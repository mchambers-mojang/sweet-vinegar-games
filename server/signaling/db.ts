import Database from 'better-sqlite3';
import * as fs from 'fs';
import * as path from 'path';

export const DEFAULT_DB_PATH = '/home/data/vinegar.db';

export interface PlayerProfile {
  device_id: string;
  display_name: string;
  visible: number;
  created_at: string;
}

export function openDb(dbPath: string): Database.Database {
  const dir = path.dirname(dbPath);
  if (dbPath !== ':memory:' && !fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  const db = new Database(dbPath);
  db.pragma('journal_mode = WAL');

  db.exec(`
    CREATE TABLE IF NOT EXISTS players (
      device_id TEXT PRIMARY KEY,
      display_name TEXT NOT NULL,
      visible INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
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
