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
});
