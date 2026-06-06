extends GutTest

## Unit tests for ShikakuBoard — rect placement, removal, coverage.

const BoardScript := preload("res://scripts/shikaku/shikaku_board.gd")

var board: Control


func before_each() -> void:
	board = Control.new()
	board.set_script(BoardScript)
	board.size = Vector2(300, 300)
	add_child_autofree(board)
	board.setup(5, 5, {Vector2i(1, 1): 6, Vector2i(3, 0): 4})


# --- Setup ---

func test_setup_dimensions() -> void:
	assert_eq(board.grid_width, 5)
	assert_eq(board.grid_height, 5)


func test_setup_numbers() -> void:
	assert_eq(board.numbers[Vector2i(1, 1)], 6)
	assert_eq(board.numbers[Vector2i(3, 0)], 4)


func test_setup_empty_rects() -> void:
	assert_eq(board.placed_rects.size(), 0)


# --- Placement ---

func test_add_rect() -> void:
	board.add_rect(Rect2i(0, 0, 3, 2))
	assert_eq(board.placed_rects.size(), 1)
	assert_eq(board.placed_rects[0], Rect2i(0, 0, 3, 2))


func test_add_multiple_rects() -> void:
	board.add_rect(Rect2i(0, 0, 2, 2))
	board.add_rect(Rect2i(2, 0, 3, 1))
	assert_eq(board.placed_rects.size(), 2)


# --- Removal ---

func test_remove_rect_by_index() -> void:
	board.add_rect(Rect2i(0, 0, 2, 2))
	board.add_rect(Rect2i(2, 0, 3, 1))
	board.remove_rect(0)
	assert_eq(board.placed_rects.size(), 1)
	assert_eq(board.placed_rects[0], Rect2i(2, 0, 3, 1))


func test_remove_rect_shifts_indices() -> void:
	board.add_rect(Rect2i(0, 0, 1, 1))
	board.add_rect(Rect2i(1, 0, 1, 1))
	board.add_rect(Rect2i(2, 0, 1, 1))
	board.remove_rect(1)
	assert_eq(board.placed_rects[1], Rect2i(2, 0, 1, 1))


# --- Coverage ---

func test_not_fully_covered_empty() -> void:
	assert_false(board.is_fully_covered())


func test_fully_covered() -> void:
	board.add_rect(Rect2i(0, 0, 5, 5))
	assert_true(board.is_fully_covered())


func test_partially_covered() -> void:
	board.add_rect(Rect2i(0, 0, 5, 4))
	assert_false(board.is_fully_covered())


# --- Replay index consistency ---

func test_remove_add_sequence_indices() -> void:
	board.add_rect(Rect2i(0, 0, 2, 2))  # index 0 = A
	board.add_rect(Rect2i(2, 0, 2, 2))  # index 1 = B
	board.remove_rect(0)                  # Remove A, B shifts to 0
	board.add_rect(Rect2i(0, 2, 2, 2))  # index 1 = C
	assert_eq(board.placed_rects.size(), 2)
	assert_eq(board.placed_rects[0], Rect2i(2, 0, 2, 2))  # B
	assert_eq(board.placed_rects[1], Rect2i(0, 2, 2, 2))  # C


# --- Numbers deserialization ---

func test_numbers_from_string_keys() -> void:
	# Simulates what the replay viewer does after JSON parse
	var numbers_data := {"2,3": 8.0, "0,0": 4.0}
	var numbers: Dictionary = {}
	for key in numbers_data.keys():
		var parts := str(key).split(",")
		if parts.size() == 2:
			numbers[Vector2i(int(parts[0]), int(parts[1]))] = int(numbers_data[key])
	board.setup(5, 5, numbers)
	assert_eq(board.numbers[Vector2i(2, 3)], 8)
	assert_eq(board.numbers[Vector2i(0, 0)], 4)
