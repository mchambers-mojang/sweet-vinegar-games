import { WebSocketServer, WebSocket } from 'ws';

export const VALID_CHARS = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
export const CODE_LENGTH = 4;
export const MAX_ROOMS = 100;
export const DEFAULT_ROOM_EXPIRY_MS = 60_000;

const PORT = parseInt(process.env.PORT ?? '8080', 10);

export interface Room {
  code: string;
  creatorSdp: string;
  creator: WebSocket;
  joiner?: WebSocket;
  timer: ReturnType<typeof setTimeout> | null;
}

export function generateCode(existing: Map<string, unknown>): string {
  let code: string;
  do {
    code = Array.from({ length: CODE_LENGTH }, () =>
      VALID_CHARS[Math.floor(Math.random() * VALID_CHARS.length)]
    ).join('');
  } while (existing.has(code));
  return code;
}

function send(ws: WebSocket, data: object): void {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(data));
  }
}

export function createServer(
  port: number,
  options: { roomExpiryMs?: number } = {}
): WebSocketServer {
  const roomExpiryMs = options.roomExpiryMs ?? DEFAULT_ROOM_EXPIRY_MS;
  const rooms = new Map<string, Room>();

  function deleteRoom(code: string): void {
    const room = rooms.get(code);
    if (room) {
      if (room.timer) clearTimeout(room.timer);
      rooms.delete(code);
    }
  }

  const wss = new WebSocketServer({ port });

  wss.on('connection', (ws: WebSocket) => {
    // Track all rooms this connection owns so every room is cleaned up on disconnect,
    // even if the client sent multiple `create` messages.
    const myRoomCodes = new Set<string>();

    ws.on('message', (raw: Buffer) => {
      let msg: Record<string, unknown>;
      try {
        msg = JSON.parse(raw.toString()) as Record<string, unknown>;
      } catch {
        send(ws, { type: 'error', message: 'Invalid JSON' });
        return;
      }

      switch (msg.type) {
        case 'create': {
          if (typeof msg.sdp !== 'string' || !msg.sdp) {
            send(ws, { type: 'error', message: 'Missing or empty sdp' });
            return;
          }
          if (rooms.size >= MAX_ROOMS) {
            send(ws, { type: 'error', message: 'Server full' });
            return;
          }
          const code = generateCode(rooms);
          const timer = setTimeout(() => deleteRoom(code), roomExpiryMs);
          rooms.set(code, { code, creatorSdp: msg.sdp, creator: ws, timer });
          myRoomCodes.add(code);
          send(ws, { type: 'room_created', code });
          break;
        }

        case 'join': {
          if (typeof msg.sdp !== 'string' || !msg.sdp) {
            send(ws, { type: 'error', message: 'Missing or empty sdp' });
            return;
          }
          const room = rooms.get(msg.code as string);
          if (!room) {
            send(ws, { type: 'error', message: 'Room not found' });
            return;
          }
          if (room.joiner) {
            send(ws, { type: 'error', message: 'Room already full' });
            return;
          }
          if (room.timer) {
            clearTimeout(room.timer);
            room.timer = null;
          }
          room.joiner = ws;
          myRoomCodes.add(msg.code as string);
          send(room.creator, { type: 'peer_joined', sdp: msg.sdp });
          send(ws, { type: 'room_joined', sdp: room.creatorSdp });
          break;
        }

        case 'ice': {
          const room = rooms.get(msg.code as string);
          if (!room) {
            send(ws, { type: 'error', message: 'Room not found' });
            return;
          }
          if (ws !== room.creator && ws !== room.joiner) {
            send(ws, { type: 'error', message: 'Not a member of this room' });
            return;
          }
          const other = ws === room.creator ? room.joiner : room.creator;
          if (other) {
            send(other, { type: 'ice', candidate: msg.candidate });
          }
          break;
        }

        default:
          send(ws, { type: 'error', message: 'Unknown message type' });
      }
    });

    ws.on('close', () => {
      for (const code of myRoomCodes) {
        deleteRoom(code);
      }
    });
  });

  return wss;
}

if (require.main === module) {
  const server = createServer(PORT);
  server.on('listening', () => {
    console.log(`Signaling server listening on port ${PORT}`);
  });
}
