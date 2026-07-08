extends GutTest

## Unit tests for GameEvents event bus and platform listener subscriptions.
## Tests verify:
##   - GameEvents signals have correct parameters.
##   - Listener handler methods (called directly) produce the expected side-effects.

const AnalyticsScript := preload("res://scripts/autoload/analytics_manager.gd")
const CollectorScript := preload("res://scripts/autoload/crash_collector.gd")
const StatsScript := preload("res://scripts/autoload/game_stats_manager.gd")
const RecorderScript := preload("res://scripts/replays/replay_recorder.gd")


# ============================================================
# GameEvents — signal emission
# ============================================================

func test_game_started_signal_emits_correct_params() -> void:
	var received := {}
	var conn := func(game_id: String, difficulty: int, rules: Dictionary) -> void:
		received["game_id"] = game_id
		received["difficulty"] = difficulty
		received["rules"] = rules
	GameEvents.game_started.connect(conn)
	GameEvents.game_started.emit("blockudoku", -1, {"mode": "classic"})
	GameEvents.game_started.disconnect(conn)
	assert_eq(received.get("game_id"), "blockudoku")
	assert_eq(received.get("difficulty"), -1)
	assert_eq(received.get("rules"), {"mode": "classic"})


func test_game_ended_signal_emits_correct_params() -> void:
	var received := {}
	var conn := func(game_id: String, outcome: String, duration: float) -> void:
		received["game_id"] = game_id
		received["outcome"] = outcome
		received["duration"] = duration
	GameEvents.game_ended.connect(conn)
	GameEvents.game_ended.emit("sudoku", "win", 120.5)
	GameEvents.game_ended.disconnect(conn)
	assert_eq(received.get("game_id"), "sudoku")
	assert_eq(received.get("outcome"), "win")
	assert_almost_eq(received.get("duration") as float, 120.5, 0.001)


func test_move_made_signal_emits_correct_params() -> void:
	var received := {}
	var conn := func(game_id: String, move_data: Dictionary) -> void:
		received["game_id"] = game_id
		received["move_data"] = move_data
	GameEvents.move_made.connect(conn)
	GameEvents.move_made.emit("shikaku", {"elapsed_time": 3.0, "event_type": "rectangle_placed", "x": 0, "y": 0})
	GameEvents.move_made.disconnect(conn)
	assert_eq(received.get("game_id"), "shikaku")
	var md: Dictionary = received.get("move_data", {})
	assert_eq(md.get("event_type"), "rectangle_placed")


func test_score_changed_signal_emits_correct_params() -> void:
	var received := {}
	var conn := func(game_id: String, old_score: int, new_score: int) -> void:
		received["game_id"] = game_id
		received["old_score"] = old_score
		received["new_score"] = new_score
	GameEvents.score_changed.connect(conn)
	GameEvents.score_changed.emit("blockudoku", 100, 250)
	GameEvents.score_changed.disconnect(conn)
	assert_eq(received.get("game_id"), "blockudoku")
	assert_eq(received.get("old_score"), 100)
	assert_eq(received.get("new_score"), 250)


func test_leaderboard_score_ready_signal_emits_correct_params() -> void:
	var received := {}
	var conn := func(game_id: String, mode: String, value: float) -> void:
		received["game_id"] = game_id
		received["mode"] = mode
		received["value"] = value
	GameEvents.leaderboard_score_ready.connect(conn)
	GameEvents.leaderboard_score_ready.emit("sudoku", "hard", 95.5)
	GameEvents.leaderboard_score_ready.disconnect(conn)
	assert_eq(received.get("game_id"), "sudoku")
	assert_eq(received.get("mode"), "hard")
	assert_almost_eq(received.get("value") as float, 95.5, 0.001)


# ============================================================
# AnalyticsManager — GameEvents handler methods
# ============================================================

var analytics: Node


func _setup_analytics() -> void:
	analytics = Node.new()
	analytics.set_script(AnalyticsScript)
	add_child_autofree(analytics)
	analytics._events = [] as Array[Dictionary]
	analytics._session_id = "test-session"
	analytics._sinks = [] as Array[Object]


func test_analytics_game_started_handler_logs_event() -> void:
	_setup_analytics()
	analytics._on_game_events_game_started("blockudoku", -1, {"mode": "classic"})
	assert_eq(analytics._events.size(), 1)
	assert_eq(analytics._events[0]["name"], "game_started")
	assert_eq(analytics._events[0]["properties"]["mode"], "classic")


func test_analytics_score_changed_handler_logs_event() -> void:
	_setup_analytics()
	analytics._on_game_events_score_changed("blockudoku", 50, 150)
	assert_eq(analytics._events.size(), 1)
	assert_eq(analytics._events[0]["name"], "score_changed")
	assert_eq(analytics._events[0]["properties"]["game"], "blockudoku")
	assert_eq(analytics._events[0]["properties"]["old_score"], 50)
	assert_eq(analytics._events[0]["properties"]["new_score"], 150)


# ============================================================
# CrashCollector — GameEvents handler methods
# ============================================================

var collector: Node


func _setup_collector() -> void:
	collector = Node.new()
	collector.set_script(CollectorScript)
	add_child_autofree(collector)
	collector._recent_actions = [] as Array[Dictionary]
	collector._state_providers = [] as Array[Callable]
	collector._replay_hooks = [] as Array[Callable]
	collector._log_file_path = ""
	collector._last_log_size = 0
	collector._error_check_timer = 0.0


func test_crash_collector_game_started_handler_registers_action() -> void:
	_setup_collector()
	collector._on_game_events_game_started("sudoku", 2, {"difficulty": 2})
	assert_eq(collector._recent_actions.size(), 1)
	assert_eq(collector._recent_actions[0]["action"], "sudoku_game_started")


func test_crash_collector_game_ended_handler_registers_action() -> void:
	_setup_collector()
	collector._on_game_events_game_ended("blockudoku", "game_over", 45.0)
	assert_eq(collector._recent_actions.size(), 1)
	assert_eq(collector._recent_actions[0]["action"], "blockudoku_game_ended")
	assert_eq(collector._recent_actions[0]["metadata"]["outcome"], "game_over")


# ============================================================
# GameStatsManager — GameEvents handler methods
# ============================================================

var stats: Node


func _setup_stats() -> void:
	stats = Node.new()
	stats.set_script(StatsScript)
	add_child_autofree(stats)
	stats._history_cache = {}
	stats._counters_cache = {}


func test_stats_game_ended_handler_increments_total_sessions() -> void:
	_setup_stats()
	stats._on_game_events_game_ended("shikaku", "win", 90.0)
	assert_eq(stats.get_counter("shikaku", "total_sessions_ended"), 1)


func test_stats_game_ended_handler_increments_outcome_counter() -> void:
	_setup_stats()
	stats._on_game_events_game_ended("sudoku", "win", 30.0)
	assert_eq(stats.get_counter("sudoku", "sessions_ended_win"), 1)


func test_stats_game_ended_handler_increments_game_over_outcome() -> void:
	_setup_stats()
	stats._on_game_events_game_ended("blockudoku", "game_over", 60.0)
	assert_eq(stats.get_counter("blockudoku", "sessions_ended_game_over"), 1)


# ============================================================
# ReplayRecorder — GameEvents handler methods
# ============================================================

var recorder: Node


func _setup_recorder() -> void:
	recorder = Node.new()
	recorder.set_script(RecorderScript)
	add_child_autofree(recorder)
	recorder._active_replay = {}
	recorder._id_rng = RandomNumberGenerator.new()
	recorder._active_sequence = 0
	recorder._save_timer = 0.0
	recorder._dirty = false


func test_recorder_move_made_handler_records_input() -> void:
	_setup_recorder()
	recorder.start_session("shikaku", 1, {})
	recorder._dirty = false
	recorder._on_game_events_move_made("shikaku", {
		"elapsed_time": 5.0,
		"event_type": "rectangle_placed",
		"x": 1,
		"y": 2,
		"w": 3,
		"h": 4,
	})
	var frames: Array = recorder._active_replay["frames"]
	assert_eq(frames.size(), 1)
	assert_eq(frames[0]["input_event"]["type"], "rectangle_placed")
	assert_eq(frames[0]["input_event"]["payload"]["x"], 1)
	assert_false(frames[0]["input_event"]["payload"].has("elapsed_time"))
	assert_false(frames[0]["input_event"]["payload"].has("event_type"))


func test_recorder_move_made_handler_noop_without_session() -> void:
	_setup_recorder()
	# No active session — should be a noop
	recorder._on_game_events_move_made("blockudoku", {
		"elapsed_time": 1.0,
		"event_type": "piece_placed",
	})
	assert_true(recorder._active_replay.is_empty())


func test_recorder_move_made_handler_tick_converted_correctly() -> void:
	_setup_recorder()
	recorder.start_session("blockudoku", 42, {})
	recorder._on_game_events_move_made("blockudoku", {
		"elapsed_time": 2.5,
		"event_type": "piece_placed",
	})
	var frames: Array = recorder._active_replay["frames"]
	assert_eq(frames[0]["tick"], 2500)
