extends GutTest

var logic: ShikakuLogic


func before_each() -> void:
	logic = ShikakuLogic.new()
	logic.init_from_save({
		"width": 2,
		"height": 2,
		"anchors": {
			"0,0": {"area": 2, "shape": ShikakuLogic.SHAPE_ABSENT},
			"0,1": {"area": 2, "shape": ShikakuLogic.SHAPE_ABSENT},
		},
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
	assert_true(fresh.anchors.size() > 0)
	assert_true(fresh.solution.size() > 0)
	assert_true(ShikakuSolver.validate_anchors(fresh.grid_width, fresh.grid_height, fresh.anchors, fresh.solution))


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
	assert_eq(restored.anchors, logic.anchors)
	assert_eq(restored.solution, logic.solution)
	assert_eq(restored.placed_rects, logic.placed_rects)
	assert_eq(restored.undo_stack, logic.undo_stack)
	assert_eq(restored.redo_stack, logic.redo_stack)
	assert_eq(restored.hints_used, logic.hints_used)


func test_legacy_numbers_migrate_to_anchors() -> void:
	var legacy := ShikakuLogic.new()
	legacy.init_from_save({
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
	assert_eq(legacy.anchors.size(), 2)
	var a00: Dictionary = legacy.anchors.get(Vector2i(0, 0), {})
	assert_eq(int(a00.get("area", 0)), 2)
	assert_eq(int(a00.get("shape", -1)), ShikakuLogic.SHAPE_ABSENT)
	assert_eq(legacy.mode, ShikakuLogic.RULE_SET_STANDARD)


func test_numbers_property_returns_area_only_anchors() -> void:
	var nums: Dictionary = logic.numbers
	assert_true(nums.has(Vector2i(0, 0)))
	assert_eq(nums[Vector2i(0, 0)], 2)


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
		"anchors": {
			"0,0": {"area": 2, "shape": ShikakuLogic.SHAPE_ABSENT},
			"1,0": {"area": 2, "shape": ShikakuLogic.SHAPE_ABSENT},
			"2,0": {"area": 2, "shape": ShikakuLogic.SHAPE_ABSENT},
		},
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


# ---------------------------------------------------------------------------
# Fix 5 — hints succeed even when candidates are blocked by wrong placements
# ---------------------------------------------------------------------------

func test_hint_succeeds_when_first_candidate_blocked() -> void:
	# 4x1 grid, two shape-ANY anchors, solution = two 2x1 rects.
	# A wrong 1x1 rect at (0,0) blocks the first solution rect (0,0,2,1).
	# The new hint code tries all candidates in order, so it must find
	# and place the second solution rect (2,0,2,1) instead of silently failing.
	var l := ShikakuLogic.new()
	l.init_from_save({
		"width": 4,
		"height": 1,
		"anchors": {
			"0,0": {"area": 0, "shape": ShikakuLogic.SHAPE_ANY},
			"2,0": {"area": 0, "shape": ShikakuLogic.SHAPE_ANY},
		},
		"solution": [
			{"x": 0, "y": 0, "w": 2, "h": 1},
			{"x": 2, "y": 0, "w": 2, "h": 1},
		],
		"placed_rects": [],
		"random_seed": 1234,
	})
	# Place a wrong 1x1 rect at (0,0): locally valid (area-unconstrained, SHAPE_ANY),
	# but not in the solution. This covers cell (0,0), blocking solution rect (0,0,2,1).
	var wrong_result: ShikakuLogic.PlaceRectResult = l.place_rectangle(0, 0, 1, 1)
	assert_true(wrong_result.valid, "Wrong 1x1 placement must be locally valid for ANY anchor")
	# Now hint: candidates = [(0,0,2,1), (2,0,2,1)].
	# (0,0,2,1) is blocked by the wrong placement; (2,0,2,1) is free.
	# The hint must find and place (2,0,2,1).
	var hint_result: ShikakuLogic.HintResult = l.use_hint()
	assert_false(hint_result.rect.is_empty(), "Hint must succeed and not silently fail when first candidate is blocked")
	assert_eq(l.hints_used, 1, "hints_used must be incremented on successful hint")


# ---------------------------------------------------------------------------
# Fix 6 — contradiction detection: get_wrong_placed_rects
# ---------------------------------------------------------------------------

func test_get_wrong_placed_rects_empty_when_no_placements() -> void:
	var wrong := logic.get_wrong_placed_rects()
	assert_true(wrong.is_empty(), "No wrong rects when board is empty")


func test_get_wrong_placed_rects_empty_when_correct() -> void:
	logic.place_rectangle(0, 0, 2, 1)
	var wrong := logic.get_wrong_placed_rects()
	assert_true(wrong.is_empty(), "Correct placement must not appear in wrong rects")


func test_get_wrong_placed_rects_empty_when_solution_is_empty() -> void:
	# Logic without a stored solution — cannot determine wrong rects.
	var l := ShikakuLogic.new()
	l.init_from_save({
		"width": 2, "height": 2,
		"anchors": {"0,0": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}},
		"solution": [],
		"placed_rects": [],
		"random_seed": 1234,
	})
	l.placed_rects.append(Rect2i(0, 0, 2, 2))
	var wrong := l.get_wrong_placed_rects()
	assert_true(wrong.is_empty(), "No wrong rects when solution is empty")


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


# ---------------------------------------------------------------------------
# Fix 1 — init_from_generated populates fields without running the generator
# ---------------------------------------------------------------------------

func test_init_from_generated_sets_correct_fields() -> void:
	var data := ShikakuGenerator.generate(5, 5, 42, ShikakuLogic.RULE_SET_STANDARD)
	assert_false(data.is_empty(), "generate must succeed for seed=42 (prerequisite)")
	var l := ShikakuLogic.new()
	l.init_from_generated(data, 42, ShikakuLogic.RULE_SET_STANDARD)
	assert_eq(l.grid_width, 5, "init_from_generated must set grid_width")
	assert_eq(l.grid_height, 5, "init_from_generated must set grid_height")
	assert_eq(l.mode, ShikakuLogic.RULE_SET_STANDARD, "init_from_generated must set mode")
	assert_eq(l.random_seed, 42, "init_from_generated must store the seed")
	assert_true(l.anchors.size() > 0, "init_from_generated must populate anchors")
	assert_true(l.solution.size() > 0, "init_from_generated must populate solution")
	assert_true(l.placed_rects.is_empty(), "init_from_generated must start with no placed rects")
	assert_false(l.is_completed, "init_from_generated must start as not completed")
	assert_eq(l.hints_used, 0, "init_from_generated must start with zero hints used")


# ---------------------------------------------------------------------------
# Fix 4 — hint removes blocking wrong placements and reports them
# ---------------------------------------------------------------------------

func test_hint_removed_rects_populated_when_wrong_placements_cleared() -> void:
	# 4×1 grid, two SHAPE_ANY anchors, solution = [(0,0,2,1), (2,0,2,1)].
	# Block BOTH solution rects with locally-valid 1×1 wrong placements.
	# use_hint must clear the blocking placement for whichever candidate it tries
	# first, and report it in removed_rects.
	var l := ShikakuLogic.new()
	l.init_from_save({
		"width": 4,
		"height": 1,
		"anchors": {
			"0,0": {"area": 0, "shape": ShikakuLogic.SHAPE_ANY},
			"2,0": {"area": 0, "shape": ShikakuLogic.SHAPE_ANY},
		},
		"solution": [
			{"x": 0, "y": 0, "w": 2, "h": 1},
			{"x": 2, "y": 0, "w": 2, "h": 1},
		],
		"placed_rects": [],
		"random_seed": 1234,
	})
	# Place two wrong 1×1 rects — each blocks one solution rect.
	var w1: ShikakuLogic.PlaceRectResult = l.place_rectangle(0, 0, 1, 1)
	assert_true(w1.valid, "Wrong 1×1 at (0,0) must be locally valid for SHAPE_ANY anchor")
	var w2: ShikakuLogic.PlaceRectResult = l.place_rectangle(2, 0, 1, 1)
	assert_true(w2.valid, "Wrong 1×1 at (2,0) must be locally valid for SHAPE_ANY anchor")
	# Hint must clear whichever blocking rect overlaps the chosen solution rect
	# and return a non-empty hint with at least one removed rect.
	var hint_result: ShikakuLogic.HintResult = l.use_hint()
	assert_false(hint_result.rect.is_empty(),
		"Hint must succeed even when all solution rects are initially blocked")
	assert_true(hint_result.removed_rects.size() > 0,
		"Hint must populate removed_rects when it had to clear a wrong placement")


# ---------------------------------------------------------------------------
# Fix 1 (current batch) — hint replay: removed_rects identifies blockers that
#   must be recorded as rectangle_removed events before the hint placement
# ---------------------------------------------------------------------------

func test_hint_removed_rects_contains_each_cleared_blocker() -> void:
	# Verifies that each wrong placement cleared by use_hint is reflected in
	# result.removed_rects with the correct rect dictionary, so the game screen
	# can record a rectangle_removed event for each one before recording the
	# placement.  A replay that only records the placement (not the removals)
	# would diverge; this test guards the logic-level contract that feeds those
	# recorder calls.
	var l := ShikakuLogic.new()
	l.init_from_save({
		"width": 4,
		"height": 1,
		"anchors": {
			"0,0": {"area": 0, "shape": ShikakuLogic.SHAPE_ANY},
			"2,0": {"area": 0, "shape": ShikakuLogic.SHAPE_ANY},
		},
		"solution": [
			{"x": 0, "y": 0, "w": 2, "h": 1},
			{"x": 2, "y": 0, "w": 2, "h": 1},
		],
		"placed_rects": [],
		"random_seed": 42,
	})
	# Place a wrong 1×1 rect at (0,0) that blocks solution rect (0,0,2,1).
	var wrong: ShikakuLogic.PlaceRectResult = l.place_rectangle(0, 0, 1, 1)
	assert_true(wrong.valid, "Wrong placement must be valid for SHAPE_ANY anchor")
	var hint_result: ShikakuLogic.HintResult = l.use_hint()
	assert_false(hint_result.rect.is_empty(), "Hint must succeed")
	# If the hint cleared the blocker at (0,0,1,1), removed_rects must carry it.
	# The game screen uses removed_rects to record rectangle_removed events.
	for removed in hint_result.removed_rects:
		assert_true(removed.has("x") and removed.has("y") and removed.has("w") and removed.has("h"),
			"Each removed_rect must be a dict with x/y/w/h for replay recording")
