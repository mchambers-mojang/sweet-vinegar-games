extends Node

## File I/O layer for replays — persistence, indexing, import/export, pending playback,
## and legacy migration. Registers its own crash hook to supply latest_completed_replay
## and replay_code to CrashReporter; ReplayRecorder supplies active_replay separately.

const REPLAYS_DIR := "user://replays/"
const REPLAYS_INDEX_PATH := "user://replays_index.json"
const LEGACY_REPLAYS_PATH := "user://replays.json"
const FORMAT_VERSION := 1
const MAX_AUTO_REPLAYS := 20

# Only metadata (header + footer + id + bookmarked) — no frames in memory
var _replay_index: Array[Dictionary] = []
var _pending_playback: Dictionary = {}


func _ready() -> void:
	_ensure_replays_dir()
	_migrate_legacy_replays()
	_load_index()
	CrashReporter.register_replay_hook(get_crash_recovery_payload)


func get_crash_recovery_payload() -> Dictionary:
	var latest: Dictionary = {}
	if not _replay_index.is_empty():
		latest = _replay_index[-1].duplicate(true)
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
		push_error("ReplayStorage: Failed to save replay file: %s (error: %d)" % [path, FileAccess.get_open_error()])


func _load_replay_file(replay_id: String) -> Dictionary:
	var path := _replay_file_path(replay_id)
	if not FileAccess.file_exists(path):
		push_warning("ReplayStorage: Replay file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ReplayStorage: Failed to open replay file: %s (error: %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("ReplayStorage: Failed to parse replay JSON: %s (length: %d)" % [path, text.length()])
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
