extends Node

## Local-first analytics manager with bounded storage and pluggable sinks.

const SAVE_PATH := "user://analytics_events.json"
const MAX_EVENTS := 5000

var _events: Array[Dictionary] = []
var _session_id: String = ""
var _sinks: Array[Object] = []


func _ready() -> void:
	_load_events()
	_start_session()


func register_sink(sink: Object) -> void:
	if sink == null:
		return
	if not sink.has_method("push_event"):
		return
	if _sinks.has(sink):
		return
	_sinks.append(sink)


func unregister_sink(sink: Object) -> void:
	_sinks.erase(sink)


func log_event(event_name: String, properties: Dictionary = {}) -> void:
	if event_name.is_empty():
		return
	var event: Dictionary = {
		"name": event_name,
		"timestamp": Time.get_unix_time_from_system(),
		"session_id": _session_id,
		"properties": properties.duplicate(true),
	}
	_append_local_event(event)
	for sink in _sinks:
		sink.call("push_event", event)


func track_achievement_unlocked(achievement_id: String, properties: Dictionary = {}) -> void:
	var payload := properties.duplicate(true)
	payload["achievement_id"] = achievement_id
	log_event("achievement_unlocked", payload)


func query_events(event_name: String = "", since_timestamp: float = 0.0, limit: int = 1000) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var unlimited := limit <= 0
	for i in range(_events.size() - 1, -1, -1):
		var event := _events[i]
		if not event_name.is_empty() and str(event.get("name", "")) != event_name:
			continue
		if since_timestamp > 0.0 and float(event.get("timestamp", 0.0)) < since_timestamp:
			continue
		result.append(event)
		if not unlimited and result.size() >= limit:
			break
	result.reverse()
	return result


func get_event_counts() -> Dictionary:
	var counts := {}
	for event in _events:
		var name := str(event.get("name", ""))
		counts[name] = int(counts.get(name, 0)) + 1
	return counts


func _start_session() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_session_id = "%d-%d" % [int(Time.get_unix_time_from_system()), rng.randi()]
	log_event("session", {
		"platform": OS.get_name(),
		"app_name": str(ProjectSettings.get_setting("application/config/name", "")),
	})


func _append_local_event(event: Dictionary) -> void:
	_events.append(event)
	var overflow := _events.size() - MAX_EVENTS
	if overflow > 0:
		_events = _events.slice(overflow, _events.size())
	_save_events()


func _save_events() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"events": _events}))


func _load_events() -> void:
	_events.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	if text.is_empty():
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var loaded_events = parsed.get("events", [])
	if typeof(loaded_events) != TYPE_ARRAY:
		return
	for entry in loaded_events:
		if typeof(entry) == TYPE_DICTIONARY:
			_events.append(entry)
