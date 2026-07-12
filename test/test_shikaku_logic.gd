extends GutTest

var logic: ShikakuLogic


func before_each() -> void:
	logic = ShikakuLogic.new()
	logic.init_from_save({
		"width": 2,
		"height": 2,
		"numbers": {"0,0": 2, "0,1": 2},
		"solution": [
			{"x": 0, "y": 0, "w": 2, "h": 1},
			{"x": 0, "y": 1, "w": 2, "h": 1},
		],
		"placed_rects": [],
		"random_seed": 1234,
	})


func test_new_game_generates_valid_puzzle() -> void:
	var fresh := ShikakuLogic.new()
	fresh.init_new_game(5, 5, 42)
	assert_true(fresh.numbers.size() > 0)
	assert_true(fresh.solution.size() > 0)
	assert_true(ShikakuSolver.validate(fresh.grid_width, fresh.grid_height, fresh.numbers, fresh.solution))


func test_place_valid_rectangle() -> void:
	var result: ShikakuLogic.PlaceRectResult = logic.place_rectangle(0, 0, 2, 1)
	assert_true(result.valid)
	assert_false(result.game_won)
	assert_eq(logic.placed_rects.size(), 1)
	assert_eq(logic.undo_stack.size(), 1)


func test_place_rectangle_wins() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	var result: ShikakuLogic.PlaceRectResult = logic.place_rectangle(0, 1, 2, 1)
	assert_true(result.valid)
	assert_true(result.game_won)
	assert_true(logic.is_completed)


func test_remove_rectangle() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	var result: ShikakuLogic.RemoveRectResult = logic.remove_rectangle(0, 0, 2, 1)
	assert_true(result.was_present)
	assert_eq(logic.placed_rects.size(), 0)


func test_undo_place() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	var result: ShikakuLogic.UndoRedoResult = logic.undo()
	assert_eq(result.action_type, "place")
	assert_eq(logic.placed_rects.size(), 0)
	assert_eq(logic.redo_stack.size(), 1)


func test_undo_remove() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	logic.remove_rectangle(0, 0, 2, 1)
	var result: ShikakuLogic.UndoRedoResult = logic.undo()
	assert_eq(result.action_type, "remove")
	assert_eq(logic.placed_rects.size(), 1)


func test_redo_after_undo() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	logic.undo()
	var result: ShikakuLogic.UndoRedoResult = logic.redo()
	assert_eq(result.action_type, "place")
	assert_eq(logic.placed_rects.size(), 1)


func test_hint_places_from_solution() -> void:
	var result: ShikakuLogic.HintResult = logic.use_hint()
	assert_false(result.rect.is_empty())
	assert_eq(logic.placed_rects.size(), 1)
	assert_eq(logic.hints_used, 1)


func test_hint_wins_game() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	var result: ShikakuLogic.HintResult = logic.use_hint()
	assert_false(result.rect.is_empty())
	assert_true(result.game_won)
	assert_true(logic.is_completed)


func test_serialize_deserialize_roundtrip() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	logic.remove_rectangle(0, 0, 2, 1)
	logic.undo()
	var data: Dictionary = logic.serialize()

	var restored := ShikakuLogic.new()
	restored.init_from_save(data)

	assert_eq(restored.grid_width, logic.grid_width)
	assert_eq(restored.grid_height, logic.grid_height)
	assert_eq(restored.numbers, logic.numbers)
	assert_eq(restored.solution, logic.solution)
	assert_eq(restored.placed_rects, logic.placed_rects)
	assert_eq(restored.undo_stack, logic.undo_stack)
	assert_eq(restored.redo_stack, logic.redo_stack)
	assert_eq(restored.hints_used, logic.hints_used)


func test_coverage_tracking() -> void:
	assert_false(logic.is_fully_covered())
	logic.place_rectangle(0, 0, 2, 1)
	assert_eq(logic.get_coverage_at(0, 0), 1)
	assert_eq(logic.get_coverage_at(1, 1), 0)
	assert_false(logic.is_fully_covered())
	logic.place_rectangle(0, 1, 2, 1)
	assert_true(logic.is_fully_covered())
	logic.remove_rectangle(0, 1, 2, 1)
	assert_false(logic.is_fully_covered())


func test_redo_stack_cleared_on_new_action() -> void:
	var puzzle := ShikakuLogic.new()
	puzzle.init_from_save({
		"width": 3,
		"height": 2,
		"numbers": {"0,0": 2, "1,0": 2, "2,0": 2},
		"solution": [
			{"x": 0, "y": 0, "w": 1, "h": 2},
			{"x": 1, "y": 0, "w": 1, "h": 2},
			{"x": 2, "y": 0, "w": 1, "h": 2},
		],
		"placed_rects": [],
		"random_seed": 1234,
	})
	puzzle.place_rectangle(0, 0, 1, 2)
	puzzle.place_rectangle(1, 0, 1, 2)
	puzzle.undo()
	assert_eq(puzzle.redo_stack.size(), 1)
	puzzle.place_rectangle(2, 0, 1, 2)
	assert_true(puzzle.redo_stack.is_empty())


func test_can_undo_redo_hint_initial_state() -> void:
	assert_false(logic.can_undo())
	assert_false(logic.can_redo())
	assert_true(logic.can_hint())


func test_can_undo_after_place() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	assert_true(logic.can_undo())
	assert_false(logic.can_redo())


func test_can_redo_after_undo() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	logic.undo()
	assert_false(logic.can_undo())
	assert_true(logic.can_redo())


func test_can_hint_false_after_used() -> void:
	logic.use_hint()
	assert_false(logic.can_hint())


func test_can_undo_redo_false_when_completed() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	logic.place_rectangle(0, 1, 2, 1)
	assert_true(logic.is_completed)
	assert_false(logic.can_undo())
	assert_false(logic.can_redo())
	assert_false(logic.can_hint())


func test_get_unplaced_solution_rects_empty_when_all_placed() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	logic.place_rectangle(0, 1, 2, 1)
	assert_true(logic.get_unplaced_solution_rects().is_empty())


func test_get_unplaced_solution_rects_returns_remaining() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	var unplaced := logic.get_unplaced_solution_rects()
	assert_eq(unplaced.size(), 1)
	assert_eq(unplaced[0], Rect2i(0, 1, 2, 1))


func test_get_unplaced_solution_rects_all_when_none_placed() -> void:
	var unplaced := logic.get_unplaced_solution_rects()
	assert_eq(unplaced.size(), logic.solution.size())
