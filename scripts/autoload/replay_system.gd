extends Node

## Unified replay autoload — merges ReplayRecorder (session lifecycle) and
## ReplayStorage (file I/O) into a single module.
## Internal seams are preserved: recorder logic is in the Recorder section,
## storage logic is in the Storage section, for independent unit testing.


# ============================================================
# Recorder (previously ReplayRecorder)
# ============================================================

const ACTIVE_REPLAY_PATH := "user://active_replay.json"
const SAVE_INTERVAL := 2.0
const SECONDS_TO_MS := 1000.0

var _active_replay: Dictionary = {}
var _id_rng := RandomNumberGenerator.new()
var _active_sequence: int = 0
var _save_timer: float = 0.0
var _dirty: bool = false


func _ready() -> void:
	_id_rng.randomize()
	_load_active_replay()
	_ensure_replays_dir()
	_migrate_legacy_replays()
	_load_index()
	CrashCollector.register_replay_hook(_recorder_crash_payload)
	CrashCollector.register_replay_hook(_storage_crash_payload)
	GameEvents.move_made.connect(_on_game_events_move_made)


func _process(delta: float) -> void:
	if not _dirty:
		return
	_save_timer += delta
	if _save_timer >= SAVE_INTERVAL:
		_save_timer = 0.0
		_dirty = false
		_save_active_replay()


func start_session(game_mode: String, session_seed: int, initial_state: Dictionary, settings_snapshot: Dictionary = {}) -> String:
	_active_replay = {
		"id": "%d_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), _id_rng.randi()],
		"header": {
			"game_mode": game_mode,
			"version": _get_game_version(),
			"seed": session_seed,
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
## The caller is responsible for persisting it via save_replay().
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


# --- Recorder private helpers ---

func _recorder_crash_payload() -> Dictionary:
	return {
		"active_replay": _active_replay,
	}


func _save_active_replay() -> void:
	if _active_replay.is_empty():
		_clear_active_replay_file()
		return
	var file := FileAccess.open(ACTIVE_REPLAY_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_active_replay))


func _load_active_replay() -> void:
	_active_replay = {}
	if not FileAccess.file_exists(ACTIVE_REPLAY_PATH):
		return
	var file := FileAccess.open(ACTIVE_REPLAY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_active_replay = parsed


func _clear_active_replay_file() -> void:
	if FileAccess.file_exists(ACTIVE_REPLAY_PATH):
		DirAccess.remove_absolute(ACTIVE_REPLAY_PATH)


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


# ============================================================
# Storage (previously ReplayStorage)
# ============================================================

const REPLAYS_DIR := "user://replays/"
const REPLAYS_INDEX_PATH := "user://replays_index.json"
const LEGACY_REPLAYS_PATH := "user://replays.json"
const FORMAT_VERSION := 1
const MAX_AUTO_REPLAYS := 20

# Only metadata (header + footer + id + bookmarked) — no frames in memory
var _replay_index: Array[Dictionary] = []
var _pending_playback: Dictionary = {}


func _storage_crash_payload() -> Dictionary:
	var latest: Dictionary = {}
	if not _replay_index.is_empty():
		latest = _load_replay_file(str(_replay_index[-1].get("id", "")))
	return {
		"latest_completed_replay": latest,
		"replay_code": export_latest_replay_code(),
	}


func set_pending_playback(replay: Dictionary) -> void:
	_pending_playback = replay


func get_pending_playback() -> Dictionary:
	var replay := _pending_playback
	_pending_playback = {}
	return replay


## Persists a completed replay dict and returns the replay_id.
## Also updates the index and enforces the rolling buffer limit.
func save_replay(replay: Dictionary) -> String:
	if replay.is_empty():
		return ""
	var replay_id := str(replay.get("id", ""))
	if replay_id.is_empty():
		return ""
	_save_replay_file(replay_id, replay)
	var meta := _extract_metadata(replay)
	_replay_index.append(meta)
	_enforce_rolling_buffer()
	_save_index()
	return replay_id


func delete_replay(replay_id: String) -> bool:
	for i in range(_replay_index.size() - 1, -1, -1):
		if str(_replay_index[i].get("id", "")) == replay_id:
			_replay_index.remove_at(i)
			_delete_replay_file(replay_id)
			_save_index()
			return true
	return false


func bookmark_replay(replay_id: String) -> bool:
	for entry in _replay_index:
		if str(entry.get("id", "")) == replay_id:
			entry["bookmarked"] = true
			_save_index()
			return true
	return false


func bookmark_latest_replay() -> bool:
	if _replay_index.is_empty():
		return false
	_replay_index[-1]["bookmarked"] = true
	_save_index()
	return true


func get_recent_replays(limit: int = MAX_AUTO_REPLAYS) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := maxi(0, _replay_index.size() - limit)
	for i in range(start, _replay_index.size()):
		result.append(_replay_index[i])
	return result


func get_replay_by_id(replay_id: String) -> Dictionary:
	return _load_replay_file(replay_id)


func export_replay_code(replay_id: String) -> String:
	var replay := get_replay_by_id(replay_id)
	if replay.is_empty():
		return ""
	var blob := {
		"format_version": FORMAT_VERSION,
		"replay": replay,
	}
	var json_str := JSON.stringify(blob)
	var compressed := json_str.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	return "SVG1_" + Marshalls.raw_to_base64(compressed)


func export_latest_replay_code() -> String:
	if _replay_index.is_empty():
		return ""
	return export_replay_code(str(_replay_index[-1].get("id", "")))


func import_replay_code(code: String) -> Dictionary:
	if code.is_empty():
		return {}
	var decoded: String = ""
	if code.begins_with("SVG1_"):
		# Compressed format (v1)
		var raw := Marshalls.base64_to_raw(code.substr(5))
		if raw.is_empty():
			return {}
		var decompressed := raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
		if decompressed.is_empty():
			return {}
		decoded = decompressed.get_string_from_utf8()
	else:
		# Legacy uncompressed base64
		decoded = Marshalls.base64_to_utf8(code)
	if decoded.is_empty():
		return {}
	var parsed = JSON.parse_string(decoded)
	if not (parsed is Dictionary):
		return {}
	var blob: Dictionary = parsed
	return blob.get("replay", {})


# --- Storage private helpers ---

func _extract_metadata(replay: Dictionary) -> Dictionary:
	var header: Dictionary = replay.get("header", {})
	var footer: Dictionary = replay.get("footer", {})
	return {
		"id": replay.get("id", ""),
		"bookmarked": replay.get("bookmarked", false),
		"frame_count": replay.get("frames", []).size(),
		"header": header,
		"footer": footer,
	}


func _replay_file_path(replay_id: String) -> String:
	return REPLAYS_DIR + replay_id + ".json"


func _save_replay_file(replay_id: String, replay: Dictionary) -> void:
	_ensure_replays_dir()
	var path := _replay_file_path(replay_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(replay))
	else:
		push_error("ReplaySystem: Failed to save replay file: %s (error: %d)" % [path, FileAccess.get_open_error()])


func _load_replay_file(replay_id: String) -> Dictionary:
	var path := _replay_file_path(replay_id)
	if not FileAccess.file_exists(path):
		push_warning("ReplaySystem: Replay file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ReplaySystem: Failed to open replay file: %s (error: %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("ReplaySystem: Failed to parse replay JSON: %s (length: %d)" % [path, text.length()])
	return {}


func _delete_replay_file(replay_id: String) -> void:
	var path := _replay_file_path(replay_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _save_index() -> void:
	var file := FileAccess.open(REPLAYS_INDEX_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_replay_index))


func _load_index() -> void:
	_replay_index.clear()
	if not FileAccess.file_exists(REPLAYS_INDEX_PATH):
		return
	var file := FileAccess.open(REPLAYS_INDEX_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		for entry in parsed:
			if entry is Dictionary:
				_replay_index.append(entry)


func _enforce_rolling_buffer() -> void:
	var non_bookmarked_seen := 0
	for i in range(_replay_index.size() - 1, -1, -1):
		if _replay_index[i].get("bookmarked", false):
			continue
		non_bookmarked_seen += 1
		if non_bookmarked_seen > MAX_AUTO_REPLAYS:
			var old_id := str(_replay_index[i].get("id", ""))
			_delete_replay_file(old_id)
			_replay_index.remove_at(i)


func _ensure_replays_dir() -> void:
	if not DirAccess.dir_exists_absolute(REPLAYS_DIR):
		DirAccess.make_dir_recursive_absolute(REPLAYS_DIR)


func _migrate_legacy_replays() -> void:
	if not FileAccess.file_exists(LEGACY_REPLAYS_PATH):
		return
	if FileAccess.file_exists(REPLAYS_INDEX_PATH):
		DirAccess.remove_absolute(LEGACY_REPLAYS_PATH)
		return
	var file := FileAccess.open(LEGACY_REPLAYS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Array):
		DirAccess.remove_absolute(LEGACY_REPLAYS_PATH)
		return
	for replay in parsed:
		if not (replay is Dictionary):
			continue
		var replay_id := str(replay.get("id", ""))
		if replay_id.is_empty():
			continue
		_save_replay_file(replay_id, replay)
		_replay_index.append(_extract_metadata(replay))
	_save_index()
	DirAccess.remove_absolute(LEGACY_REPLAYS_PATH)
