extends GutTest

## Unit tests for game-over detection logic.
## Blockudoku: no valid placements remain.
## Shikaku: board fully covered (win condition).

const BlockBoardScript := preload("res://scripts/blockudoku/blockudoku_board.gd")
const ShikakuBoardScript := preload("res://scripts/shikaku/shikaku_board.gd")


# ============================================================
# Blockudoku — has_valid_placement (game over when false)
# ============================================================

var block_board: Control


func before_each() -> void:
	block_board = Control.new()
	block_board.set_script(BlockBoardScript)
	block_board.size = Vector2(360, 360)
	add_child_autofree(block_board)
	block_board._init_grid()


func test_game_not_over_empty_board() -> void:
	var shapes: Array = [[Vector2i(0, 0)]]
	assert_true(block_board.has_valid_placement(shapes))


func test_game_over_full_board_single_cell() -> void:
	for r in 9:
		for c in 9:
			block_board.grid[r * 9 + c] = 1
	var shapes: Array = [[Vector2i(0, 0)]]
	assert_false(block_board.has_valid_placement(shapes))


func test_game_not_over_one_empty_single_cell_shape() -> void:
	for r in 9:
		for c in 9:
			block_board.grid[r * 9 + c] = 1
	block_board.grid[40] = 0  # One empty cell
	var shapes: Array = [[Vector2i(0, 0)]]
	assert_true(block_board.has_valid_placement(shapes))


func test_game_over_shape_doesnt_fit() -> void:
	# Fill everything except one cell — but shape needs 2 adjacent cells
	for r in 9:
		for c in 9:
			block_board.grid[r * 9 + c] = 1
	block_board.grid[40] = 0  # Only cell (4,4) is empty
	var shapes: Array = [[Vector2i(0, 0), Vector2i(1, 0)]]  # Needs 2 horizontal
	assert_false(block_board.has_valid_placement(shapes))


func test_game_not_over_shape_fits_adjacent_empty() -> void:
	for r in 9:
		for c in 9:
			block_board.grid[r * 9 + c] = 1
	block_board.grid[40] = 0  # (4,4)
	block_board.grid[41] = 0  # (5,4)
	var shapes: Array = [[Vector2i(0, 0), Vector2i(1, 0)]]
	assert_true(block_board.has_valid_placement(shapes))


func test_game_over_multiple_shapes_none_fit() -> void:
	for r in 9:
		for c in 9:
			block_board.grid[r * 9 + c] = 1
	block_board.grid[0] = 0  # Only (0,0) empty
	var shapes: Array = [
		[Vector2i(0, 0), Vector2i(1, 0)],  # horizontal 2
		[Vector2i(0, 0), Vector2i(0, 1)],  # vertical 2
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],  # L-shape
	]
	assert_false(block_board.has_valid_placement(shapes))


func test_game_not_over_any_shape_fits() -> void:
	# Most of board full, but enough space for the third shape
	for r in 9:
		for c in 9:
			block_board.grid[r * 9 + c] = 1
	block_board.grid[0] = 0
	block_board.grid[1] = 0
	block_board.grid[9] = 0
	var shapes: Array = [
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],  # 3-wide, won't fit
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],  # L-shape, fits!
	]
	assert_true(block_board.has_valid_placement(shapes))


# ============================================================
# Shikaku — is_fully_covered (win condition)
# ============================================================

func test_shikaku_win_full_coverage() -> void:
	var board := Control.new()
	board.set_script(ShikakuBoardScript)
	board.size = Vector2(200, 200)
	add_child_autofree(board)
	board.setup(4, 4, {Vector2i(0, 0): 8, Vector2i(2, 2): 8})
	board.add_rect(Rect2i(0, 0, 4, 2))
	board.add_rect(Rect2i(0, 2, 4, 2))
	assert_true(board.is_fully_covered())


func test_shikaku_not_won_partial() -> void:
	var board := Control.new()
	board.set_script(ShikakuBoardScript)
	board.size = Vector2(200, 200)
	add_child_autofree(board)
	board.setup(4, 4, {Vector2i(0, 0): 8, Vector2i(2, 2): 8})
	board.add_rect(Rect2i(0, 0, 4, 2))
	assert_false(board.is_fully_covered())


func test_shikaku_not_won_empty() -> void:
	var board := Control.new()
	board.set_script(ShikakuBoardScript)
	board.size = Vector2(200, 200)
	add_child_autofree(board)
	board.setup(3, 3, {Vector2i(0, 0): 9})
	assert_false(board.is_fully_covered())


func test_shikaku_win_single_rect() -> void:
	var board := Control.new()
	board.set_script(ShikakuBoardScript)
	board.size = Vector2(200, 200)
	add_child_autofree(board)
	board.setup(3, 3, {Vector2i(1, 1): 9})
	board.add_rect(Rect2i(0, 0, 3, 3))
	assert_true(board.is_fully_covered())
