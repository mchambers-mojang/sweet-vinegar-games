import Database from 'better-sqlite3';
import * as fs from 'fs';
import * as path from 'path';

export const DEFAULT_DB_PATH = process.env.DB_PATH ?? '/home/data/vinegar.db';

const VALID_JOURNAL_MODES = ['DELETE', 'TRUNCATE', 'PERSIST', 'MEMORY', 'WAL', 'OFF'] as const;
type JournalMode = typeof VALID_JOURNAL_MODES[number];

function resolveJournalMode(): JournalMode {
  const raw = (process.env.SQLITE_JOURNAL_MODE ?? 'WAL').toUpperCase();
  if ((VALID_JOURNAL_MODES as readonly string[]).includes(raw)) return raw as JournalMode;
  process.stderr.write(`[WARNING] Unknown SQLITE_JOURNAL_MODE="${raw}"; falling back to WAL. Valid modes: DELETE, TRUNCATE, PERSIST, MEMORY, WAL, OFF.\n`);
  return 'WAL';
}

export const JOURNAL_MODE: JournalMode = resolveJournalMode();

/**
 * Returns true when dir resides on a different block device than its parent —
 * a reliable proxy for "this is a real mount point" on Linux.
 */
export function isMountPoint(dir: string): boolean {
  try {
    return fs.statSync(dir).dev !== fs.statSync(path.dirname(dir)).dev;
  } catch {
    return false;
  }
}

export interface PlayerProfile {
  device_id: string;
  display_name: string;
  visible: number;
  created_at: string;
}

export interface BoardConfigEntry {
  sort: 'asc' | 'desc';
  min: number;
  max: number;
}

export const BOARD_CONFIG: Record<string, BoardConfigEntry> = {
  'sudoku:easy':          { sort: 'asc',  min: 10,  max: 7200   },
  'sudoku:medium':        { sort: 'asc',  min: 15,  max: 7200   },
  'sudoku:hard':          { sort: 'asc',  min: 30,  max: 7200   },
  'sudoku:expert':        { sort: 'asc',  min: 60,  max: 7200   },
  'shikaku:5':            { sort: 'asc',  min: 3,   max: 3600   },
  'shikaku:7':            { sort: 'asc',  min: 5,   max: 3600   },
  'shikaku:8':            { sort: 'asc',  min: 8,   max: 3600   },
  'shikaku:10':           { sort: 'asc',  min: 10,  max: 3600   },
  'shikaku:12':           { sort: 'asc',  min: 15,  max: 3600   },
  'shikaku:15':           { sort: 'asc',  min: 20,  max: 3600   },
  'blockudoku:standard':  { sort: 'desc', min: 0,   max: 999999 },
};

export interface ScoreEntry {
  device_id: string;
  display_name: string;
  value: number;
  rank: number;
}

export function openDb(dbPath: string): Database.Database {
  const dir = path.dirname(dbPath);
  if (dbPath !== ':memory:' && !fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  if (dbPath !== ':memory:' && !isMountPoint(dir)) {
    process.stderr.write(
      `[WARNING] "${dir}" is not a mount point. On Azure App Service, mount an Azure Files ` +
      `share at "${dir}" to prevent data loss on redeploy.\n`
    );
  }

  const db = new Database(dbPath);
  db.pragma(`journal_mode = ${JOURNAL_MODE}`);

  db.exec(`
    CREATE TABLE IF NOT EXISTS players (
      device_id TEXT PRIMARY KEY,
      display_name TEXT NOT NULL,
      visible INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS scores (
      device_id TEXT NOT NULL,
      game TEXT NOT NULL,
      mode TEXT NOT NULL,
      value REAL NOT NULL,
      submitted_at TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (device_id, game, mode),
      FOREIGN KEY (device_id) REFERENCES players(device_id)
    )
  `);

  return db;
}

export function upsertPlayer(
  db: Database.Database,
  device_id: string,
  display_name: string,
  visible: number
): void {
  db.prepare(`
    INSERT INTO players (device_id, display_name, visible)
    VALUES (?, ?, ?)
    ON CONFLICT(device_id) DO UPDATE SET
      display_name = excluded.display_name,
      visible = excluded.visible
  `).run(device_id, display_name, visible);
}

export function getPlayer(
  db: Database.Database,
  device_id: string
): PlayerProfile | undefined {
  return db
    .prepare('SELECT device_id, display_name, visible, created_at FROM players WHERE device_id = ?')
    .get(device_id) as PlayerProfile | undefined;
}

export function upsertScore(
  db: Database.Database,
  device_id: string,
  game: string,
  mode: string,
  value: number
): { accepted: boolean; personal_best: number } {
  const config = BOARD_CONFIG[`${game}:${mode}`];
  const existing = db
    .prepare('SELECT value FROM scores WHERE device_id = ? AND game = ? AND mode = ?')
    .get(device_id, game, mode) as { value: number } | undefined;

  if (existing) {
    const isBetter = config.sort === 'asc' ? value < existing.value : value > existing.value;
    if (isBetter) {
      db.prepare(
        "UPDATE scores SET value = ?, submitted_at = datetime('now') WHERE device_id = ? AND game = ? AND mode = ?"
      ).run(value, device_id, game, mode);
      return { accepted: true, personal_best: value };
    }
    return { accepted: false, personal_best: existing.value };
  }

  db.prepare(
    'INSERT INTO scores (device_id, game, mode, value) VALUES (?, ?, ?, ?)'
  ).run(device_id, game, mode, value);
  return { accepted: true, personal_best: value };
}

export function deletePlayerScores(
  db: Database.Database,
  device_id: string,
  deleteProfile: boolean = false
): void {
  db.prepare('DELETE FROM scores WHERE device_id = ?').run(device_id);
  if (deleteProfile) {
    db.prepare('DELETE FROM players WHERE device_id = ?').run(device_id);
  }
}

export function getLeaderboard(
  db: Database.Database,
  game: string,
  mode: string,
  device_id: string
): { top: ScoreEntry[]; player_rank: number | null; player_score: number | null } {
  const config = BOARD_CONFIG[`${game}:${mode}`];
  // config.sort is typed 'asc'|'desc'; map to SQL literals for use in the template string
  const sqlOrder: 'ASC' | 'DESC' = config.sort === 'asc' ? 'ASC' : 'DESC';

  const top = db.prepare(`
    SELECT s.device_id, p.display_name, s.value,
      DENSE_RANK() OVER (ORDER BY s.value ${sqlOrder}) AS rank
    FROM scores s
    JOIN players p ON s.device_id = p.device_id
    WHERE s.game = ? AND s.mode = ? AND p.visible = 1
    ORDER BY s.value ${sqlOrder}
    LIMIT 10
  `).all(game, mode) as ScoreEntry[];

  const playerRow = db.prepare(`
    WITH all_ranked AS (
      SELECT device_id, value,
        DENSE_RANK() OVER (ORDER BY value ${sqlOrder}) AS rank
      FROM scores
      WHERE game = ? AND mode = ?
    )
    SELECT rank, value FROM all_ranked WHERE device_id = ?
  `).get(game, mode, device_id) as { rank: number; value: number } | undefined;

  return {
    top,
    player_rank: playerRow?.rank ?? null,
    player_score: playerRow?.value ?? null,
  };
}
