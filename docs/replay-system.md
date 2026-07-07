# Replay system (input recording)

This implementation provides deterministic input capture, crash reproduction, and visual playback using a two-module architecture with a `GameReplayAdapter` seam.

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

## Architecture

### ReplayRecorder (session lifecycle)

`scripts/replays/replay_recorder.gd` is an autoload that owns the in-memory recording lifecycle. It exposes:

- `start_session(game_mode, seed, initial_state, settings_snapshot)` → `String` — begin a recording session, returns replay_id
- `has_active_session()` → `bool` — whether a session is in progress
- `record_input(elapsed_time, event_type, payload)` — append a frame
- `finish_session(outcome, final_score, duration, final_state)` → `Dictionary` — finalize and return the completed replay; caller must persist it via `ReplayStorage.save_replay()`
- `flush_active_replay()` — immediately flush the in-progress snapshot to disk
- `get_crash_recovery_payload()` — crash reporter hook; returns the active in-progress replay

The active (in-progress) replay is snapshotted to `user://active_replay.json` for crash recovery.

### ReplayStorage (file I/O)

`scripts/replays/replay_storage.gd` is an autoload that handles all persistence. It exposes:

- `save_replay(replay)` → `String` — persist a completed replay dict; returns replay_id
- `delete_replay(replay_id)` — remove from index and disk
- `bookmark_replay(replay_id)` / `bookmark_latest_replay()` — mark a replay as permanently retained
- `get_recent_replays(limit)` — metadata list for the replays screen
- `get_replay_by_id(replay_id)` — full replay with frames
- `export_replay_code(replay_id)` / `import_replay_code(code)` — compact base64 payloads
- `set_pending_playback(replay)` / `get_pending_playback()` — pass a replay between screens

### ReplayManager (facade)

`scripts/autoload/replay_manager.gd` is a thin facade that delegates to `ReplayRecorder` and `ReplayStorage`. It exists for backward compatibility. New callers should use the specific module directly.

### ReplayPlayer (playback engine)

`scripts/replays/replay_player.gd` is a generic playback engine attached to `scenes/replay_viewer.tscn`. It:

- Reads the pending replay from `ReplayStorage`
- Selects a `GameReplayAdapter` based on `game_mode`
- Drives play/pause, speed cycling (1×/2×/4×), and board reset via the adapter
- All games use the single `replay_viewer.tscn` scene

### GameReplayAdapter (seam)

`scripts/replays/game_replay_adapter.gd` is a `RefCounted` base class. Each game provides one concrete adapter:

| Game       | Adapter file                             |
|------------|------------------------------------------|
| Blockudoku | `blockudoku_replay_adapter.gd`           |
| Shikaku    | `shikaku_replay_adapter.gd`              |
| Sudoku     | `sudoku_replay_adapter.gd`               |

The adapter interface:

```gdscript
# Create and return the board Control. Called once before playback.
func setup_playback(initial_state: Dictionary) -> Control

# Apply one frame to the board.
func apply_frame(frame: Dictionary, visual: Control, suppress_effects: bool = false) -> void

# Reset the board to initial_state (enables backward scrubbing / replay-from-start).
func reset_to_state(initial_state: Dictionary, visual: Control) -> void

# Which event types are visually meaningful? Empty = include all.
func get_visual_event_types() -> Array[String]
```

## Storage and retention

- Replays are written to `user://replays/<id>.json`
- Index is stored at `user://replays_index.json`
- Active (in-progress) replay is snapshotted to `user://active_replay.json`
  - supports crash-time recovery payloads
- Auto-retention keeps a rolling buffer of 20 non-bookmarked replays
- Bookmarked replays are retained permanently and excluded from rolling eviction

## Game-mode support

### Blockudoku

- Seeded RNG for piece dealing (deterministic sequence)
- Records: piece selection, placement with grid coordinates, rejected placements
- Visual event type: `piece_placed`

### Sudoku

- Seeded puzzle generation
- Records: cell selections, number inputs, hints, erase, color actions
- Visual event types: `number_input` (non-notes), `hint_pressed`

### Shikaku

- Seeded puzzle generation
- Records: rectangle placements and removals
- Visual event types: `rectangle_placed`, `rectangle_removed`

## Carom status

Carom-specific replay hooks are not added because no Carom gameplay scripts are present yet.
To add Carom replay support, implement a `CaromReplayAdapter extends GameReplayAdapter` and register it in `ReplayPlayer._create_adapter()`.
