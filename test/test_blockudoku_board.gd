extends GutTest

## Unit tests for BlockudokuBoard — grid state, placement, clears, serialization.

const BoardScript := preload("res://scripts/blockudoku/blockudoku_board.gd")

var board: Control


func before_each() -> void:
	board = Control.new()
	board.set_script(BoardScript)
	board.size = Vector2(360, 360)
	add_child_autofree(board)
	board._init_grid()


# --- Grid initialization ---

func test_grid_starts_empty() -> void:
	assert_eq(board.grid.size(), 81)
	for i in 81:
		assert_eq(board.grid[i], 0, "Cell %d should be 0" % i)


func test_cell_colors_start_transparent() -> void:
	assert_eq(board.cell_colors.size(), 81)
	for i in 81:
		assert_eq(board.cell_colors[i], Color.TRANSPARENT)


# --- Placement ---

func test_place_single_cell() -> void:
	var shape: Array[Vector2i] = [Vector2i(0, 0)]
	board.place_block(shape, 3, 4)
	assert_eq(board.grid[4 * 9 + 3], 1)
	assert_ne(board.cell_colors[4 * 9 + 3], Color.TRANSPARENT)


func test_place_l_shape() -> void:
	var shape: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	board.place_block(shape, 0, 0)
	assert_eq(board.grid[0], 1)   # (0,0)
	assert_eq(board.grid[1], 1)   # (1,0)
	assert_eq(board.grid[9], 1)   # (0,1)
	assert_eq(board.grid[10], 0)  # (1,1) empty


func test_can_place_valid() -> void:
	var shape: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	assert_true(board.can_place(shape, 0, 0))


func test_can_place_out_of_bounds() -> void:
	var shape: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	assert_false(board.can_place(shape, 8, 0))


func test_can_place_occupied() -> void:
	var shape: Array[Vector2i] = [Vector2i(0, 0)]
	board.place_block(shape, 3, 3)
	assert_false(board.can_place(shape, 3, 3))


# --- Line clearing ---

func test_clear_full_row() -> void:
	var shape: Array[Vector2i] = [Vector2i(0, 0)]
	for c in 9:
		board.place_block(shape, c, 0)
	var result: Dictionary = board.check_and_clear()
	assert_eq(result["cleared"], 9)
	assert_eq(result["lines"], 1)
	for c in 9:
		assert_eq(board.grid[c], 0, "Cell (%d,0) should be cleared" % c)


func test_clear_full_column() -> void:
	var shape: Array[Vector2i] = [Vector2i(0, 0)]
	for r in 9:
		board.place_block(shape, 0, r)
	var result: Dictionary = board.check_and_clear()
	assert_eq(result["cleared"], 9)
	assert_eq(result["lines"], 1)


func test_clear_full_box() -> void:
	var shape: Array[Vector2i] = [Vector2i(0, 0)]
	for r in 3:
		for c in 3:
			board.place_block(shape, c, r)
	var result: Dictionary = board.check_and_clear()
	assert_eq(result["boxes"], 1)
	assert_eq(result["cleared"], 9)


func test_no_clear_partial_row() -> void:
	var shape: Array[Vector2i] = [Vector2i(0, 0)]
	for c in 8:
		board.place_block(shape, c, 0)
	var result: Dictionary = board.check_and_clear()
	assert_eq(result["cleared"], 0)


# --- Serialization roundtrip (the bug we fixed) ---

func test_get_set_state_roundtrip() -> void:
	var shape: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	board.place_block(shape, 2, 5)
	var state: Dictionary = board.get_state()
	# Simulate JSON roundtrip (numbers become floats)
	var json_str := JSON.stringify(state)
	var restored_state = JSON.parse_string(json_str)
	board.reset()
	board.set_state(restored_state)
	assert_eq(board.grid[5 * 9 + 2], 1)
	assert_eq(board.grid[5 * 9 + 3], 1)
	assert_eq(board.grid[5 * 9 + 4], 1)
	assert_eq(board.grid[0], 0)


func test_set_state_handles_float_grid_from_json() -> void:
	var grid_data: Array = []
	grid_data.resize(81)
	for i in 81:
		grid_data[i] = 0.0
	grid_data[0] = 1.0
	grid_data[40] = 1.0
	var colors: Array = []
	colors.resize(81)
	for i in 81:
		colors[i] = "00000000"
	colors[0] = "ff0000ff"
	colors[40] = "00ff00ff"
	var state := {"grid": grid_data, "cell_colors": colors, "color_index": 0}
	board.set_state(state)
	assert_eq(board.grid[0], 1)
	assert_eq(board.grid[40], 1)
	assert_eq(board.grid[1], 0)


# --- Reset ---

func test_reset_clears_grid() -> void:
	var shape: Array[Vector2i] = [Vector2i(0, 0)]
	board.place_block(shape, 4, 4)
	board.reset()
	assert_eq(board.grid[4 * 9 + 4], 0)
	assert_eq(board.cell_colors[4 * 9 + 4], Color.TRANSPARENT)


# --- has_valid_placement ---

func test_has_valid_placement_empty_board() -> void:
	var shapes: Array = [[Vector2i(0, 0)]]
	assert_true(board.has_valid_placement(shapes))


func test_has_valid_placement_full_board() -> void:
	for r in 9:
		for c in 9:
			board.grid[r * 9 + c] = 1
	var shapes: Array = [[Vector2i(0, 0)]]
	assert_false(board.has_valid_placement(shapes))


# --- Public coordinate API ---

func test_get_cell_screen_rect_steps_by_cell_size() -> void:
	var rect_00: Rect2 = board.get_cell_screen_rect(0, 0)
	var rect_10: Rect2 = board.get_cell_screen_rect(1, 0)
	var rect_01: Rect2 = board.get_cell_screen_rect(0, 1)
	assert_true(absf((rect_10.position.x - rect_00.position.x) - rect_00.size.x) < 0.001)
	assert_true(absf((rect_01.position.y - rect_00.position.y) - rect_00.size.y) < 0.001)


func test_get_cell_center_matches_rect_center() -> void:
	var rect: Rect2 = board.get_cell_screen_rect(3, 4)
	var center: Vector2 = board.get_cell_center(3, 4)
	assert_true(center.distance_to(rect.get_center()) < 0.001)
