extends GutTest

## Unit tests for NumberPathBoard — interpolation and path state.

const BoardScript := preload("res://scripts/number_path/number_path_board.gd")

var board: Control


func before_each() -> void:
	board = Control.new()
	board.set_script(BoardScript)
	board.size = Vector2(300, 300)
	add_child_autofree(board)
	board.setup(5, 5, [], [])


# --- _interpolate_cells ---

func test_interpolate_same_cell_returns_empty() -> void:
	var result: Array = board._interpolate_cells(Vector2i(2, 2), Vector2i(2, 2))
	assert_eq(result.size(), 0)


func test_interpolate_adjacent_horizontal_returns_one_cell() -> void:
	var result: Array = board._interpolate_cells(Vector2i(1, 2), Vector2i(2, 2))
	assert_eq(result.size(), 1)
	assert_eq(result[0], Vector2i(2, 2))


func test_interpolate_adjacent_vertical_returns_one_cell() -> void:
	var result: Array = board._interpolate_cells(Vector2i(2, 1), Vector2i(2, 2))
	assert_eq(result.size(), 1)
	assert_eq(result[0], Vector2i(2, 2))


func test_interpolate_multi_step_horizontal() -> void:
	# (0,0) → (3,0): should yield (1,0), (2,0), (3,0)
	var result: Array = board._interpolate_cells(Vector2i(0, 0), Vector2i(3, 0))
	assert_eq(result.size(), 3)
	assert_eq(result[0], Vector2i(1, 0))
	assert_eq(result[1], Vector2i(2, 0))
	assert_eq(result[2], Vector2i(3, 0))


func test_interpolate_multi_step_vertical() -> void:
	# (0,0) → (0,3): should yield (0,1), (0,2), (0,3)
	var result: Array = board._interpolate_cells(Vector2i(0, 0), Vector2i(0, 3))
	assert_eq(result.size(), 3)
	assert_eq(result[0], Vector2i(0, 1))
	assert_eq(result[1], Vector2i(0, 2))
	assert_eq(result[2], Vector2i(0, 3))


# --- Regression fix 5: diagonal gestures are rejected ---

func test_interpolate_diagonal_1x1_returns_empty() -> void:
	# A move one step diagonally (dx=1, dy=1) must be rejected, not staircase-walked.
	var result: Array = board._interpolate_cells(Vector2i(1, 1), Vector2i(2, 2))
	assert_eq(result.size(), 0, "Diagonal transition must be rejected")


func test_interpolate_diagonal_2x1_returns_empty() -> void:
	# dx=2, dy=1 — both axes differ; must be rejected.
	var result: Array = board._interpolate_cells(Vector2i(0, 0), Vector2i(2, 1))
	assert_eq(result.size(), 0, "Non-orthogonal transition must be rejected")


func test_interpolate_diagonal_1x2_returns_empty() -> void:
	# dx=1, dy=2 — both axes differ; must be rejected.
	var result: Array = board._interpolate_cells(Vector2i(0, 0), Vector2i(1, 2))
	assert_eq(result.size(), 0, "Non-orthogonal transition must be rejected")


func test_interpolate_diagonal_negative_returns_empty() -> void:
	# dx=-2, dy=-3 — both axes differ; must be rejected.
	var result: Array = board._interpolate_cells(Vector2i(3, 4), Vector2i(1, 1))
	assert_eq(result.size(), 0, "Negative diagonal transition must be rejected")


func test_interpolate_pure_left_not_rejected() -> void:
	# dx=-2, dy=0 — pure horizontal move; must produce intermediate cells.
	var result: Array = board._interpolate_cells(Vector2i(3, 2), Vector2i(1, 2))
	assert_eq(result.size(), 2)
	assert_eq(result[0], Vector2i(2, 2))
	assert_eq(result[1], Vector2i(1, 2))


# --- Path state helpers ---

func test_extend_path_appends_cell() -> void:
	board.extend_path(Vector2i(0, 0))
	board.extend_path(Vector2i(1, 0))
	assert_eq(board._path.size(), 2)
	assert_eq(board._path[1], Vector2i(1, 0))


func test_truncate_path_reduces_length() -> void:
	board.extend_path(Vector2i(0, 0))
	board.extend_path(Vector2i(1, 0))
	board.extend_path(Vector2i(2, 0))
	board.truncate_path(2)
	assert_eq(board._path.size(), 2)


func test_set_path_replaces_path() -> void:
	board.extend_path(Vector2i(0, 0))
	var new_path: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1)]
	board.set_path(new_path)
	assert_eq(board._path.size(), 2)
	assert_eq(board._path[0], Vector2i(1, 1))
