import WebSocket, { WebSocketServer } from 'ws';
import { createServer } from './server';

function connect(port: number): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${port}`);
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function nextMessage(ws: WebSocket): Promise<Record<string, unknown>> {
  return new Promise((resolve) => {
    ws.once('message', (data: Buffer) => resolve(JSON.parse(data.toString())));
  });
}

async function makeServer(options?: { roomExpiryMs?: number }): Promise<{ wss: WebSocketServer; port: number }> {
  return new Promise((resolve) => {
    const wss = createServer(0, options);
    wss.on('listening', () => {
      const addr = wss.address() as { port: number };
      resolve({ wss, port: addr.port });
    });
  });
}

describe('Signaling Server', () => {
  let wss: WebSocketServer;
  let port: number;

  beforeEach(async () => {
    ({ wss, port } = await makeServer());
  });

  afterEach((done) => {
    wss.close(done);
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
    const { wss: expWss, port: expPort } = await makeServer({ roomExpiryMs: 100 });

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
      await new Promise<void>((resolve) => expWss.close(() => resolve()));
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
