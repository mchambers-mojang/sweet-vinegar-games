extends GutTest

## Unit tests for NumberPathReplayAdapter — apply_frame behaviour.
## Regression coverage for:
##   Fix 3: undo_applied restores the complete path (not just truncates)
##   Fix 4: hint_applied with contradiction:true leaves geometry unchanged

const BoardScript := preload("res://scripts/number_path/number_path_board.gd")

var adapter: NumberPathReplayAdapter
var board: Control


func _make_frame(event_type: String, payload: Dictionary) -> Dictionary:
	return {"input_event": {"type": event_type, "payload": payload}}


func before_each() -> void:
	adapter = NumberPathReplayAdapter.new()
	board = Control.new()
	board.set_script(BoardScript)
	board.size = Vector2(300, 300)
	add_child_autofree(board)
	board.setup(5, 5,
		[{"x": 0, "y": 0, "n": 1}, {"x": 4, "y": 4, "n": 2}],
		[])
	# Start with a two-cell path
	board.set_path([Vector2i(0, 0), Vector2i(1, 0)])


# --- path_extended ---

func test_path_extended_appends_cell() -> void:
	adapter.apply_frame(_make_frame("path_extended", {"x": 2, "y": 0}), board)
	assert_eq(board._path.size(), 3)
	assert_eq(board._path[2], Vector2i(2, 0))


# --- path_truncated ---

func test_path_truncated_reduces_path() -> void:
	adapter.apply_frame(_make_frame("path_truncated", {"length": 1}), board)
	assert_eq(board._path.size(), 1)


# --- Regression Fix 4: hint_applied with contradiction leaves path unchanged ---

func test_hint_applied_contradiction_leaves_path_unchanged() -> void:
	var before_size := board._path.size()
	var before_head := board._path[board._path.size() - 1]
	adapter.apply_frame(_make_frame("hint_applied", {"contradiction": true}), board)
	assert_eq(board._path.size(), before_size, "Contradiction hint must not extend path")
	assert_eq(board._path[board._path.size() - 1], before_head, "Contradiction hint must not change head")


func test_hint_applied_normal_extends_path() -> void:
	adapter.apply_frame(_make_frame("hint_applied", {"x": 2, "y": 0}), board)
	assert_eq(board._path.size(), 3)
	assert_eq(board._path[2], Vector2i(2, 0))


# --- Regression Fix 3: undo_applied with path field restores full path ---

func test_undo_applied_with_path_field_restores_full_path() -> void:
	# Path currently is [(0,0),(1,0)]. Simulate undo that restores a longer path
	# (i.e., the undo restored a state BEFORE a truncation — path grows).
	var restored := [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}]
	adapter.apply_frame(_make_frame("undo_applied", {
		"length": 3,
		"path": restored,
	}), board)
	assert_eq(board._path.size(), 3, "undo_applied must grow path when restoring prior extension")
	assert_eq(board._path[2], Vector2i(2, 0))


func test_undo_applied_with_path_field_can_shrink_path() -> void:
	# Undo that restores a shorter state (after undoing an extension).
	board.extend_path(Vector2i(2, 0))
	assert_eq(board._path.size(), 3)
	var restored := [{"x": 0, "y": 0}]
	adapter.apply_frame(_make_frame("undo_applied", {
		"length": 1,
		"path": restored,
	}), board)
	assert_eq(board._path.size(), 1)
	assert_eq(board._path[0], Vector2i(0, 0))


func test_undo_applied_legacy_no_path_field_truncates() -> void:
	# Legacy replays only have "length" — adapter must fall back to truncate.
	board.extend_path(Vector2i(2, 0))
	assert_eq(board._path.size(), 3)
	adapter.apply_frame(_make_frame("undo_applied", {"length": 2}), board)
	assert_eq(board._path.size(), 2)


# --- redo_applied ---

func test_redo_applied_with_path_field_restores_path() -> void:
	var restored := [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}]
	adapter.apply_frame(_make_frame("redo_applied", {
		"length": 3,
		"path": restored,
	}), board)
	assert_eq(board._path.size(), 3)
	assert_eq(board._path[2], Vector2i(2, 0))
