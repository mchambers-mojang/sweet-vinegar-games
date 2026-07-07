import * as http from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import Database from 'better-sqlite3';
import { DEFAULT_DB_PATH, openDb, upsertPlayer, getPlayer, BOARD_CONFIG, upsertScore, getLeaderboard } from './db';

export const VALID_CHARS = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
export const CODE_LENGTH = 4;
export const MAX_ROOMS = 100;
export const DEFAULT_ROOM_EXPIRY_MS = 60_000;
export const MAX_BUFFERED_ICE = 20;
export const MAX_BODY_BYTES = 4096;

const PORT = parseInt(process.env.PORT ?? '8080', 10);

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PROFILE_PATH_RE = /^\/profile\/([^/]+)$/;
const SCORES_PATH_RE = /^\/scores(\?.*)?$/;
const LEADERBOARD_PATH_RE = /^\/leaderboard(\?.*)?$/;

export interface ServerBundle {
  wss: WebSocketServer;
  httpServer: http.Server;
}

export interface Room {
  code: string;
  creatorSdp: string;
  creator: WebSocket;
  joiner?: WebSocket;
  timer: ReturnType<typeof setTimeout> | null;
  pendingIceForJoiner: object[];  // ICE from host before joiner arrives
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

function parseJsonBody(
  req: http.IncomingMessage,
  res: http.ServerResponse,
  onSuccess: (payload: Record<string, unknown>) => void
): void {
  const chunks: Buffer[] = [];
  let bodyBytes = 0;
  let tooLarge = false;
  req.on('data', (chunk: Buffer) => {
    if (tooLarge) return;
    if (bodyBytes + chunk.length > MAX_BODY_BYTES) {
      tooLarge = true;
      res.writeHead(413, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Payload too large' }));
      req.destroy();
      return;
    }
    bodyBytes += chunk.length;
    chunks.push(chunk);
  });
  req.on('end', () => {
    if (tooLarge) return;
    const body = Buffer.concat(chunks).toString();
    let payload: Record<string, unknown>;
    try {
      payload = JSON.parse(body) as Record<string, unknown>;
    } catch {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Invalid JSON' }));
      return;
    }
    onSuccess(payload);
  });
}

export function createServer(
  port: number,
  options: { roomExpiryMs?: number; db?: Database.Database } = {}
): ServerBundle {
  const roomExpiryMs = options.roomExpiryMs ?? DEFAULT_ROOM_EXPIRY_MS;
  const db = options.db ?? openDb(DEFAULT_DB_PATH);
  const rooms = new Map<string, Room>();

  function deleteRoom(code: string): void {
    const room = rooms.get(code);
    if (room) {
      if (room.timer) clearTimeout(room.timer);
      rooms.delete(code);
    }
  }

  const httpServer = http.createServer((req, res) => {
    const url = req.url ?? '/';

    // PUT /profile
    if (req.method === 'PUT' && url === '/profile') {
      parseJsonBody(req, res, (payload) => {
        const { device_id, display_name, visible } = payload;

        if (typeof device_id !== 'string' || !UUID_RE.test(device_id)) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'device_id must be a valid UUID' }));
          return;
        }

        if (typeof display_name !== 'string') {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'display_name must be a string' }));
          return;
        }
        const trimmed = display_name.trim();
        if (trimmed.length === 0 || trimmed.length > 20) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'display_name must be a non-empty string of at most 20 characters' }));
          return;
        }

        if (visible !== undefined && typeof visible !== 'boolean') {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'visible must be a boolean' }));
          return;
        }
        const visibleInt = visible === false ? 0 : 1;

        upsertPlayer(db, device_id, trimmed, visibleInt);
        res.writeHead(204);
        res.end();
      });
      return;
    }

    // GET /profile/:device_id
    const profileMatch = PROFILE_PATH_RE.exec(url);
    if (req.method === 'GET' && profileMatch) {
      const device_id = profileMatch[1];
      if (!UUID_RE.test(device_id)) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'device_id must be a valid UUID' }));
        return;
      }
      const profile = getPlayer(db, device_id);
      if (!profile) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Profile not found' }));
        return;
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        display_name: profile.display_name,
        visible: profile.visible === 1,
        created_at: profile.created_at,
      }));
      return;
    }

    // POST /scores
    if (req.method === 'POST' && SCORES_PATH_RE.test(url)) {
      parseJsonBody(req, res, (payload) => {
        const { device_id, game, mode, value } = payload;

        if (typeof device_id !== 'string' || !UUID_RE.test(device_id)) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'device_id must be a valid UUID' }));
          return;
        }

        if (typeof game !== 'string' || !game) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'game must be a non-empty string' }));
          return;
        }

        if (typeof mode !== 'string' || !mode) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'mode must be a non-empty string' }));
          return;
        }

        const configKey = `${game}:${mode}`;
        const config = BOARD_CONFIG[configKey];
        if (!config) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: `Unknown game:mode combination: ${configKey}` }));
          return;
        }

        if (typeof value !== 'number' || !isFinite(value)) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'value must be a finite number' }));
          return;
        }

        if (value < config.min || value > config.max) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: `value must be between ${config.min} and ${config.max}` }));
          return;
        }

        const player = getPlayer(db, device_id);
        if (!player) {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Player profile not found' }));
          return;
        }

        const result = upsertScore(db, device_id, game, mode, value);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      });
      return;
    }

    // GET /leaderboard
    if (req.method === 'GET' && LEADERBOARD_PATH_RE.test(url)) {
      const queryString = url.includes('?') ? url.slice(url.indexOf('?') + 1) : '';
      const params = new URLSearchParams(queryString);
      const game = params.get('game');
      const mode = params.get('mode');
      const device_id = params.get('device_id');

      if (!game) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'game query parameter is required' }));
        return;
      }

      if (!mode) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'mode query parameter is required' }));
        return;
      }

      if (!device_id) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'device_id query parameter is required' }));
        return;
      }

      if (!UUID_RE.test(device_id)) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'device_id must be a valid UUID' }));
        return;
      }

      const configKey = `${game}:${mode}`;
      if (!BOARD_CONFIG[configKey]) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: `Unknown game:mode combination: ${configKey}` }));
        return;
      }

      const result = getLeaderboard(db, game, mode, device_id);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(result));
      return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
  });

  const wss = new WebSocketServer({ server: httpServer, maxPayload: 16384 });

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
          rooms.set(code, { code, creatorSdp: msg.sdp, creator: ws, timer, pendingIceForJoiner: [] });
          myRoomCodes.add(code);
          send(ws, { type: 'room_created', code });
          break;
        }

        case 'join': {
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
          // Send creator's offer to joiner so they can create an answer
          send(ws, { type: 'room_joined', sdp: room.creatorSdp });
          // Flush any ICE candidates from host that arrived before joiner
          for (const ice of room.pendingIceForJoiner) {
            send(ws, { type: 'ice', candidate: ice });
          }
          room.pendingIceForJoiner = [];
          // If joiner included an answer SDP, forward it to creator immediately
          if (typeof msg.sdp === 'string' && msg.sdp) {
            send(room.creator, { type: 'peer_joined', sdp: msg.sdp });
          }
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
          } else if (ws === room.creator) {
            // Host ICE arrived before joiner — buffer for flush on join
            if (room.pendingIceForJoiner.length < MAX_BUFFERED_ICE) {
              room.pendingIceForJoiner.push(msg.candidate as object);
            }
          }
          break;
        }

        case 'answer': {
          // Joiner sends answer SDP after receiving the offer via room_joined
          if (typeof msg.sdp !== 'string' || !msg.sdp) {
            send(ws, { type: 'error', message: 'Missing or empty sdp' });
            return;
          }
          const answerRoom = rooms.get(msg.code as string);
          if (!answerRoom) {
            send(ws, { type: 'error', message: 'Room not found' });
            return;
          }
          if (ws !== answerRoom.joiner) {
            send(ws, { type: 'error', message: 'Only the joiner can send an answer' });
            return;
          }
          send(answerRoom.creator, { type: 'peer_joined', sdp: msg.sdp });
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

  httpServer.listen(port);
  return { wss, httpServer };
}

if (require.main === module) {
  const { httpServer } = createServer(PORT);
  httpServer.on('listening', () => {
    console.log(`Signaling server listening on port ${PORT}`);
  });
}
