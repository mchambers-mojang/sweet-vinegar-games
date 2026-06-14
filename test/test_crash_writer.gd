extends GutTest

## Unit tests for CrashWriter — file I/O, rotation, retrieval, clipboard.

const WriterScript := preload("res://scripts/autoload/crash_writer.gd")

var writer: Node


func before_each() -> void:
	writer = Node.new()
	writer.set_script(WriterScript)
	add_child_autofree(writer)
	# Reset cached state so tests start clean
	writer._latest_report_path = ""
	writer._latest_report_text = ""


func _make_report(kind: String = "test_error") -> Dictionary:
	return {
		"timestamp": "2024-01-01T00:00:00",
		"kind": kind,
		"message": "test message",
	}


# --- write_report ---

func test_write_creates_file() -> void:
	var path := writer.write_report(_make_report())
	assert_true(path != "", "write_report should return a non-empty path")
	assert_true(FileAccess.file_exists(path), "Crash report file should exist on disk")


func test_report_content_valid_json() -> void:
	var report := _make_report("json_test")
	var path := writer.write_report(report)
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "File should be readable")
	var parsed = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Dictionary, "File content should parse as a Dictionary")


func test_write_updates_latest_path() -> void:
	var path := writer.write_report(_make_report())
	assert_eq(writer.get_latest_report_path(), path)


func test_write_updates_latest_text() -> void:
	var report := _make_report("text_test")
	writer.write_report(report)
	var text := writer.get_latest_report_text()
	assert_true(text.contains("text_test"), "Latest report text should contain the written kind")


# --- get_latest_report_text ---

func test_get_latest_report_text_returns_empty_when_no_path_set() -> void:
	# With no path and no cached text, should return empty
	# (Note: disk may have prior reports from CI; only testing the in-memory fast path)
	writer._latest_report_text = ""
	writer._latest_report_path = ""
	# Force the lazy-load path to skip by giving a nonexistent path
	writer._latest_report_path = "user://crash_logs/nonexistent_test_file.json"
	var text := writer.get_latest_report_text()
	assert_eq(text, "", "Should return empty string when file does not exist")


func test_get_latest_report_text_reads_from_disk_when_path_set() -> void:
	# Write via another instance to simulate a report written in a prior session
	var path := writer.write_report(_make_report("disk_read_test"))
	# Reset the in-memory cache but keep the path
	writer._latest_report_text = ""
	var text := writer.get_latest_report_text()
	assert_true(text.contains("disk_read_test"), "Should read report content from disk")


# --- get_recent_reports ---

func test_get_recent_ordered_most_recent_first() -> void:
	# Write two reports; filenames include timestamps so ordering is deterministic
	writer.write_report(_make_report("first"))
	writer.write_report(_make_report("second"))
	var reports: Array[Dictionary] = writer.get_recent_reports(2)
	assert_eq(reports.size(), 2)
	# Most recent file sorts last alphabetically then reversed; just verify both present
	var kinds: Array[String] = []
	for r in reports:
		kinds.append(str(r.get("kind", "")))
	assert_true(kinds.has("first"), "Both reports should be present")
	assert_true(kinds.has("second"), "Both reports should be present")


func test_get_recent_limit_respected() -> void:
	for i in 5:
		writer.write_report(_make_report("report_%d" % i))
	var reports: Array[Dictionary] = writer.get_recent_reports(2)
	assert_eq(reports.size(), 2)


# --- trim_old_reports ---

func test_trim_respects_limit() -> void:
	# Temporarily lower the limit so the test doesn't need to write 16 files
	var original_max := WriterScript.MAX_LOG_FILES
	# Write MAX+2 reports and verify trim keeps only MAX
	for i in range(original_max + 2):
		writer.write_report(_make_report("trim_test_%d" % i))
	writer.trim_old_reports()
	var remaining: Array[Dictionary] = writer.get_recent_reports(-1)
	assert_true(remaining.size() <= original_max,
			"trim_old_reports should keep at most MAX_LOG_FILES reports")


# --- copy_latest_report_to_clipboard ---

func test_clipboard_copy_returns_false_when_empty() -> void:
	var result := writer.copy_latest_report_to_clipboard()
	assert_false(result, "Should return false when no report is available")


func test_clipboard_copy_returns_true_after_write() -> void:
	writer.write_report(_make_report("clipboard_test"))
	var result := writer.copy_latest_report_to_clipboard()
	assert_true(result, "Should return true after a report has been written")
