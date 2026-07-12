extends GutTest

## Unit tests for LeaderboardManager — the platform autoload that auto-submits
## scores to the server on GameEvents.leaderboard_score_ready.
##
## Tests verify:
##   - Submission is skipped when profile is incomplete.
##   - Handler is called without errors when profile is complete.

const LeaderboardScreenScript := preload("res://scripts/ui/leaderboard_screen.gd")
const BlockudokuScreenScript := preload("res://scripts/blockudoku/blockudoku_game_screen.gd")


class MockStats:
	var high_score: int

	func _init(initial_high_score: int) -> void:
		high_score = initial_high_score

	func get_counter(_game_id: String, _counter_name: String) -> int:
		return high_score

	func set_counter(_game_id: String, _counter_name: String, value: int) -> void:
		high_score = value


class TestManager extends "res://scripts/autoload/leaderboard_manager.gd":
	var submissions: Array[Dictionary] = []

	func _submit(game_id: String, mode: String, value: float) -> void:
		submissions.append({
			"game_id": game_id,
			"mode": mode,
			"value": value,
		})


# ============================================================
# Setup / teardown
# ============================================================

var manager: Node

# Saved PlayerIdentity state, restored after each test.
var _saved_setup_complete: bool
var _saved_display_name: String
var _saved_device_id: String
var _saved_data_enabled: bool


func before_each() -> void:
	_saved_setup_complete = PlayerIdentity.is_setup_complete
	_saved_display_name = PlayerIdentity.display_name
	_saved_device_id = PlayerIdentity.device_id
	_saved_data_enabled = PlayerIdentity.leaderboard_data_enabled

	manager = TestManager.new()
	add_child_autofree(manager)
	manager._pending = [] as Array[HTTPRequest]


func after_each() -> void:
	PlayerIdentity.is_setup_complete = _saved_setup_complete
	PlayerIdentity.display_name = _saved_display_name
	PlayerIdentity.device_id = _saved_device_id
	PlayerIdentity.leaderboard_data_enabled = _saved_data_enabled


# ============================================================
# Profile-gating tests (directly call the handler method)
# ============================================================

func test_no_submit_when_setup_incomplete() -> void:
	PlayerIdentity.is_setup_complete = false
	PlayerIdentity.display_name = "TestPlayer"
	PlayerIdentity.device_id = "00000000-0000-0000-0000-000000000001"

	manager._on_leaderboard_score_ready("sudoku", "easy", 120.0)
	assert_eq(manager.submissions.size(), 0)


func test_no_submit_when_display_name_empty() -> void:
	PlayerIdentity.is_setup_complete = true
	PlayerIdentity.display_name = ""
	PlayerIdentity.device_id = "00000000-0000-0000-0000-000000000001"

	manager._on_leaderboard_score_ready("shikaku", "10", 60.0)
	assert_eq(manager.submissions.size(), 0)


func test_no_submit_when_device_id_empty() -> void:
	PlayerIdentity.is_setup_complete = true
	PlayerIdentity.display_name = "TestPlayer"
	PlayerIdentity.device_id = ""

	manager._on_leaderboard_score_ready("blockudoku", "standard", 1500.0)
	assert_eq(manager.submissions.size(), 0)


func test_submit_creates_http_request_when_profile_complete() -> void:
	PlayerIdentity.is_setup_complete = true
	PlayerIdentity.display_name = "TestPlayer"
	PlayerIdentity.device_id = "00000000-0000-0000-0000-000000000001"
	PlayerIdentity.leaderboard_data_enabled = true

	manager._on_leaderboard_score_ready("sudoku", "medium", 200.0)
	assert_eq(manager.submissions, [{
		"game_id": "sudoku",
		"mode": "medium",
		"value": 200.0,
	}])


func test_no_submit_when_data_disabled() -> void:
	PlayerIdentity.is_setup_complete = true
	PlayerIdentity.display_name = "TestPlayer"
	PlayerIdentity.device_id = "00000000-0000-0000-0000-000000000001"
	PlayerIdentity.leaderboard_data_enabled = false

	manager._on_leaderboard_score_ready("sudoku", "easy", 120.0)
	# Kill switch must prevent any network request
	assert_eq(manager.submissions.size(), 0)


# ============================================================
# Cleanup helper
# ============================================================

func test_cleanup_removes_from_pending() -> void:
	var http := HTTPRequest.new()
	manager.add_child(http)
	manager._pending.append(http)

	manager._cleanup(http)
	assert_eq(manager._pending.size(), 0)


func test_blockudoku_leaderboard_score_restores_local_personal_best() -> void:
	var stats := MockStats.new(0)
	var screen := LeaderboardScreenScript.new()
	screen.set("_stats", stats)
	screen.set("_game_id", "blockudoku")
	screen.set("_current_mode", "standard")

	screen.call("_sync_personal_best", 1200.0)

	assert_eq(stats.high_score, 1200)
	var game_screen: Node = BlockudokuScreenScript.new()
	game_screen._stats = stats
	game_screen.logic = BlockudokuLogic.new()
	game_screen.logic.score = 3
	game_screen._check_for_new_best()
	assert_false(game_screen._new_best_shown, "First placement must not beat the synchronized personal best")
	game_screen.free()
	screen.free()


func test_blockudoku_leaderboard_score_never_lowers_local_personal_best() -> void:
	var stats := MockStats.new(1500)
	var screen := LeaderboardScreenScript.new()
	screen.set("_stats", stats)
	screen.set("_game_id", "blockudoku")
	screen.set("_current_mode", "standard")

	screen.call("_sync_personal_best", 1200.0)

	assert_eq(stats.high_score, 1500)
	screen.free()
