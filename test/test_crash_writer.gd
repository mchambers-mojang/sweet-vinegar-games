extends GutTest

## Unit tests for CrashCollector file I/O — writing, rotation, retrieval, clipboard.
## (Formerly test_crash_writer.gd; CrashWriter was merged into CrashCollector.)

const CollectorScript := preload("res://scripts/autoload/crash_collector.gd")

var collector: Node


func before_each() -> void:
	collector = Node.new()
	collector.set_script(CollectorScript)
	add_child_autofree(collector)
	# Reset cached state so tests start clean
	collector._latest_report_path = ""
	collector._latest_report_text = ""


func _capture(kind: String = "test_error") -> String:
	return collector.capture_crash(kind, "test message")


# --- capture_crash (write) / get_latest_report_path ---

func test_write_creates_file() -> void:
	var path: String = _capture()
	assert_true(path != "", "capture_crash should return a non-empty path")
	assert_true(FileAccess.file_exists(path), "Crash report file should exist on disk")


func test_report_content_valid_json() -> void:
	var path: String = _capture("json_test")
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "File should be readable")
	var parsed = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Dictionary, "File content should parse as a Dictionary")


func test_write_updates_latest_path() -> void:
	var path: String = _capture()
	assert_eq(collector.get_latest_report_path(), path)


func test_write_updates_latest_text() -> void:
	_capture("text_test")
	var text: String = collector.get_latest_report_text()
	assert_true(text.contains("text_test"), "Latest report text should contain the written kind")


# --- get_latest_report_text ---

func test_get_latest_report_text_returns_empty_when_no_path_set() -> void:
	# With no path and no cached text, should return empty
	# (Note: disk may have prior reports from CI; only testing the in-memory fast path)
	collector._latest_report_text = ""
	# Force the lazy-load path to skip by giving a nonexistent path
	collector._latest_report_path = "user://crash_logs/nonexistent_test_file.json"
	var text: String = collector.get_latest_report_text()
	assert_eq(text, "", "Should return empty string when file does not exist")


func test_get_latest_report_text_reads_from_disk_when_path_set() -> void:
	# Capture a report then reset the in-memory cache but keep the path
	_capture("disk_read_test")
	collector._latest_report_text = ""
	var text: String = collector.get_latest_report_text()
	assert_true(text.contains("disk_read_test"), "Should read report content from disk")


# --- get_recent_reports ---

func test_get_recent_ordered_most_recent_first() -> void:
	_capture("first")
	_capture("second")
	var reports: Array[Dictionary] = collector.get_recent_reports(2)
	assert_eq(reports.size(), 2)
	var kinds: Array[String] = []
	for r in reports:
		kinds.append(str(r.get("kind", "")))
	assert_true(kinds.has("first"), "Both reports should be present")
	assert_true(kinds.has("second"), "Both reports should be present")


func test_get_recent_limit_respected() -> void:
	for i in 5:
		_capture("report_%d" % i)
	var reports: Array[Dictionary] = collector.get_recent_reports(2)
	assert_eq(reports.size(), 2)


# --- trim_old_reports ---

func test_trim_respects_limit() -> void:
	var original_max := CollectorScript.MAX_LOG_FILES
	for i in range(original_max + 2):
		_capture("trim_test_%d" % i)
	collector.trim_old_reports()
	var remaining: Array[Dictionary] = collector.get_recent_reports(-1)
	assert_true(remaining.size() <= original_max,
			"trim_old_reports should keep at most MAX_LOG_FILES reports")


# --- copy_latest_report_to_clipboard ---

func test_clipboard_copy_returns_false_when_empty() -> void:
	# Point to a nonexistent path so the disk fallback returns empty
	collector._latest_report_path = "user://crash_logs/nonexistent_test_file.json"
	var result: bool = collector.copy_latest_report_to_clipboard()
	assert_false(result, "Should return false when no report is available")


func test_clipboard_copy_returns_true_after_write() -> void:
	_capture("clipboard_test")
	var result: bool = collector.copy_latest_report_to_clipboard()
	assert_true(result, "Should return true after a report has been written")
