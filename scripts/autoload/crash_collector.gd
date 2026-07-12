extends Node

## Collects crash/error state from providers and owns collection, assembly, and persistence.

const MAX_ACTIONS := 20
const ERROR_CHECK_INTERVAL := 1.0  # Check for new errors every second
const LOG_DIR := "user://crash_logs"
const MAX_LOG_FILES := 15

var _recent_actions: Array[Dictionary] = []
var _state_providers: Array[Callable] = []
var _replay_hooks: Array[Callable] = []
var _log_file_path: String = ""
var _last_log_size: int = 0
var _error_check_timer: float = 0.0
var _latest_report_path: String = ""
var _latest_report_text: String = ""


func _ready() -> void:
	_ensure_log_dir()
	trim_old_reports()
	_log_file_path = _find_godot_log_path()
	if _log_file_path != "":
		var file := FileAccess.open(_log_file_path, FileAccess.READ)
		if file:
			_last_log_size = file.get_length()
	GameEvents.game_started.connect(_on_game_events_game_started)
	GameEvents.game_ended.connect(_on_game_events_game_ended)


func _process(delta: float) -> void:
	_error_check_timer += delta
	if _error_check_timer < ERROR_CHECK_INTERVAL:
		return
	_error_check_timer = 0.0
	_check_log_for_errors()


func _check_log_for_errors() -> void:
	if _log_file_path == "":
		return
	var file := FileAccess.open(_log_file_path, FileAccess.READ)
	if file == null:
		return
	var current_size := file.get_length()
	if current_size <= _last_log_size:
		return
	# Read only the new portion
	file.seek(_last_log_size)
	var new_content := file.get_buffer(current_size - _last_log_size).get_string_from_utf8()
	_last_log_size = current_size

	# Parse for script errors
	var lines := new_content.split("\n")
	var error_lines: Array[String] = []
	for line in lines:
		if line.contains("SCRIPT ERROR:") or line.contains("ERROR:") or line.contains("Parse Error"):
			error_lines.append(line.strip_edges())

	if error_lines.size() > 0:
		var error_msg := "\n".join(error_lines)
		capture_error(error_msg, "", {"source": "log_monitor"})


func _find_godot_log_path() -> String:
	var log_dir := OS.get_user_data_dir().path_join("logs")
	var dir := DirAccess.open(log_dir)
	if dir == null:
		return ""
	# Find the current log (godot.log is the active one)
	var path := log_dir.path_join("godot.log")
	if FileAccess.file_exists(path):
		return path
	return ""


func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_CRASH:
		capture_crash("engine_crash", "MainLoop.NOTIFICATION_CRASH")


func register_user_action(action: String, metadata: Dictionary = {}) -> void:
	var entry := {
		"timestamp": Time.get_datetime_string_from_system(true, true),
		"action": action,
		"metadata": metadata,
	}
	_recent_actions.append(entry)
	while _recent_actions.size() > MAX_ACTIONS:
		_recent_actions.remove_at(0)


func register_state_provider(provider: Callable) -> void:
	if provider.is_null():
		return
	if not _state_providers.has(provider):
		_state_providers.append(provider)


func unregister_state_provider(provider: Callable) -> void:
	_state_providers.erase(provider)


func register_replay_hook(hook: Callable) -> void:
	if hook.is_null():
		return
	if not _replay_hooks.has(hook):
		_replay_hooks.append(hook)


func unregister_replay_hook(hook: Callable) -> void:
	_replay_hooks.erase(hook)


func capture_error(message: String, stack_trace: String = "", extra: Dictionary = {}) -> String:
	var payload := extra.duplicate()
	if stack_trace != "":
		payload["stack_trace"] = stack_trace
	return capture_crash("runtime_error", message, payload)


func capture_crash(kind: String, message: String, extra: Dictionary = {}) -> String:
	var report := _assemble_report({
		"kind": kind,
		"message": message,
		"extra": extra,
	})
	return _write_report(report)


func _assemble_report(error_info: Dictionary) -> Dictionary:
	var screen_size := DisplayServer.screen_get_size()
	var report := {
		"timestamp": Time.get_datetime_string_from_system(true, true),
		"kind": error_info.get("kind", ""),
		"message": error_info.get("message", ""),
		"godot_version": Engine.get_version_info(),
		"app_version": _get_app_version(),
		"device": {
			"model": OS.get_model_name(),
			"os_name": OS.get_name(),
			"os_version": OS.get_version(),
			"screen_size": {
				"width": screen_size.x,
				"height": screen_size.y,
			},
		},
		"scene": _get_current_scene_path(),
		"stack_trace": get_stack(),
		"memory": {
			"static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
			"static_peak_bytes": Performance.get_monitor(Performance.MEMORY_STATIC_MAX),
		},
		"user_actions": _recent_actions.duplicate(true),
		"game_state": _collect_state(),
		"extra": error_info.get("extra", {}),
	}

	var replay_payload := _collect_replay_payload()
	if not replay_payload.is_empty():
		report["replay"] = replay_payload

	return report


func _collect_state() -> Dictionary:
	var combined := {
		"scene": _get_current_scene_path(),
	}
	for provider in _state_providers:
		if provider.is_null():
			continue
		var value = provider.call()
		if value is Dictionary:
			combined.merge(value, true)
	return combined


func _collect_replay_payload() -> Dictionary:
	var replay := {}
	for hook in _replay_hooks:
		if hook.is_null():
			continue
		var value = hook.call()
		if value is Dictionary:
			replay.merge(value, true)
	return replay


func _get_current_scene_path() -> String:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return ""
	return tree.current_scene.scene_file_path


func _get_app_version() -> String:
	var project_version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if project_version != "":
		return project_version
	return str(ProjectSettings.get_setting("application/config/name", ""))


# --- GameEvents subscriptions ---

func _on_game_events_game_started(game_id: String, _difficulty: int, rules: Dictionary) -> void:
	register_user_action(game_id + "_game_started", rules)


func _on_game_events_game_ended(game_id: String, outcome: String, _duration: float) -> void:
	register_user_action(game_id + "_game_ended", {"outcome": outcome})


# --- File I/O ---

func _write_report(report: Dictionary) -> String:
	_ensure_log_dir()
	var unix := int(Time.get_unix_time_from_system())
	var ticks := Time.get_ticks_usec()
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var file_name := "crash_%s_%d_%d.json" % [stamp, unix, ticks]
	var path := LOG_DIR.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	var json := JSON.stringify(report, "\t")
	file.store_string(json)
	_latest_report_path = path
	_latest_report_text = json
	trim_old_reports()
	return path


func get_recent_reports(limit: int = 10) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for path in _get_recent_report_paths(limit):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			var report: Dictionary = parsed
			report["path"] = path
			reports.append(report)
	return reports


func get_latest_report_path() -> String:
	return _latest_report_path


func get_latest_report_text() -> String:
	if _latest_report_text != "":
		return _latest_report_text
	if _latest_report_path == "":
		var recent := _get_recent_report_paths(1)
		if recent.is_empty():
			return ""
		_latest_report_path = recent[0]
	var file := FileAccess.open(_latest_report_path, FileAccess.READ)
	if file == null:
		return ""
	_latest_report_text = file.get_as_text()
	return _latest_report_text


func copy_latest_report_to_clipboard() -> bool:
	var text := get_latest_report_text()
	if text == "":
		return false
	DisplayServer.clipboard_set(text)
	return true


func trim_old_reports() -> void:
	var paths := _get_recent_report_paths(-1)
	if paths.size() <= MAX_LOG_FILES:
		return
	for i in range(MAX_LOG_FILES, paths.size()):
		DirAccess.remove_absolute(paths[i])


func _ensure_log_dir() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)


func _get_recent_report_paths(limit: int = MAX_LOG_FILES) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			continue
		if name.ends_with(".json"):
			paths.append(LOG_DIR.path_join(name))
	dir.list_dir_end()
	paths.sort()
	paths.reverse()
	if limit >= 0 and paths.size() > limit:
		paths.resize(limit)
	return paths
