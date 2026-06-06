extends Node

## Lightweight replay recorder for crash reproduction and deterministic input playback.

const REPLAYS_PATH := "user://replays.json"
const ACTIVE_REPLAY_PATH := "user://active_replay.json"
const FORMAT_VERSION := 1
const MAX_AUTO_REPLAYS := 20
const SECONDS_TO_MS := 1000.0
const MIN_PLAYBACK_SPEED := 0.25
const MAX_PLAYBACK_SPEED := 4.0

var _replays: Array[Dictionary] = []
var _active_replay: Dictionary = {}
var _id_rng := RandomNumberGenerator.new()
var _active_sequence: int = 0
var playback_speed: float = 1.0


func _ready() -> void:
	_id_rng.randomize()
	_load_replays()
	_load_active_replay()


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
	_save_active_replay()
	return str(_active_replay["id"])


func has_active_session() -> bool:
	return not _active_replay.is_empty()


func record_input(elapsed_time: float, event_type: String, payload: Dictionary) -> void:
	if _active_replay.is_empty():
		return
	var frames: Array[Dictionary] = _active_replay.get("frames", [])
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
	_save_active_replay()


func finish_session(outcome: String, final_score: int, duration: float, final_state: Dictionary = {}) -> void:
	if _active_replay.is_empty():
		return
	_active_replay["footer"] = {
		"final_score": final_score,
		"duration": duration,
		"outcome": outcome,
		"final_state": final_state,
	}
	_replays.append(_active_replay.duplicate(true))
	_enforce_rolling_buffer()
	_save_replays()
	_active_replay = {}
	_clear_active_replay_file()


func bookmark_latest_replay() -> bool:
	if _replays.is_empty():
		return false
	_replays[-1]["bookmarked"] = true
	_save_replays()
	return true


func get_recent_replays(limit: int = MAX_AUTO_REPLAYS) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := maxi(0, _replays.size() - limit)
	for i in range(start, _replays.size()):
		result.append(_replays[i])
	return result


func get_replay_by_id(replay_id: String) -> Dictionary:
	for replay in _replays:
		if str(replay.get("id", "")) == replay_id:
			return replay
	return {}


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
	if _replays.is_empty():
		return ""
	return export_replay_code(str(_replays[-1].get("id", "")))


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
	if not _replays.is_empty():
		payload["latest_completed_replay"] = _replays[-1]
	return payload


func _get_game_version() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if not version.is_empty():
		return version
	var features = ProjectSettings.get_setting("application/config/features", PackedStringArray())
	return ",".join(features)


func _enforce_rolling_buffer() -> void:
	var non_bookmarked_seen := 0
	for i in range(_replays.size() - 1, -1, -1):
		if _replays[i].get("bookmarked", false):
			continue
		non_bookmarked_seen += 1
		if non_bookmarked_seen > MAX_AUTO_REPLAYS:
			_replays.remove_at(i)


func _load_replays() -> void:
	_replays.clear()
	if not FileAccess.file_exists(REPLAYS_PATH):
		return
	var file := FileAccess.open(REPLAYS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		for replay in parsed:
			if replay is Dictionary:
				_replays.append(replay)


func _save_replays() -> void:
	var file := FileAccess.open(REPLAYS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_replays))


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
