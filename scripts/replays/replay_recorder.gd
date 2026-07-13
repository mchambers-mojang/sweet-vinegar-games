extends Node

## In-memory session recorder — owns the start/record_input/finish lifecycle.
## Produces a complete replay Dictionary when finish_session() is called.
## No persistent file I/O for completed replays — that is handled by ReplayStorage.
## The active (in-progress) replay is snapshotted to disk for crash recovery.

const ACTIVE_REPLAY_PATH := "user://active_replay.json"
const SAVE_INTERVAL := 2.0
const SECONDS_TO_MS := 1000.0

var active_replay_path: String = ACTIVE_REPLAY_PATH
var _active_replay: Dictionary = {}
var _id_rng := RandomNumberGenerator.new()
var _active_sequence: int = 0
var _save_timer: float = 0.0
var _dirty: bool = false


func _ready() -> void:
	_id_rng.randomize()
	_load_active_replay()
	CrashCollector.register_replay_hook(get_crash_recovery_payload)
	GameEvents.move_made.connect(_on_game_events_move_made)


func _process(delta: float) -> void:
	if not _dirty:
		return
	_save_timer += delta
	if _save_timer >= SAVE_INTERVAL:
		_save_timer = 0.0
		_dirty = false
		_save_active_replay()


func start_session(game_mode: String, seed: int, initial_state: Dictionary, settings_snapshot: Dictionary = {}) -> String:
	_active_replay = {
		"id": "%d_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), _id_rng.randi()],
		"header": {
			"game_mode": game_mode,
			"version": _get_game_version(),
			"seed": seed,
			"settings_snapshot": settings_snapshot,
			"timestamp": Time.get_unix_time_from_system(),
			"initial_state": initial_state,
		},
		"frames": [],
		"footer": {},
	}
	_active_sequence = 0
	_save_timer = 0.0
	_dirty = false
	_save_active_replay()
	return str(_active_replay.get("id", ""))


func has_active_session() -> bool:
	return not _active_replay.is_empty()


func flush_active_replay() -> void:
	if not _active_replay.is_empty():
		_dirty = false
		_save_active_replay()


func record_input(elapsed_time: float, event_type: String, payload: Dictionary) -> void:
	if _active_replay.is_empty():
		return
	var frames: Array = _active_replay.get("frames", [])
	frames.append({
		"tick": roundi(maxf(0.0, elapsed_time) * SECONDS_TO_MS),
		"seq": _active_sequence,
		"input_event": {
			"type": event_type,
			"payload": payload,
		},
	})
	_active_sequence += 1
	_active_replay["frames"] = frames
	_dirty = true


## Finalizes the active session and returns the completed replay Dictionary.
## The caller is responsible for persisting it via ReplayStorage.save_replay().
## Returns an empty Dictionary if there is no active session.
func finish_session(outcome: String, final_score: int, duration: float, final_state: Dictionary = {}) -> Dictionary:
	if _active_replay.is_empty():
		return {}
	_active_replay["footer"] = {
		"final_score": final_score,
		"duration": duration,
		"outcome": outcome,
		"final_state": final_state,
	}
	var completed: Dictionary = _active_replay.duplicate(true)
	_active_replay = {}
	_active_sequence = 0
	_dirty = false
	_clear_active_replay_file()
	return completed


func get_crash_recovery_payload() -> Dictionary:
	return {
		"active_replay": _active_replay,
	}


# --- Private helpers ---

func _save_active_replay() -> void:
	if _active_replay.is_empty():
		_clear_active_replay_file()
		return
	var file := FileAccess.open(active_replay_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_active_replay))


func _load_active_replay() -> void:
	_active_replay = {}
	if not FileAccess.file_exists(active_replay_path):
		return
	var file := FileAccess.open(active_replay_path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_active_replay = parsed


func _clear_active_replay_file() -> void:
	if FileAccess.file_exists(active_replay_path):
		DirAccess.remove_absolute(active_replay_path)


func _get_game_version() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if not version.is_empty():
		return version
	var features = ProjectSettings.get_setting("application/config/features", PackedStringArray())
	return ",".join(features)


# --- GameEvents subscriptions ---

func _on_game_events_move_made(_game_id: String, move_data: Dictionary) -> void:
	if _active_replay.is_empty():
		return
	var elapsed: float = move_data.get("elapsed_time", 0.0)
	var event_type: String = move_data.get("event_type", "move")
	var payload: Dictionary = move_data.duplicate()
	payload.erase("elapsed_time")
	payload.erase("event_type")
	record_input(elapsed, event_type, payload)
