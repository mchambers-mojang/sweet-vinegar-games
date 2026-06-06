# Replay system (input recording)

This draft implementation adds a shared replay foundation focused on deterministic input capture and crash reproduction.

## What is recorded

Each replay is stored as:

- **Header**
  - `game_mode`
  - `version`
  - `seed`
  - `settings_snapshot`
  - `timestamp`
  - `initial_state`
- **Frames**
  - array of `{ tick, input_event }` where `tick` is milliseconds since game start
- **Footer**
  - `final_score`
  - `duration`
  - `outcome`
  - `final_state`

## Storage and retention

- Replays are written to `user://replays.json`
- Active (in-progress) replay is snapshotted to `user://active_replay.json` on each input frame
  - this supports crash-time recovery payloads
- Auto-retention keeps a rolling buffer of recent non-bookmarked replays (20 max)
- Bookmarked replays are retained permanently and excluded from rolling eviction

## Replay manager API

`scripts/autoload/replay_manager.gd` exposes:

- `start_session(...)`
- `record_input(...)`
- `finish_session(...)`
- `bookmark_latest_replay()`
- `export_replay_code(...)` / `import_replay_code(...)` (compact base64 payload)
- `simulate_replay(...)` (deterministic frame feed via callback)
- playback helpers:
  - `set_playback_speed(...)` (0.25x–4x)
  - `scrub_frames_to_tick(...)`
- crash helper:
  - `get_crash_recovery_payload()`

## Game-mode support in this repo

### Blockudoku

- Seeded RNG for piece dealing (deterministic sequence)
- Records:
  - piece selection
  - placement with grid coordinates
  - rejected placement attempts
- Stores and resumes RNG seed/state in save data
- Finalizes replay on game over or back-to-menu abandon
- Supports manual bookmark from game-over dialog

### Sudoku

- Seeded puzzle generation
- Records:
  - cell selections
  - number button presses
  - number input events (cell + value, notes mode metadata)
  - erase, hint, and color actions
- Stores seed + replay id in save data
- Finalizes replay on win, fail, or abandon
- Supports manual bookmark from win/fail dialogs

### Shikaku

- Seeded puzzle generation
- Records:
  - rectangle placements
  - rectangle removals
- Stores seed + replay id in save data
- Finalizes replay on win or abandon
- Supports manual bookmark from win dialog

## Carom status

Carom-specific replay hooks are not added in this repository because no Carom gameplay scripts are present yet.
The shared replay manager is implemented to support adding Carom deterministic input recording once that mode exists.
