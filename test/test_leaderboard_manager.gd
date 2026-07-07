extends GutTest

## Unit tests for LeaderboardManager — the platform autoload that auto-submits
## scores to the server on GameEvents.leaderboard_score_ready.
##
## Tests verify:
##   - Submission is skipped when profile is incomplete.
##   - Handler is called without errors when profile is complete.

const ManagerScript := preload("res://scripts/autoload/leaderboard_manager.gd")


# ============================================================
# Setup / teardown
# ============================================================

var manager: Node

# Saved PlayerIdentity state, restored after each test.
var _saved_setup_complete: bool
var _saved_display_name: String
var _saved_device_id: String


func before_each() -> void:
	_saved_setup_complete = PlayerIdentity.is_setup_complete
	_saved_display_name = PlayerIdentity.display_name
	_saved_device_id = PlayerIdentity.device_id

	manager = Node.new()
	manager.set_script(ManagerScript)
	add_child_autofree(manager)
	manager._pending = [] as Array[HTTPRequest]


func after_each() -> void:
	PlayerIdentity.is_setup_complete = _saved_setup_complete
	PlayerIdentity.display_name = _saved_display_name
	PlayerIdentity.device_id = _saved_device_id


# ============================================================
# Profile-gating tests (directly call the handler method)
# ============================================================

func test_no_submit_when_setup_incomplete() -> void:
	PlayerIdentity.is_setup_complete = false
	PlayerIdentity.display_name = "TestPlayer"
	PlayerIdentity.device_id = "00000000-0000-0000-0000-000000000001"

	manager._on_leaderboard_score_ready("sudoku", "easy", 120.0)
	# No HTTPRequest should have been created
	assert_eq(manager._pending.size(), 0)


func test_no_submit_when_display_name_empty() -> void:
	PlayerIdentity.is_setup_complete = true
	PlayerIdentity.display_name = ""
	PlayerIdentity.device_id = "00000000-0000-0000-0000-000000000001"

	manager._on_leaderboard_score_ready("shikaku", "10", 60.0)
	assert_eq(manager._pending.size(), 0)


func test_no_submit_when_device_id_empty() -> void:
	PlayerIdentity.is_setup_complete = true
	PlayerIdentity.display_name = "TestPlayer"
	PlayerIdentity.device_id = ""

	manager._on_leaderboard_score_ready("blockudoku", "standard", 1500.0)
	assert_eq(manager._pending.size(), 0)


func test_submit_creates_http_request_when_profile_complete() -> void:
	PlayerIdentity.is_setup_complete = true
	PlayerIdentity.display_name = "TestPlayer"
	PlayerIdentity.device_id = "00000000-0000-0000-0000-000000000001"

	manager._on_leaderboard_score_ready("sudoku", "medium", 200.0)
	# One HTTPRequest should have been added to _pending
	assert_eq(manager._pending.size(), 1)


# ============================================================
# Cleanup helper
# ============================================================

func test_cleanup_removes_from_pending() -> void:
	var http := HTTPRequest.new()
	manager.add_child(http)
	manager._pending.append(http)

	manager._cleanup(http)
	assert_eq(manager._pending.size(), 0)

