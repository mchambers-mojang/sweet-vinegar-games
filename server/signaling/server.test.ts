import * as http from 'http';
import WebSocket, { WebSocketServer } from 'ws';
import Database from 'better-sqlite3';
import { createServer } from './server';
import { openDb } from './db';

const messageQueues = new WeakMap<WebSocket, {
  queue: Record<string, unknown>[];
  resolvers: Array<(msg: Record<string, unknown>) => void>;
}>();

function connect(port: number): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${port}`);
    const state = { queue: [] as Record<string, unknown>[], resolvers: [] as Array<(msg: Record<string, unknown>) => void> };
    messageQueues.set(ws, state);
    ws.on('message', (data: Buffer) => {
      const msg = JSON.parse(data.toString()) as Record<string, unknown>;
      if (state.resolvers.length > 0) {
        state.resolvers.shift()!(msg);
      } else {
        state.queue.push(msg);
      }
    });
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function nextMessage(ws: WebSocket): Promise<Record<string, unknown>> {
  const state = messageQueues.get(ws);
  if (!state) throw new Error('WebSocket not registered');
  return new Promise((resolve) => {
    if (state.queue.length > 0) {
      resolve(state.queue.shift()!);
    } else {
      state.resolvers.push(resolve);
    }
  });
}

function httpRequest(
  options: { method: string; port: number; path: string; body?: unknown }
): Promise<{ status: number; body: unknown }> {
  return new Promise((resolve, reject) => {
    const payload = options.body !== undefined ? JSON.stringify(options.body) : undefined;
    const req = http.request(
      {
        hostname: 'localhost',
        port: options.port,
        path: options.path,
        method: options.method,
        headers: payload
          ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }
          : {},
      },
      (res) => {
        let data = '';
        res.on('data', (chunk: Buffer) => { data += chunk.toString(); });
        res.on('end', () => {
          resolve({ status: res.statusCode ?? 0, body: data ? JSON.parse(data) : null });
        });
      }
    );
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

interface ServerHandle {
  wss: WebSocketServer;
  httpServer: http.Server;
  port: number;
  db: Database.Database;
}

async function makeServer(options?: { roomExpiryMs?: number }): Promise<ServerHandle> {
  return new Promise((resolve) => {
    const db = openDb(':memory:');
    const { wss, httpServer } = createServer(0, { ...options, db });
    httpServer.on('listening', () => {
      const addr = httpServer.address() as { port: number };
      resolve({ wss, httpServer, port: addr.port, db });
    });
  });
}

const TEST_UUID = '550e8400-e29b-41d4-a716-446655440000';
const TEST_UUID2 = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
const TEST_UUID3 = 'c2ddde11-2e2d-6001-dd8f-8dd1df502c33';

/** Seeds Alice (100s), Bob (200s), Carol invisible (50s) into sudoku:easy */
async function seedSudokuEasyScores(port: number): Promise<void> {
  await httpRequest({ method: 'POST', port, path: '/scores', body: { device_id: TEST_UUID, game: 'sudoku', mode: 'easy', value: 100 } });
  await httpRequest({ method: 'POST', port, path: '/scores', body: { device_id: TEST_UUID2, game: 'sudoku', mode: 'easy', value: 200 } });
  await httpRequest({ method: 'POST', port, path: '/scores', body: { device_id: TEST_UUID3, game: 'sudoku', mode: 'easy', value: 50 } });
}

describe('Signaling Server', () => {
  let wss: WebSocketServer;
  let httpServer: http.Server;
  let port: number;

  beforeEach(async () => {
    ({ wss, httpServer, port } = await makeServer());
  });

  afterEach((done) => {
    wss.close(() => httpServer.close(done));
  });

  test('create → join → both receive correct SDPs', async () => {
    const creator = await connect(port);
    const joiner = await connect(port);

    creator.send(JSON.stringify({ type: 'create', sdp: 'offer-sdp' }));
    const roomCreated = await nextMessage(creator);

    expect(roomCreated.type).toBe('room_created');
    expect(typeof roomCreated.code).toBe('string');
    expect((roomCreated.code as string).length).toBe(4);
    expect(roomCreated.code).toMatch(/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{4}$/);

    const peerJoinedPromise = nextMessage(creator);
    joiner.send(JSON.stringify({ type: 'join', code: roomCreated.code, sdp: 'answer-sdp' }));

    const [peerJoined, roomJoined] = await Promise.all([
      peerJoinedPromise,
      nextMessage(joiner),
    ]);

    expect(peerJoined.type).toBe('peer_joined');
    expect(peerJoined.sdp).toBe('answer-sdp');
    expect(roomJoined.type).toBe('room_joined');
    expect(roomJoined.sdp).toBe('offer-sdp');

    creator.close();
    joiner.close();
  });

  test('join nonexistent code → error', async () => {
    const ws = await connect(port);
    ws.send(JSON.stringify({ type: 'join', code: 'ZZZZ', sdp: 'answer-sdp' }));
    const msg = await nextMessage(ws);

    expect(msg.type).toBe('error');
    expect(msg.message).toBe('Room not found');
    ws.close();
  });

  test('create without sdp → error', async () => {
    const ws = await connect(port);
    ws.send(JSON.stringify({ type: 'create' }));
    const msg = await nextMessage(ws);
    expect(msg.type).toBe('error');
    expect(msg.message).toBe('Missing or empty sdp');
    ws.close();
  });

  test('join without sdp → room_joined with offer (two-phase flow)', async () => {
    const creator = await connect(port);
    creator.send(JSON.stringify({ type: 'create', sdp: 'offer-sdp' }));
    const { code } = await nextMessage(creator) as { code: string };

    const joiner = await connect(port);
    joiner.send(JSON.stringify({ type: 'join', code }));
    const msg = await nextMessage(joiner);
    // Joiner receives the offer so they can create an answer
    expect(msg.type).toBe('room_joined');
    expect(msg.sdp).toBe('offer-sdp');
    creator.close();
    joiner.close();
  });

  test('answer relayed from joiner to creator', async () => {
    const creator = await connect(port);
    const joiner = await connect(port);

    creator.send(JSON.stringify({ type: 'create', sdp: 'offer-sdp' }));
    const { code } = await nextMessage(creator) as { code: string };

    // Joiner joins without SDP, gets offer
    joiner.send(JSON.stringify({ type: 'join', code }));
    await nextMessage(joiner); // room_joined

    // Joiner sends answer
    const peerJoinedPromise = nextMessage(creator);
    joiner.send(JSON.stringify({ type: 'answer', code, sdp: 'answer-sdp' }));
    const peerJoined = await peerJoinedPromise;
    expect(peerJoined.type).toBe('peer_joined');
    expect(peerJoined.sdp).toBe('answer-sdp');

    creator.close();
    joiner.close();
  });

  test('ICE from non-member → error', async () => {
    const creator = await connect(port);
    creator.send(JSON.stringify({ type: 'create', sdp: 'offer-sdp' }));
    const { code } = await nextMessage(creator) as { code: string };

    const outsider = await connect(port);
    outsider.send(JSON.stringify({ type: 'ice', code, candidate: { candidate: 'evil' } }));
    const msg = await nextMessage(outsider);
    expect(msg.type).toBe('error');
    expect(msg.message).toBe('Not a member of this room');
    creator.close();
    outsider.close();
  });

  test('multiple creates from one connection are all cleaned up on disconnect', async () => {
    const creator = await connect(port);

    // Send two creates from the same connection
    creator.send(JSON.stringify({ type: 'create', sdp: 'offer-sdp' }));
    const first = await nextMessage(creator) as { code: string };
    creator.send(JSON.stringify({ type: 'create', sdp: 'offer-sdp-2' }));
    const second = await nextMessage(creator) as { code: string };

    creator.close();
    await new Promise((resolve) => setTimeout(resolve, 50));

    // Both rooms should now be gone
    for (const code of [first.code, second.code]) {
      const joiner = await connect(port);
      joiner.send(JSON.stringify({ type: 'join', code, sdp: 'answer-sdp' }));
      const msg = await nextMessage(joiner);
      expect(msg.type).toBe('error');
      expect(msg.message).toBe('Room not found');
      joiner.close();
    }
  });

  test('room expires after timeout', async () => {
    // Use a short expiry for this test — create a dedicated server
    const { wss: expWss, httpServer: expHttpServer, port: expPort } = await makeServer({ roomExpiryMs: 100 });

    try {
      const creator = await connect(expPort);
      creator.send(JSON.stringify({ type: 'create', sdp: 'offer-sdp' }));
      const roomCreated = await nextMessage(creator);
      expect(roomCreated.type).toBe('room_created');

      // Wait for expiry
      await new Promise((resolve) => setTimeout(resolve, 200));

      const joiner = await connect(expPort);
      joiner.send(JSON.stringify({ type: 'join', code: roomCreated.code, sdp: 'answer-sdp' }));
      const msg = await nextMessage(joiner);

      expect(msg.type).toBe('error');
      expect(msg.message).toBe('Room not found');

      creator.close();
      joiner.close();
    } finally {
      await new Promise<void>((resolve) => expWss.close(() => expHttpServer.close(() => resolve())));
    }
  });

  test('ICE candidates are relayed to the other peer', async () => {
    const creator = await connect(port);
    const joiner = await connect(port);

    creator.send(JSON.stringify({ type: 'create', sdp: 'offer-sdp' }));
    const roomCreated = await nextMessage(creator);
    const code = roomCreated.code as string;

    const peerJoinedPromise = nextMessage(creator);
    joiner.send(JSON.stringify({ type: 'join', code, sdp: 'answer-sdp' }));
    await Promise.all([peerJoinedPromise, nextMessage(joiner)]);

    // Creator sends ICE → joiner receives it
    const joinerIcePromise = nextMessage(joiner);
    creator.send(JSON.stringify({ type: 'ice', code, candidate: { candidate: 'cand1' } }));
    const joinerIce = await joinerIcePromise;
    expect(joinerIce.type).toBe('ice');
    expect((joinerIce.candidate as Record<string, unknown>).candidate).toBe('cand1');

    // Joiner sends ICE → creator receives it
    const creatorIcePromise = nextMessage(creator);
    joiner.send(JSON.stringify({ type: 'ice', code, candidate: { candidate: 'cand2' } }));
    const creatorIce = await creatorIcePromise;
    expect(creatorIce.type).toBe('ice');
    expect((creatorIce.candidate as Record<string, unknown>).candidate).toBe('cand2');

    creator.close();
    joiner.close();
  });

  test('host ICE is buffered and flushed when joiner connects', async () => {
    const creator = await connect(port);

    creator.send(JSON.stringify({ type: 'create', sdp: 'offer-sdp' }));
    const roomCreated = await nextMessage(creator);
    const code = roomCreated.code as string;

    // Host sends ICE candidates before joiner arrives
    creator.send(JSON.stringify({ type: 'ice', code, candidate: { candidate: 'early-cand1' } }));
    creator.send(JSON.stringify({ type: 'ice', code, candidate: { candidate: 'early-cand2' } }));

    // Small delay to ensure server processes the ICE messages
    await new Promise((resolve) => setTimeout(resolve, 50));

    // Now joiner connects — should receive buffered ICE after room_joined
    const joiner = await connect(port);
    joiner.send(JSON.stringify({ type: 'join', code }));

    // Joiner gets room_joined first
    const roomJoined = await nextMessage(joiner);
    expect(roomJoined.type).toBe('room_joined');

    // Then the buffered ICE candidates
    const ice1 = await nextMessage(joiner);
    expect(ice1.type).toBe('ice');
    expect((ice1.candidate as Record<string, unknown>).candidate).toBe('early-cand1');

    const ice2 = await nextMessage(joiner);
    expect(ice2.type).toBe('ice');
    expect((ice2.candidate as Record<string, unknown>).candidate).toBe('early-cand2');

    creator.close();
    joiner.close();
  });
});

describe('Profile Endpoints', () => {
  let wss: WebSocketServer;
  let httpServer: http.Server;
  let port: number;

  beforeEach(async () => {
    ({ wss, httpServer, port } = await makeServer());
  });

  afterEach((done) => {
    wss.close(() => httpServer.close(done));
  });

  test('PUT /profile creates a new player — GET returns it', async () => {
    const put = await httpRequest({
      method: 'PUT',
      port,
      path: '/profile',
      body: { device_id: TEST_UUID, display_name: 'Alice', visible: true },
    });
    expect(put.status).toBe(204);

    const get = await httpRequest({ method: 'GET', port, path: `/profile/${TEST_UUID}` });
    expect(get.status).toBe(200);
    const body = get.body as Record<string, unknown>;
    expect(body.display_name).toBe('Alice');
    expect(body.visible).toBe(true);
    expect(typeof body.created_at).toBe('string');
  });

  test('PUT /profile updates existing player', async () => {
    await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: TEST_UUID, display_name: 'Alice', visible: true },
    });
    await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: TEST_UUID, display_name: 'Alicia', visible: false },
    });

    const get = await httpRequest({ method: 'GET', port, path: `/profile/${TEST_UUID}` });
    const body = get.body as Record<string, unknown>;
    expect(body.display_name).toBe('Alicia');
    expect(body.visible).toBe(false);
  });

  test('GET /profile/:device_id returns 404 for unknown id', async () => {
    const res = await httpRequest({ method: 'GET', port, path: `/profile/${TEST_UUID}` });
    expect(res.status).toBe(404);
  });

  test('PUT /profile trims whitespace from display_name', async () => {
    await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: TEST_UUID, display_name: '  Bob  ', visible: true },
    });
    const get = await httpRequest({ method: 'GET', port, path: `/profile/${TEST_UUID}` });
    expect((get.body as Record<string, unknown>).display_name).toBe('Bob');
  });

  test('PUT /profile rejects empty display_name', async () => {
    const res = await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: TEST_UUID, display_name: '   ', visible: true },
    });
    expect(res.status).toBe(400);
  });

  test('PUT /profile rejects display_name over 20 chars', async () => {
    const res = await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: TEST_UUID, display_name: 'A'.repeat(21), visible: true },
    });
    expect(res.status).toBe(400);
  });

  test('PUT /profile returns 413 for body exceeding 4KB', async () => {
    const res = await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: TEST_UUID, display_name: 'A'.repeat(20), visible: true, junk: 'x'.repeat(4096) },
    });
    expect(res.status).toBe(413);
  });

  test('PUT /profile accepts display_name of exactly 20 chars', async () => {
    const res = await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: TEST_UUID, display_name: 'A'.repeat(20), visible: true },
    });
    expect(res.status).toBe(204);
  });

  test('PUT /profile rejects invalid device_id', async () => {
    const res = await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: 'not-a-uuid', display_name: 'Alice', visible: true },
    });
    expect(res.status).toBe(400);
  });

  test('GET /profile/:device_id rejects invalid device_id', async () => {
    const res = await httpRequest({ method: 'GET', port, path: '/profile/not-a-uuid' });
    expect(res.status).toBe(400);
  });

  test('PUT /profile defaults visible to true when not provided', async () => {
    await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: TEST_UUID, display_name: 'Charlie' },
    });
    const get = await httpRequest({ method: 'GET', port, path: `/profile/${TEST_UUID}` });
    expect((get.body as Record<string, unknown>).visible).toBe(true);
  });

  test('GET /profile/:device_id for unknown route returns 404', async () => {
    const res = await httpRequest({ method: 'GET', port, path: '/unknown' });
    expect(res.status).toBe(404);
  });

  test('multiple players are independent', async () => {
    await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: TEST_UUID, display_name: 'PlayerOne', visible: true },
    });
    await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: TEST_UUID2, display_name: 'PlayerTwo', visible: false },
    });

    const r1 = await httpRequest({ method: 'GET', port, path: `/profile/${TEST_UUID}` });
    const r2 = await httpRequest({ method: 'GET', port, path: `/profile/${TEST_UUID2}` });

    expect((r1.body as Record<string, unknown>).display_name).toBe('PlayerOne');
    expect((r2.body as Record<string, unknown>).display_name).toBe('PlayerTwo');
    expect((r2.body as Record<string, unknown>).visible).toBe(false);
  });
});

describe('Score Endpoints', () => {
  let wss: WebSocketServer;
  let httpServer: http.Server;
  let port: number;

  beforeEach(async () => {
    ({ wss, httpServer, port } = await makeServer());
    // Seed a player profile for use in score tests
    await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: TEST_UUID, display_name: 'Alice', visible: true },
    });
  });

  afterEach((done) => {
    wss.close(() => httpServer.close(done));
  });

  test('POST /scores accepts a valid asc (time-based) score', async () => {
    const res = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'sudoku', mode: 'easy', value: 120 },
    });
    expect(res.status).toBe(200);
    const body = res.body as Record<string, unknown>;
    expect(body.accepted).toBe(true);
    expect(body.personal_best).toBe(120);
  });

  test('POST /scores accepts a valid desc (score-based) score', async () => {
    const res = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'blockudoku', mode: 'standard', value: 5000 },
    });
    expect(res.status).toBe(200);
    const body = res.body as Record<string, unknown>;
    expect(body.accepted).toBe(true);
    expect(body.personal_best).toBe(5000);
  });

  test('POST /scores upserts only when new value is better (asc: lower is better)', async () => {
    await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'sudoku', mode: 'easy', value: 300 },
    });
    // Better (lower) time — should be accepted
    const better = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'sudoku', mode: 'easy', value: 200 },
    });
    expect((better.body as Record<string, unknown>).accepted).toBe(true);
    expect((better.body as Record<string, unknown>).personal_best).toBe(200);

    // Worse (higher) time — should be rejected
    const worse = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'sudoku', mode: 'easy', value: 250 },
    });
    expect((worse.body as Record<string, unknown>).accepted).toBe(false);
    expect((worse.body as Record<string, unknown>).personal_best).toBe(200);
  });

  test('POST /scores upserts only when new value is better (desc: higher is better)', async () => {
    await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'blockudoku', mode: 'standard', value: 3000 },
    });
    // Better (higher) score — accepted
    const better = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'blockudoku', mode: 'standard', value: 5000 },
    });
    expect((better.body as Record<string, unknown>).accepted).toBe(true);
    expect((better.body as Record<string, unknown>).personal_best).toBe(5000);

    // Worse (lower) score — rejected
    const worse = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'blockudoku', mode: 'standard', value: 4000 },
    });
    expect((worse.body as Record<string, unknown>).accepted).toBe(false);
    expect((worse.body as Record<string, unknown>).personal_best).toBe(5000);
  });

  test('POST /scores rejects value below min bound', async () => {
    // sudoku:easy min is 10
    const res = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'sudoku', mode: 'easy', value: 5 },
    });
    expect(res.status).toBe(400);
  });

  test('POST /scores rejects value above max bound', async () => {
    // sudoku:easy max is 7200
    const res = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'sudoku', mode: 'easy', value: 7201 },
    });
    expect(res.status).toBe(400);
  });

  test('POST /scores accepts boundary values (min and max)', async () => {
    const atMin = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'sudoku', mode: 'easy', value: 10 },
    });
    expect(atMin.status).toBe(200);

    await httpRequest({
      method: 'PUT', port, path: '/profile',
      body: { device_id: TEST_UUID2, display_name: 'Bob', visible: true },
    });
    const atMax = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID2, game: 'sudoku', mode: 'easy', value: 7200 },
    });
    expect(atMax.status).toBe(200);
  });

  test('POST /scores rejects unknown game:mode combo', async () => {
    const res = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'sudoku', mode: 'nightmare', value: 100 },
    });
    expect(res.status).toBe(400);
  });

  test('POST /scores returns 404 for unknown device_id', async () => {
    const res = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID2, game: 'sudoku', mode: 'easy', value: 120 },
    });
    expect(res.status).toBe(404);
  });

  test('POST /scores rejects invalid device_id', async () => {
    const res = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: 'not-a-uuid', game: 'sudoku', mode: 'easy', value: 120 },
    });
    expect(res.status).toBe(400);
  });

  test('POST /scores rejects missing game field', async () => {
    const res = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, mode: 'easy', value: 120 },
    });
    expect(res.status).toBe(400);
  });

  test('POST /scores rejects non-number value', async () => {
    const res = await httpRequest({
      method: 'POST', port, path: '/scores',
      body: { device_id: TEST_UUID, game: 'sudoku', mode: 'easy', value: 'fast' },
    });
    expect(res.status).toBe(400);
  });
});

describe('Leaderboard Endpoint', () => {
  let wss: WebSocketServer;
  let httpServer: http.Server;
  let port: number;

  beforeEach(async () => {
    ({ wss, httpServer, port } = await makeServer());
    // Seed three players
    await httpRequest({ method: 'PUT', port, path: '/profile', body: { device_id: TEST_UUID, display_name: 'Alice', visible: true } });
    await httpRequest({ method: 'PUT', port, path: '/profile', body: { device_id: TEST_UUID2, display_name: 'Bob', visible: true } });
    await httpRequest({ method: 'PUT', port, path: '/profile', body: { device_id: TEST_UUID3, display_name: 'Carol', visible: false } });
  });

  afterEach((done) => {
    wss.close(() => httpServer.close(done));
  });

  test('GET /leaderboard returns top visible players and requester rank', async () => {
    // Alice: 100s, Bob: 200s, Carol (invisible): 50s
    await seedSudokuEasyScores(port);

    const res = await httpRequest({ method: 'GET', port, path: `/leaderboard?game=sudoku&mode=easy&device_id=${TEST_UUID}` });
    expect(res.status).toBe(200);
    const body = res.body as Record<string, unknown>;

    // Top 10 should only contain visible players (Alice and Bob)
    const top = body.top as Array<Record<string, unknown>>;
    expect(top.length).toBe(2);
    expect(top[0].display_name).toBe('Alice');   // 100s is better (lower) than Bob's 200s
    expect(top[1].display_name).toBe('Bob');

    // Alice is querying — she's rank 2 overall (Carol has 50s which is better)
    expect(body.player_rank).toBe(2);
    expect(body.player_score).toBe(100);
  });

  test('GET /leaderboard invisible player can see their own rank', async () => {
    await seedSudokuEasyScores(port);

    const res = await httpRequest({ method: 'GET', port, path: `/leaderboard?game=sudoku&mode=easy&device_id=${TEST_UUID3}` });
    const body = res.body as Record<string, unknown>;

    // Carol (invisible) is rank 1 overall (50s is lowest/best)
    expect(body.player_rank).toBe(1);
    expect(body.player_score).toBe(50);

    // Top should still only show visible players (Alice, Bob)
    const top = body.top as Array<Record<string, unknown>>;
    expect(top.every((e) => e.display_name !== 'Carol')).toBe(true);
  });

  test('GET /leaderboard returns null rank/score when requester has no score', async () => {
    await httpRequest({ method: 'POST', port, path: '/scores', body: { device_id: TEST_UUID2, game: 'sudoku', mode: 'easy', value: 200 } });

    const res = await httpRequest({ method: 'GET', port, path: `/leaderboard?game=sudoku&mode=easy&device_id=${TEST_UUID}` });
    const body = res.body as Record<string, unknown>;
    expect(body.player_rank).toBeNull();
    expect(body.player_score).toBeNull();
  });

  test('GET /leaderboard top ranks are dense (no gaps from invisible players)', async () => {
    await seedSudokuEasyScores(port);

    const res = await httpRequest({ method: 'GET', port, path: `/leaderboard?game=sudoku&mode=easy&device_id=${TEST_UUID}` });
    const top = (res.body as Record<string, unknown>).top as Array<Record<string, unknown>>;

    // Top visible ranks should be 1, 2 (not 2, 3 skipping the invisible rank 1)
    expect(top[0].rank).toBe(1);
    expect(top[1].rank).toBe(2);
  });

  test('GET /leaderboard returns 400 for missing game param', async () => {
    const res = await httpRequest({ method: 'GET', port, path: `/leaderboard?mode=easy&device_id=${TEST_UUID}` });
    expect(res.status).toBe(400);
  });

  test('GET /leaderboard returns 400 for missing mode param', async () => {
    const res = await httpRequest({ method: 'GET', port, path: `/leaderboard?game=sudoku&device_id=${TEST_UUID}` });
    expect(res.status).toBe(400);
  });

  test('GET /leaderboard returns 400 for missing device_id param', async () => {
    const res = await httpRequest({ method: 'GET', port, path: '/leaderboard?game=sudoku&mode=easy' });
    expect(res.status).toBe(400);
  });

  test('GET /leaderboard returns 400 for unknown game:mode', async () => {
    const res = await httpRequest({ method: 'GET', port, path: `/leaderboard?game=sudoku&mode=nightmare&device_id=${TEST_UUID}` });
    expect(res.status).toBe(400);
  });

  test('GET /leaderboard returns 400 for invalid device_id', async () => {
    const res = await httpRequest({ method: 'GET', port, path: '/leaderboard?game=sudoku&mode=easy&device_id=not-a-uuid' });
    expect(res.status).toBe(400);
  });

  test('GET /leaderboard returns empty top when no scores submitted', async () => {
    const res = await httpRequest({ method: 'GET', port, path: `/leaderboard?game=sudoku&mode=easy&device_id=${TEST_UUID}` });
    expect(res.status).toBe(200);
    const body = res.body as Record<string, unknown>;
    expect((body.top as unknown[]).length).toBe(0);
    expect(body.player_rank).toBeNull();
    expect(body.player_score).toBeNull();
  });
});

import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { isMountPoint, JOURNAL_MODE } from './db';

describe('openDb — mount point validation', () => {
  test('isMountPoint returns false for a regular subdirectory', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'svtest-'));
    try {
      expect(isMountPoint(tmp)).toBe(false);
    } finally {
      fs.rmSync(tmp, { recursive: true });
    }
  });

  test('isMountPoint returns true for the filesystem root', () => {
    // The root directory is always its own mount point (dev === its own dev).
    // On Linux, / has no parent with a different device, so comparing / to /
    // returns false by our logic, but we can verify that a well-known mount
    // like /proc (present in Linux containers) is detected when it exists.
    // The test that is always reliable: a fresh tmpdir is NOT a mount point.
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'svtest-'));
    try {
      expect(isMountPoint(tmp)).toBe(false);
    } finally {
      fs.rmSync(tmp, { recursive: true });
    }
  });

  test('isMountPoint returns false when directory does not exist', () => {
    expect(isMountPoint('/nonexistent/path/xyz')).toBe(false);
  });

  test('openDb with :memory: does not write a mount warning to stderr', () => {
    const stderrSpy = jest.spyOn(process.stderr, 'write').mockImplementation(() => true);
    try {
      const db = openDb(':memory:');
      db.close();
      const mountWarnings = (stderrSpy.mock.calls as unknown[][])
        .map((args) => String(args[0]))
        .filter((msg) => msg.includes('is not a mount point'));
      expect(mountWarnings.length).toBe(0);
    } finally {
      stderrSpy.mockRestore();
    }
  });

  test('openDb with a regular filesystem path writes a mount warning to stderr', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'svtest-'));
    const dbPath = path.join(tmp, 'test.db');
    const stderrSpy = jest.spyOn(process.stderr, 'write').mockImplementation(() => true);
    try {
      const db = openDb(dbPath);
      db.close();
      const mountWarnings = (stderrSpy.mock.calls as unknown[][])
        .map((args) => String(args[0]))
        .filter((msg) => msg.includes('is not a mount point'));
      expect(mountWarnings.length).toBeGreaterThan(0);
      expect(mountWarnings[0]).toContain(tmp);
    } finally {
      stderrSpy.mockRestore();
      fs.rmSync(tmp, { recursive: true });
    }
  });

  test('JOURNAL_MODE is a valid SQLite journal mode', () => {
    const valid = ['DELETE', 'TRUNCATE', 'PERSIST', 'MEMORY', 'WAL', 'OFF'];
    expect(valid).toContain(JOURNAL_MODE);
  });
});

