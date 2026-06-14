extends Node

## Handles all file I/O for crash/error reports: writing, rotation, and retrieval.

const LOG_DIR := "user://crash_logs"
const MAX_LOG_FILES := 15

var _latest_report_path: String = ""
var _latest_report_text: String = ""


func _ready() -> void:
	_ensure_log_dir()
	trim_old_reports()


func write_report(report: Dictionary) -> String:
	_ensure_log_dir()
	var unix := int(Time.get_unix_time_from_system())
	var ticks := Time.get_ticks_usec()
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var file_name := "crash_%s_%d_%d.json" % [stamp, unix, ticks]
	var path := LOG_DIR.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(report, "\t"))
	_latest_report_path = path
	_latest_report_text = JSON.stringify(report, "\t")
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
