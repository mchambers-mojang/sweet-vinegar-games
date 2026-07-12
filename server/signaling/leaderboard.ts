import * as http from 'http';
import Database from 'better-sqlite3';
import { upsertPlayer, getPlayer, BoardConfigEntry, BOARD_CONFIG, upsertScore, getLeaderboard, deletePlayerScores } from './db';

export const MAX_BODY_BYTES = 4096;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PROFILE_PATH_RE = /^\/profile\/([^/]+)$/;
const SCORES_PATH_RE = /^\/scores(\?.*)?$/;
const SCORES_DEVICE_PATH_RE = /^\/scores\/([^/?]+)(\?.*)?$/;
const LEADERBOARD_PATH_RE = /^\/leaderboard(\?.*)?$/;

function parseJsonBody(
  req: http.IncomingMessage,
  res: http.ServerResponse,
  onSuccess: (payload: Record<string, unknown>) => void
): void {
  const chunks: Buffer[] = [];
  let bodyBytes = 0;
  let tooLarge = false;
  req.on('error', () => {
    if (!res.writableEnded) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Request error' }));
    }
  });
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

/**
 * Validates that game and mode refer to a known BOARD_CONFIG entry.
 * Returns the config on success, or writes a 400 response and returns null.
 */
function resolveGameMode(
  res: http.ServerResponse,
  game: string,
  mode: string
): BoardConfigEntry | null {
  const configKey = `${game}:${mode}`;
  const config = BOARD_CONFIG[configKey];
  if (!config) {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Invalid game or mode' }));
    return null;
  }
  return config;
}

/**
 * Handles all leaderboard and profile HTTP routes.
 * Returns true if the request was matched and will be responded to,
 * false if no route matched (caller should send a 404).
 */
export function handleLeaderboardRequest(
  db: Database.Database,
  req: http.IncomingMessage,
  res: http.ServerResponse
): boolean {
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
    return true;
  }

  // GET /profile/:device_id
  const profileMatch = PROFILE_PATH_RE.exec(url);
  if (req.method === 'GET' && profileMatch) {
    const device_id = profileMatch[1];
    if (!UUID_RE.test(device_id)) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'device_id must be a valid UUID' }));
      return true;
    }
    const profile = getPlayer(db, device_id);
    if (!profile) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Profile not found' }));
      return true;
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      display_name: profile.display_name,
      visible: profile.visible === 1,
      created_at: profile.created_at,
    }));
    return true;
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

      const config = resolveGameMode(res, game, mode);
      if (!config) return;

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
    return true;
  }

  // DELETE /scores/:device_id — remove all scores for a player
  const scoresDeviceMatch = SCORES_DEVICE_PATH_RE.exec(url);
  if (req.method === 'DELETE' && scoresDeviceMatch) {
    const device_id = scoresDeviceMatch[1];
    if (!UUID_RE.test(device_id)) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'device_id must be a valid UUID' }));
      return true;
    }
    if (!getPlayer(db, device_id)) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Player profile not found' }));
      return true;
    }
    const queryString = url.includes('?') ? url.slice(url.indexOf('?') + 1) : '';
    const params = new URLSearchParams(queryString);
    const purgeProfile = params.get('purge_profile') === 'true';
    deletePlayerScores(db, device_id, purgeProfile);
    res.writeHead(204);
    res.end();
    return true;
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
      return true;
    }

    if (!mode) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'mode query parameter is required' }));
      return true;
    }

    if (!device_id) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'device_id query parameter is required' }));
      return true;
    }

    if (!UUID_RE.test(device_id)) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'device_id must be a valid UUID' }));
      return true;
    }

    if (!resolveGameMode(res, game, mode)) return true;

    const result = getLeaderboard(db, game, mode, device_id);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(result));
    return true;
  }

  return false;
}
