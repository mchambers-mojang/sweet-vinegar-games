extends GutTest

## Unit tests for CrashCollector — state providers, replay hooks, user actions, capture.

const CollectorScript := preload("res://scripts/autoload/crash_collector.gd")

var collector: Node


func before_each() -> void:
	collector = Node.new()
	collector.set_script(CollectorScript)
	add_child_autofree(collector)
	# Reset internal state after _ready
	collector._recent_actions = [] as Array[Dictionary]
	collector._state_providers = [] as Array[Callable]
	collector._replay_hooks = [] as Array[Callable]
	collector._log_file_path = ""
	collector._last_log_size = 0
	collector._error_check_timer = 0.0


# --- State providers ---

func test_register_state_provider_called_on_capture() -> void:
	var called := false
	var provider := func() -> Dictionary:
		called = true
		return {"test_key": "test_value"}
	collector.register_state_provider(provider)
	collector.capture_error("test error")
	assert_true(called, "State provider should be called during capture")


func test_state_provider_value_included_in_report() -> void:
	var provider := func() -> Dictionary:
		return {"custom_state": "hello"}
	collector.register_state_provider(provider)
	collector.capture_error("state test")
	var text := CrashWriter.get_latest_report_text()
	assert_true(text.contains("custom_state"), "custom_state key should appear in the report")


func test_unregister_removes_provider() -> void:
	var call_count := 0
	var provider := func() -> Dictionary:
		call_count += 1
		return {}
	collector.register_state_provider(provider)
	collector.unregister_state_provider(provider)
	collector.capture_error("after unregister")
	assert_eq(call_count, 0, "Unregistered provider should not be called")


func test_duplicate_provider_not_added() -> void:
	var provider := func() -> Dictionary:
		return {}
	collector.register_state_provider(provider)
	collector.register_state_provider(provider)
	assert_eq(collector._state_providers.size(), 1)


# --- User actions ---

func test_user_actions_included_in_report() -> void:
	collector.register_user_action("opened_menu", {"from": "home"})
	collector.register_user_action("started_game")
	collector.capture_error("action test")
	var text := CrashWriter.get_latest_report_text()
	assert_true(text.contains("opened_menu"), "User action should appear in report")
	assert_true(text.contains("started_game"), "User action should appear in report")


func test_user_actions_capped_at_max() -> void:
	for i in range(CollectorScript.MAX_ACTIONS + 5):
		collector.register_user_action("action_%d" % i)
	assert_eq(collector._recent_actions.size(), CollectorScript.MAX_ACTIONS)


# --- Replay hooks ---

func test_replay_hook_included() -> void:
	var hook := func() -> Dictionary:
		return {"frames": [{"seq": 0}]}
	collector.register_replay_hook(hook)
	collector.capture_error("replay test")
	var text := CrashWriter.get_latest_report_text()
	assert_true(text.contains("\"replay\""), "Replay payload should appear in report")


func test_unregister_replay_hook() -> void:
	var called := false
	var hook := func() -> Dictionary:
		called = true
		return {"data": "x"}
	collector.register_replay_hook(hook)
	collector.unregister_replay_hook(hook)
	collector.capture_error("after hook unregister")
	assert_false(called, "Unregistered replay hook should not be called")


# --- capture_error / capture_crash ---

func test_capture_error_triggers_write() -> void:
	collector.capture_error("test message")
	var path := CrashWriter.get_latest_report_path()
	assert_true(path != "", "CrashWriter should have written a file")


func test_capture_crash_triggers_write() -> void:
	collector.capture_crash("test_kind", "test message")
	var path := CrashWriter.get_latest_report_path()
	assert_true(path != "", "CrashWriter should have written a file")


func test_capture_error_wraps_as_runtime_error() -> void:
	collector.capture_error("boom")
	var text := CrashWriter.get_latest_report_text()
	assert_true(text.contains("runtime_error"), "capture_error should produce kind=runtime_error")


func test_capture_crash_includes_kind() -> void:
	collector.capture_crash("engine_crash", "oops")
	var text := CrashWriter.get_latest_report_text()
	assert_true(text.contains("engine_crash"), "Report should contain the crash kind")


func test_capture_error_stack_trace_in_extra() -> void:
	collector.capture_error("err", "line 42 in foo.gd")
	var text := CrashWriter.get_latest_report_text()
	assert_true(text.contains("stack_trace"), "Stack trace should appear in report")
