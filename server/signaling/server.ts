import * as http from 'http';
import { WebSocketServer } from 'ws';
import Database from 'better-sqlite3';
import { DEFAULT_DB_PATH, openDb } from './db';
import { Room, DEFAULT_ROOM_EXPIRY_MS, attachSignaling, generateCode, VALID_CHARS, CODE_LENGTH, MAX_ROOMS, MAX_BUFFERED_ICE } from './signaling';
import { MAX_BODY_BYTES, handleLeaderboardRequest } from './leaderboard';

export { VALID_CHARS, CODE_LENGTH, MAX_ROOMS, DEFAULT_ROOM_EXPIRY_MS, MAX_BUFFERED_ICE, MAX_BODY_BYTES, generateCode };
export type { Room };

export interface ServerBundle {
  wss: WebSocketServer;
  httpServer: http.Server;
}

const PORT = parseInt(process.env.PORT ?? '8080', 10);

export function createServer(
  port: number,
  options: { roomExpiryMs?: number; db?: Database.Database } = {}
): ServerBundle {
  const roomExpiryMs = options.roomExpiryMs ?? DEFAULT_ROOM_EXPIRY_MS;
  const db = options.db ?? openDb(DEFAULT_DB_PATH);
  const rooms = new Map<string, Room>();

  const httpServer = http.createServer((req, res) => {
    if (handleLeaderboardRequest(db, req, res)) return;
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
  });

  const wss = attachSignaling(httpServer, { rooms, roomExpiryMs });

  httpServer.listen(port);
  return { wss, httpServer };
}

if (require.main === module) {
  const { httpServer } = createServer(PORT);
  httpServer.on('listening', () => {
    console.log(`Signaling server listening on port ${PORT}`);
  });
}
