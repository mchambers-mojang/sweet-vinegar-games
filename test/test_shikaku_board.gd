extends GutTest

## Unit tests for ShikakuBoard — rect placement, removal, coverage.

const BoardScript := preload("res://scripts/shikaku/shikaku_board.gd")

var board: Control


func before_each() -> void:
	board = Control.new()
	board.set_script(BoardScript)
	board.size = Vector2(300, 300)
	add_child_autofree(board)
	board.setup(5, 5, {
		Vector2i(1, 1): {"area": 6, "shape": ShikakuLogic.SHAPE_ABSENT},
		Vector2i(3, 0): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT},
	})


# --- Setup ---

func test_setup_dimensions() -> void:
	assert_eq(board.grid_width, 5)
	assert_eq(board.grid_height, 5)


func test_setup_numbers() -> void:
	assert_eq(board.numbers[Vector2i(1, 1)], 6)
	assert_eq(board.numbers[Vector2i(3, 0)], 4)


func test_setup_anchors() -> void:
	var a11: Dictionary = board.anchors.get(Vector2i(1, 1), {})
	assert_eq(int(a11.get("area", 0)), 6)
	assert_eq(int(a11.get("shape", -1)), ShikakuLogic.SHAPE_ABSENT)


func test_setup_empty_rects() -> void:
	assert_eq(board.placed_rects.size(), 0)


# --- Legacy format auto-detection ---

func test_setup_legacy_int_format() -> void:
	board.setup(5, 5, {Vector2i(2, 3): 8, Vector2i(0, 0): 4})
	assert_eq(board.numbers[Vector2i(2, 3)], 8)
	assert_eq(board.numbers[Vector2i(0, 0)], 4)


# --- Shape-only anchor ---

func test_setup_shape_only_anchor() -> void:
	board.setup(4, 4, {Vector2i(0, 0): {"area": 0, "shape": ShikakuLogic.SHAPE_TALL}})
	var a: Dictionary = board.anchors.get(Vector2i(0, 0), {})
	assert_eq(int(a.get("area", -1)), 0)
	assert_eq(int(a.get("shape", -1)), ShikakuLogic.SHAPE_TALL)
	# Numbers property only shows area-carrying anchors.
	assert_false(board.numbers.has(Vector2i(0, 0)))


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


# --- Numbers deserialization (legacy compat) ---

func test_numbers_from_string_keys() -> void:
	# Simulates what the replay viewer does after JSON parse (old format)
	var numbers_data := {"2,3": 8.0, "0,0": 4.0}
	var numbers: Dictionary = {}
	for key in numbers_data.keys():
		var parts := str(key).split(",")
		if parts.size() == 2:
			numbers[Vector2i(int(parts[0]), int(parts[1]))] = int(numbers_data[key])
	board.setup(5, 5, numbers)
	assert_eq(board.numbers[Vector2i(2, 3)], 8)
	assert_eq(board.numbers[Vector2i(0, 0)], 4)


# --- Public coordinate API ---

func test_get_cell_screen_rect_steps_by_cell_size() -> void:
	var rect_00: Rect2 = board.get_cell_screen_rect(0, 0)
	var rect_10: Rect2 = board.get_cell_screen_rect(1, 0)
	var rect_01: Rect2 = board.get_cell_screen_rect(0, 1)
	assert_true(absf((rect_10.position.x - rect_00.position.x) - rect_00.size.x) < 0.001)
	assert_true(absf((rect_01.position.y - rect_00.position.y) - rect_00.size.y) < 0.001)


func test_get_cell_center_matches_rect_center() -> void:
	var rect: Rect2 = board.get_cell_screen_rect(2, 3)
	var center: Vector2 = board.get_cell_center(2, 3)
	assert_true(center.distance_to(rect.get_center()) < 0.001)


# ---------------------------------------------------------------------------
# Fix 4 — accessible tooltip set at setup time
# ---------------------------------------------------------------------------

func test_setup_sets_tooltip_text_non_empty() -> void:
	# Board was set up with area-only anchors in before_each — tooltip must not be empty.
	assert_false(board.tooltip_text.is_empty(),
		"tooltip_text must be set at setup() time for screen-reader accessibility")


func test_setup_tooltip_contains_area_description() -> void:
	# The tooltip for area-only anchors should mention cell counts.
	assert_true(board.tooltip_text.contains("cells"),
		"tooltip_text must describe area anchors ('cells')")


func test_setup_shape_only_anchor_tooltip_contains_shape_name() -> void:
	board.setup(5, 5, {Vector2i(2, 2): {"area": 0, "shape": ShikakuLogic.SHAPE_TALL}})
	assert_true(board.tooltip_text.contains("Tall"),
		"tooltip_text must include shape name for shape-only anchors")


func test_setup_combined_anchor_tooltip_contains_both() -> void:
	board.setup(5, 5, {Vector2i(1, 1): {"area": 4, "shape": ShikakuLogic.SHAPE_SQUARE}})
	assert_true(board.tooltip_text.contains("Square"),
		"tooltip_text must include shape name for combined anchors")
	assert_true(board.tooltip_text.contains("4"),
		"tooltip_text must include area for combined anchors")


func test_setup_clears_tooltip_when_no_anchors() -> void:
	board.setup(5, 5, {})
	assert_true(board.tooltip_text.is_empty(),
		"tooltip_text must be empty when there are no anchors")


# ---------------------------------------------------------------------------
# Fix 6 — contradiction highlighting via refresh_error_state
# ---------------------------------------------------------------------------

func test_add_rect_sets_rect_is_wrong_false_by_default() -> void:
	board.add_rect(Rect2i(0, 0, 2, 2))
	assert_eq(board.rect_is_wrong.size(), 1)
	assert_false(board.rect_is_wrong[0], "Newly added rect must default to not-wrong")


func test_refresh_error_state_marks_wrong_rects() -> void:
	board.add_rect(Rect2i(0, 0, 2, 2))
	board.add_rect(Rect2i(2, 0, 3, 1))
	var wrong: Array[Rect2i] = [Rect2i(0, 0, 2, 2)]
	board.refresh_error_state(wrong)
	assert_true(board.rect_is_wrong[0], "Rect matching wrong list must be flagged")
	assert_false(board.rect_is_wrong[1], "Rect not in wrong list must not be flagged")


func test_refresh_error_state_clears_previous_errors() -> void:
	board.add_rect(Rect2i(0, 0, 2, 2))
	board.refresh_error_state([Rect2i(0, 0, 2, 2)])
	assert_true(board.rect_is_wrong[0])
	board.refresh_error_state([])
	assert_false(board.rect_is_wrong[0], "After clearing wrong list, rect must no longer be flagged")


func test_remove_rect_removes_from_error_tracking() -> void:
	board.add_rect(Rect2i(0, 0, 2, 2))
	board.add_rect(Rect2i(2, 0, 3, 1))
	board.refresh_error_state([Rect2i(0, 0, 2, 2)])
	board.remove_rect(0)
	assert_eq(board.rect_is_wrong.size(), 1,
		"rect_is_wrong must be kept in sync with placed_rects after remove")


func test_setup_clears_error_state() -> void:
	board.add_rect(Rect2i(0, 0, 2, 2))
	board.refresh_error_state([Rect2i(0, 0, 2, 2)])
	board.setup(5, 5, {Vector2i(1, 1): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}})
	assert_true(board.rect_is_wrong.is_empty(),
		"rect_is_wrong must be cleared on setup()")
