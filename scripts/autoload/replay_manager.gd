extends Node

## Lightweight replay recorder with lazy-loaded replay files.
## Only metadata (header+footer) is kept in memory; frames load on demand.

const REPLAYS_DIR := "user://replays/"
const REPLAYS_INDEX_PATH := "user://replays_index.json"
const ACTIVE_REPLAY_PATH := "user://active_replay.json"
const LEGACY_REPLAYS_PATH := "user://replays.json"
const FORMAT_VERSION := 1
const MAX_AUTO_REPLAYS := 20
const SECONDS_TO_MS := 1000.0
const MIN_PLAYBACK_SPEED := 0.25
const MAX_PLAYBACK_SPEED := 4.0

# Only metadata (header + footer + id + bookmarked) — no frames in memory
var _replay_index: Array[Dictionary] = []
var _active_replay: Dictionary = {}
var _id_rng := RandomNumberGenerator.new()
var _active_sequence: int = 0
var _save_timer: float = 0.0
var _dirty: bool = false
var playback_speed: float = 1.0
var _pending_playback: Dictionary = {}

const SAVE_INTERVAL := 2.0


func set_pending_playback(replay: Dictionary) -> void:
	_pending_playback = replay


func get_pending_playback() -> Dictionary:
	var replay := _pending_playback
	_pending_playback = {}
	return replay


func _ready() -> void:
	_id_rng.randomize()
	_ensure_replays_dir()
	_migrate_legacy_replays()
	_load_index()
	_load_active_replay()


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


func finish_session(outcome: String, final_score: int, duration: float, final_state: Dictionary = {}) -> void:
	if _active_replay.is_empty():
		return
	_active_replay["footer"] = {
		"final_score": final_score,
		"duration": duration,
		"outcome": outcome,
		"final_state": final_state,
	}
	var replay_id := str(_active_replay.get("id", ""))
	_save_replay_file(replay_id, _active_replay)
	var meta := _extract_metadata(_active_replay)
	_replay_index.append(meta)
	_enforce_rolling_buffer()
	_save_index()
	_active_replay = {}
	_dirty = false
	_clear_active_replay_file()


func bookmark_latest_replay() -> bool:
	if _replay_index.is_empty():
		return false
	_replay_index[-1]["bookmarked"] = true
	_save_index()
	return true


func delete_replay(replay_id: String) -> bool:
	for i in range(_replay_index.size() - 1, -1, -1):
		if str(_replay_index[i].get("id", "")) == replay_id:
			_replay_index.remove_at(i)
			_delete_replay_file(replay_id)
			_save_index()
			return true
	return false


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
	return Marshalls.utf8_to_base64(JSON.stringify(blob))


func export_latest_replay_code() -> String:
	if _replay_index.is_empty():
		return ""
	return export_replay_code(str(_replay_index[-1].get("id", "")))


func import_replay_code(code: String) -> Dictionary:
	if code.is_empty():
		return {}
	var decoded := Marshalls.base64_to_utf8(code)
	if decoded.is_empty():
		return {}
	var parsed = JSON.parse_string(decoded)
	if not (parsed is Dictionary):
		return {}
	var blob: Dictionary = parsed
	return blob.get("replay", {})


func simulate_replay(replay: Dictionary, apply_event: Callable) -> bool:
	if replay.is_empty():
		return false
	var frames: Array = replay.get("frames", [])
	frames.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_tick := int(a.get("tick", 0))
		var b_tick := int(b.get("tick", 0))
		if a_tick == b_tick:
			return int(a.get("seq", 0)) < int(b.get("seq", 0))
		return a_tick < b_tick
	)
	for frame in frames:
		apply_event.call(frame)
	return true


func set_playback_speed(multiplier: float) -> float:
	playback_speed = clampf(multiplier, MIN_PLAYBACK_SPEED, MAX_PLAYBACK_SPEED)
	return playback_speed


func scrub_frames_to_tick(replay: Dictionary, tick_ms: int) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for frame in replay.get("frames", []):
		if int(frame.get("tick", 0)) <= tick_ms:
			frames.append(frame)
	return frames


func get_crash_recovery_payload() -> Dictionary:
	var payload := {
		"active_replay": _active_replay,
		"latest_completed_replay": {},
	}
	if not _replay_index.is_empty():
		var latest_id := str(_replay_index[-1].get("id", ""))
		payload["latest_completed_replay"] = _load_replay_file(latest_id)
	return payload


# --- Private helpers ---

func _extract_metadata(replay: Dictionary) -> Dictionary:
	var header: Dictionary = replay.get("header", {})
	var footer: Dictionary = replay.get("footer", {})
	return {
		"id": replay.get("id", ""),
		"bookmarked": replay.get("bookmarked", false),
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
		push_error("ReplayManager: Failed to save replay file: %s (error: %d)" % [path, FileAccess.get_open_error()])


func _load_replay_file(replay_id: String) -> Dictionary:
	var path := _replay_file_path(replay_id)
	if not FileAccess.file_exists(path):
		push_warning("ReplayManager: Replay file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ReplayManager: Failed to open replay file: %s (error: %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("ReplayManager: Failed to parse replay JSON: %s (length: %d)" % [path, text.length()])
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


func _save_active_replay() -> void:
	if _active_replay.is_empty():
		_clear_active_replay_file()
		return
	var file := FileAccess.open(ACTIVE_REPLAY_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_active_replay))


func _clear_active_replay_file() -> void:
	if FileAccess.file_exists(ACTIVE_REPLAY_PATH):
		DirAccess.remove_absolute(ACTIVE_REPLAY_PATH)


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


func _get_game_version() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if not version.is_empty():
		return version
	var features = ProjectSettings.get_setting("application/config/features", PackedStringArray())
	return ",".join(features)
