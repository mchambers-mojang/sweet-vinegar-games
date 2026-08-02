extends GutTest

## Tests for Shikaku Shapes Mode — generation, validation, clue types,
## legacy migration, anchor invariants, and solver coverage.


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build an anchors dict from a simple list of (pos, area, shape) triples.
func _make_anchors(entries: Array) -> Dictionary:
	var result: Dictionary = {}
	for e in entries:
		result[e[0]] = {"area": e[1], "shape": e[2]}
	return result


# ---------------------------------------------------------------------------
# Anchor invariants
# ---------------------------------------------------------------------------

func test_anchor_area_only_is_valid() -> void:
	var anchors := _make_anchors([
		[Vector2i(0, 0), 4, ShikakuLogic.SHAPE_ABSENT],
		[Vector2i(2, 0), 4, ShikakuLogic.SHAPE_ABSENT],
	])
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(2, 0, 2, 2)]
	assert_true(ShikakuSolver.validate_anchors(4, 2, anchors, rects))


func test_anchor_shape_only_square_is_valid() -> void:
	# SHAPE_SQUARE anchor in 2x2 rect: no area constraint, shape=square passes.
	var anchors := _make_anchors([
		[Vector2i(0, 0), 0, ShikakuLogic.SHAPE_SQUARE],
		[Vector2i(2, 0), 4, ShikakuLogic.SHAPE_ABSENT],
	])
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(2, 0, 2, 2)]
	assert_true(ShikakuSolver.validate_anchors(4, 2, anchors, rects))


func test_anchor_combined_area_and_shape_is_valid() -> void:
	# Area=4 + SHAPE_SQUARE: 2x2 rect satisfies both.
	var anchors := _make_anchors([
		[Vector2i(0, 0), 4, ShikakuLogic.SHAPE_SQUARE],
		[Vector2i(2, 0), 4, ShikakuLogic.SHAPE_ABSENT],
	])
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(2, 0, 2, 2)]
	assert_true(ShikakuSolver.validate_anchors(4, 2, anchors, rects))


func test_anchor_combined_area_shape_wrong_area_fails() -> void:
	# Area=6 + SHAPE_SQUARE: 2x2 area is 4, not 6 → fails.
	var anchors := _make_anchors([
		[Vector2i(0, 0), 6, ShikakuLogic.SHAPE_SQUARE],
		[Vector2i(2, 0), 2, ShikakuLogic.SHAPE_ABSENT],
	])
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(2, 0, 2, 1)]
	assert_false(ShikakuSolver.validate_anchors(4, 2, anchors, rects))


func test_anchor_combined_area_correct_shape_wrong_fails() -> void:
	# Area=4 + SHAPE_TALL: 2x2 is square, not tall → fails.
	var anchors := _make_anchors([
		[Vector2i(0, 0), 4, ShikakuLogic.SHAPE_TALL],
		[Vector2i(2, 0), 4, ShikakuLogic.SHAPE_ABSENT],
	])
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(2, 0, 2, 2)]
	assert_false(ShikakuSolver.validate_anchors(4, 2, anchors, rects))


# ---------------------------------------------------------------------------
# All six supported sizes generate valid Shapes puzzles
# ---------------------------------------------------------------------------

func test_shapes_mode_generates_5x5() -> void:
	var gen := ShikakuGenerator.generate(5, 5, 100, ShikakuLogic.RULE_SET_SHAPES)
	var anchors: Dictionary = gen.get("anchors", {})
	var solution: Array[Rect2i] = gen.get("solution", [])
	assert_true(anchors.size() > 0, "5x5 Shapes should have anchors")
	assert_true(ShikakuSolver.validate_anchors(5, 5, anchors, solution),
		"5x5 Shapes solution should validate")


func test_shapes_mode_generates_7x7() -> void:
	var gen := ShikakuGenerator.generate(7, 7, 101, ShikakuLogic.RULE_SET_SHAPES)
	var anchors: Dictionary = gen.get("anchors", {})
	var solution: Array[Rect2i] = gen.get("solution", [])
	assert_true(ShikakuSolver.validate_anchors(7, 7, anchors, solution))


func test_shapes_mode_generates_8x8() -> void:
	var t0 := Time.get_ticks_msec()
	var gen := ShikakuGenerator.generate(8, 8, 102, ShikakuLogic.RULE_SET_SHAPES)
	var elapsed_ms := Time.get_ticks_msec() - t0
	var anchors: Dictionary = gen.get("anchors", {})
	var solution: Array[Rect2i] = gen.get("solution", [])
	assert_true(anchors.size() > 0, "8x8 Shapes should have anchors")
	assert_lt(elapsed_ms, 3000, "8x8 Shapes generation must complete within 3 seconds (took %d ms)" % elapsed_ms)
	assert_true(ShikakuSolver.validate_anchors(8, 8, anchors, solution),
		"8x8 Shapes solution should validate")
	assert_eq(ShikakuSolver.count_solutions(8, 8, anchors, 2), 1,
		"8x8 Shapes puzzle must have exactly one solution")
	assert_true(ShikakuSolver.is_human_solvable(8, 8, anchors),
		"8x8 Shapes puzzle must be human-solvable")


func test_shapes_mode_generates_10x10() -> void:
	var gen := ShikakuGenerator.generate(10, 10, 103, ShikakuLogic.RULE_SET_SHAPES)
	var anchors: Dictionary = gen.get("anchors", {})
	var solution: Array[Rect2i] = gen.get("solution", [])
	assert_true(ShikakuSolver.validate_anchors(10, 10, anchors, solution))


func test_shapes_mode_generates_12x12() -> void:
	var gen := ShikakuGenerator.generate(12, 12, 104, ShikakuLogic.RULE_SET_SHAPES)
	var anchors: Dictionary = gen.get("anchors", {})
	var solution: Array[Rect2i] = gen.get("solution", [])
	assert_true(ShikakuSolver.validate_anchors(12, 12, anchors, solution))


func test_shapes_mode_generates_15x15() -> void:
	var t0 := Time.get_ticks_msec()
	var gen := ShikakuGenerator.generate(15, 15, 105, ShikakuLogic.RULE_SET_SHAPES)
	var elapsed_ms := Time.get_ticks_msec() - t0
	var anchors: Dictionary = gen.get("anchors", {})
	var solution: Array[Rect2i] = gen.get("solution", [])
	assert_true(anchors.size() > 0, "15x15 Shapes should have anchors")
	assert_lt(elapsed_ms, 3000, "15x15 Shapes generation must complete within 3 seconds (took %d ms)" % elapsed_ms)
	assert_true(ShikakuSolver.validate_anchors(15, 15, anchors, solution),
		"15x15 Shapes solution should validate")
	assert_eq(ShikakuSolver.count_solutions(15, 15, anchors, 2), 1,
		"15x15 Shapes puzzle must have exactly one solution (exhaustive check)")
	assert_true(ShikakuSolver.is_human_solvable(15, 15, anchors),
		"15x15 Shapes puzzle must be human-solvable (exhaustive check)")


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------

func test_shapes_mode_is_deterministic() -> void:
	var gen1 := ShikakuGenerator.generate(7, 7, 999, ShikakuLogic.RULE_SET_SHAPES)
	var gen2 := ShikakuGenerator.generate(7, 7, 999, ShikakuLogic.RULE_SET_SHAPES)
	var a1: Dictionary = gen1.get("anchors", {})
	var a2: Dictionary = gen2.get("anchors", {})
	assert_eq(a1.size(), a2.size(), "Anchor count must be deterministic")
	for pos in a1.keys():
		assert_true(a2.has(pos), "Same anchor positions for same seed")
		assert_eq(a1[pos], a2[pos], "Same anchor clue for same seed")


func test_standard_mode_is_deterministic() -> void:
	var gen1 := ShikakuGenerator.generate(5, 5, 42, ShikakuLogic.RULE_SET_STANDARD)
	var gen2 := ShikakuGenerator.generate(5, 5, 42, ShikakuLogic.RULE_SET_STANDARD)
	assert_eq(gen1["anchors"], gen2["anchors"])


# ---------------------------------------------------------------------------
# Every anchor has at least one clue component
# ---------------------------------------------------------------------------

func test_shapes_anchors_all_constrained() -> void:
	for seed in [1, 2, 3, 10, 42]:
		var gen := ShikakuGenerator.generate(7, 7, seed, ShikakuLogic.RULE_SET_SHAPES)
		var anchors: Dictionary = gen.get("anchors", {})
		for pos in anchors.keys():
			var a: Dictionary = anchors[pos]
			var area: int = int(a.get("area", 0))
			var shape: int = int(a.get("shape", ShikakuLogic.SHAPE_ABSENT))
			assert_true(
				area > 0 or shape != ShikakuLogic.SHAPE_ABSENT,
				"Every anchor must have area > 0 OR shape != ABSENT at %s" % str(pos)
			)


# ---------------------------------------------------------------------------
# Unique solution — count_solutions returns exactly 1
# ---------------------------------------------------------------------------

func test_shapes_puzzle_has_unique_solution_small() -> void:
	# Small puzzle: uniqueness is fast to verify.
	for seed in [1, 2, 5]:
		var gen := ShikakuGenerator.generate(5, 5, seed, ShikakuLogic.RULE_SET_SHAPES)
		var anchors: Dictionary = gen.get("anchors", {})
		var n := ShikakuSolver.count_solutions(5, 5, anchors, 2)
		assert_eq(n, 1, "5x5 Shapes seed=%d should have exactly 1 solution" % seed)


func test_standard_puzzle_has_unique_solution_small() -> void:
	for seed in [1, 2, 5]:
		var gen := ShikakuGenerator.generate(5, 5, seed, ShikakuLogic.RULE_SET_STANDARD)
		var anchors: Dictionary = gen.get("anchors", {})
		var n := ShikakuSolver.count_solutions(5, 5, anchors, 2)
		assert_eq(n, 1, "5x5 Standard seed=%d should have exactly 1 solution" % seed)


# ---------------------------------------------------------------------------
# Standard mode unaffected (regression)
# ---------------------------------------------------------------------------

func test_standard_mode_area_only_anchors() -> void:
	var gen := ShikakuGenerator.generate(5, 5, 42, ShikakuLogic.RULE_SET_STANDARD)
	var anchors: Dictionary = gen.get("anchors", {})
	for pos in anchors.keys():
		var a: Dictionary = anchors[pos]
		assert_true(int(a.get("area", 0)) > 0, "Standard anchors always have area")
		assert_eq(int(a.get("shape", -1)), ShikakuLogic.SHAPE_ABSENT,
			"Standard anchors have shape=ABSENT")


# ---------------------------------------------------------------------------
# ShikakuLogic — Shapes mode init and solve
# ---------------------------------------------------------------------------

func test_logic_shapes_mode_init() -> void:
	var logic := ShikakuLogic.new()
	logic.init_new_game(5, 5, 200, ShikakuLogic.RULE_SET_SHAPES)
	assert_eq(logic.mode, ShikakuLogic.RULE_SET_SHAPES)
	assert_true(logic.anchors.size() > 0)
	assert_true(logic.solution.size() > 0)


func test_logic_shapes_mode_place_valid_rect() -> void:
	# Create a minimal shapes puzzle manually.
	var logic := ShikakuLogic.new()
	logic.init_from_save({
		"width": 2,
		"height": 2,
		"mode": ShikakuLogic.RULE_SET_SHAPES,
		"anchors": {
			"0,0": {"area": 0, "shape": ShikakuLogic.SHAPE_WIDE},
			"0,1": {"area": 0, "shape": ShikakuLogic.SHAPE_WIDE},
		},
		"solution": [
			{"x": 0, "y": 0, "w": 2, "h": 1},
			{"x": 0, "y": 1, "w": 2, "h": 1},
		],
		"placed_rects": [],
		"random_seed": 1234,
	})
	# 2x1 rect is WIDE (w>h): should be valid.
	var result: ShikakuLogic.PlaceRectResult = logic.place_rectangle(0, 0, 2, 1)
	assert_true(result.valid, "WIDE 2x1 should be valid for WIDE anchor")


func test_logic_shapes_mode_reject_wrong_shape() -> void:
	var logic := ShikakuLogic.new()
	logic.init_from_save({
		"width": 2,
		"height": 2,
		"mode": ShikakuLogic.RULE_SET_SHAPES,
		"anchors": {
			"0,0": {"area": 0, "shape": ShikakuLogic.SHAPE_TALL},
			"1,0": {"area": 0, "shape": ShikakuLogic.SHAPE_TALL},
		},
		"solution": [
			{"x": 0, "y": 0, "w": 1, "h": 2},
			{"x": 1, "y": 0, "w": 1, "h": 2},
		],
		"placed_rects": [],
		"random_seed": 1234,
	})
	# 2x1 rect is WIDE: must fail for TALL anchor.
	var result: ShikakuLogic.PlaceRectResult = logic.place_rectangle(0, 0, 2, 1)
	assert_false(result.valid, "WIDE 2x1 should be rejected for TALL anchor")


func test_logic_shapes_mode_serialize_deserialize() -> void:
	var logic := ShikakuLogic.new()
	logic.init_new_game(5, 5, 300, ShikakuLogic.RULE_SET_SHAPES)
	var data := logic.serialize()
	assert_eq(int(data.get("mode", -1)), ShikakuLogic.RULE_SET_SHAPES)
	assert_true(data.has("anchors"))

	var restored := ShikakuLogic.new()
	restored.init_from_save(data)
	assert_eq(restored.mode, ShikakuLogic.RULE_SET_SHAPES)
	assert_eq(restored.anchors, logic.anchors)


# ---------------------------------------------------------------------------
# Legacy migration
# ---------------------------------------------------------------------------

func test_legacy_save_numbers_migrates_to_standard() -> void:
	var logic := ShikakuLogic.new()
	logic.init_from_save({
		"width": 5,
		"height": 5,
		"numbers": {"0,0": 4, "3,2": 6, "1,4": 5},
		"solution": [],
		"placed_rects": [],
		"random_seed": 0,
	})
	# All anchors should be area-only with SHAPE_ABSENT
	assert_eq(logic.mode, ShikakuLogic.RULE_SET_STANDARD)
	assert_eq(logic.anchors.size(), 3)
	for pos in logic.anchors.keys():
		var a: Dictionary = logic.anchors[pos]
		assert_eq(int(a.get("shape", -1)), ShikakuLogic.SHAPE_ABSENT)
		assert_true(int(a.get("area", 0)) > 0)


# ---------------------------------------------------------------------------
# Explicit Any round-trip
# ---------------------------------------------------------------------------

func test_explicit_any_shape_round_trips() -> void:
	var logic := ShikakuLogic.new()
	logic.init_from_save({
		"width": 2,
		"height": 2,
		"mode": ShikakuLogic.RULE_SET_SHAPES,
		"anchors": {
			"0,0": {"area": 2, "shape": ShikakuLogic.SHAPE_ANY},
			"0,1": {"area": 2, "shape": ShikakuLogic.SHAPE_ABSENT},
		},
		"solution": [{"x": 0, "y": 0, "w": 2, "h": 1}, {"x": 0, "y": 1, "w": 2, "h": 1}],
		"placed_rects": [],
		"random_seed": 1234,
	})
	var data := logic.serialize()
	var restored := ShikakuLogic.new()
	restored.init_from_save(data)
	var a00: Dictionary = restored.anchors.get(Vector2i(0, 0), {})
	assert_eq(int(a00.get("shape", -1)), ShikakuLogic.SHAPE_ANY,
		"SHAPE_ANY must survive round-trip")


# ---------------------------------------------------------------------------
# SHAPE_ICONS metadata
# ---------------------------------------------------------------------------

func test_shape_icons_are_distinct() -> void:
	var icons: Array[String] = []
	for shape in [ShikakuLogic.SHAPE_SQUARE, ShikakuLogic.SHAPE_TALL, ShikakuLogic.SHAPE_WIDE, ShikakuLogic.SHAPE_ANY]:
		var icon: String = ShikakuLogic.SHAPE_ICONS.get(shape, "")
		assert_false(icon.is_empty(), "Shape icon must not be empty for shape %d" % shape)
		assert_false(icons.has(icon), "Shape icon must be unique: '%s'" % icon)
		icons.append(icon)


func test_shape_absent_has_no_icon() -> void:
	var icon: String = ShikakuLogic.SHAPE_ICONS.get(ShikakuLogic.SHAPE_ABSENT, "MISSING")
	assert_eq(icon, "", "SHAPE_ABSENT icon should be empty string")


# ---------------------------------------------------------------------------
# SHAPE_NAMES — accessibility (Fix 5)
# ---------------------------------------------------------------------------

func test_shape_names_are_non_empty_for_constrained_shapes() -> void:
	for shape in [ShikakuLogic.SHAPE_SQUARE, ShikakuLogic.SHAPE_TALL, ShikakuLogic.SHAPE_WIDE, ShikakuLogic.SHAPE_ANY]:
		var name: String = ShikakuLogic.SHAPE_NAMES.get(shape, "")
		assert_false(name.is_empty(), "SHAPE_NAMES must have non-empty text for shape %d" % shape)


func test_shape_names_are_distinct() -> void:
	var names: Array[String] = []
	for shape in [ShikakuLogic.SHAPE_SQUARE, ShikakuLogic.SHAPE_TALL, ShikakuLogic.SHAPE_WIDE, ShikakuLogic.SHAPE_ANY]:
		var name: String = ShikakuLogic.SHAPE_NAMES.get(shape, "")
		assert_false(names.has(name), "SHAPE_NAMES must be unique: '%s'" % name)
		names.append(name)


func test_shape_absent_has_no_name() -> void:
	var name: String = ShikakuLogic.SHAPE_NAMES.get(ShikakuLogic.SHAPE_ABSENT, "MISSING")
	assert_eq(name, "", "SHAPE_ABSENT name should be empty string")


# ---------------------------------------------------------------------------
# Uniqueness — initial full-clue puzzle must be unique (Fix 1)
# ---------------------------------------------------------------------------

func test_shapes_mode_initial_clues_are_unique() -> void:
	# All generated Shapes puzzles must have a unique solution even before
	# any minimization — this verifies the unsound-uniqueness-proof fix.
	for seed in [1, 2, 3, 10, 42]:
		var gen := ShikakuGenerator.generate(7, 7, seed, ShikakuLogic.RULE_SET_SHAPES)
		var anchors: Dictionary = gen.get("anchors", {})
		assert_true(anchors.size() > 0, "7x7 Shapes seed=%d must produce anchors" % seed)
		var n := ShikakuSolver.count_solutions(7, 7, anchors, 2)
		assert_eq(n, 1, "7x7 Shapes seed=%d must have exactly 1 solution after generation" % seed)


# ---------------------------------------------------------------------------
# Human-solvability (Fix 2)
# ---------------------------------------------------------------------------

func test_shapes_mode_is_human_solvable_small() -> void:
	# Small grids should yield human-solvable Shapes puzzles.
	var found_human_solvable := false
	for seed in range(1, 10):
		var gen := ShikakuGenerator.generate(5, 5, seed, ShikakuLogic.RULE_SET_SHAPES)
		var anchors: Dictionary = gen.get("anchors", {})
		if ShikakuSolver.is_human_solvable(5, 5, anchors):
			found_human_solvable = true
			break
	assert_true(found_human_solvable, "At least one 5x5 Shapes puzzle across seeds 1-9 must be human-solvable")


func test_is_human_solvable_forced_area_anchor() -> void:
	# A 2x2 grid with two area-only anchors whose only valid placement is unique.
	var anchors := _make_anchors([
		[Vector2i(0, 0), 2, ShikakuLogic.SHAPE_ABSENT],
		[Vector2i(0, 1), 2, ShikakuLogic.SHAPE_ABSENT],
	])
	# Only valid partition: (0,0,2,1) and (0,1,2,1) — both forced.
	assert_true(ShikakuSolver.is_human_solvable(2, 2, anchors),
		"Area-only anchors with unique placement must be human-solvable")


func test_is_human_solvable_false_when_ambiguous() -> void:
	# 2x2 grid, single SHAPE_ANY anchor with no area: could be 1×1, 1×2, 2×1, 2×2 etc.
	# Multiple options → not forced → not human-solvable.
	var anchors := _make_anchors([
		[Vector2i(0, 0), 0, ShikakuLogic.SHAPE_ANY],
		[Vector2i(1, 1), 0, ShikakuLogic.SHAPE_ANY],
	])
	assert_false(ShikakuSolver.is_human_solvable(2, 2, anchors),
		"Ambiguous shape-only anchors must not be human-solvable")


# ---------------------------------------------------------------------------
# Cancellation (Fix 3)
# ---------------------------------------------------------------------------

func test_count_solutions_returns_minus_one_when_cancelled() -> void:
	# Build a puzzle that would take non-trivial time to solve, then cancel immediately.
	var gen := ShikakuGenerator.generate(5, 5, 42, ShikakuLogic.RULE_SET_SHAPES)
	var anchors: Dictionary = gen.get("anchors", {})
	var already_cancelled := true
	var cancel_check := func() -> bool: return already_cancelled
	var result := ShikakuSolver.count_solutions(5, 5, anchors, 2, cancel_check)
	assert_eq(result, -1, "count_solutions must return -1 when cancel_check fires immediately")


func test_count_solutions_normal_without_cancellation() -> void:
	# Without a cancel_check, count_solutions works as before.
	var gen := ShikakuGenerator.generate(5, 5, 42, ShikakuLogic.RULE_SET_SHAPES)
	var anchors: Dictionary = gen.get("anchors", {})
	var n := ShikakuSolver.count_solutions(5, 5, anchors, 2)
	assert_eq(n, 1, "count_solutions without cancellation must return 1 for a valid puzzle")


# ---------------------------------------------------------------------------
# Unconstrained area enumeration is exhaustive — no static area cap (Fix 1b)
# ---------------------------------------------------------------------------

func test_shape_only_anchor_can_match_area_above_8() -> void:
	# A 3x3 SQUARE rect has area 9, which exceeds the old MAX_UNCONSTRAINED_AREA=8.
	# The solver must still find and validate it.
	var anchors := _make_anchors([
		[Vector2i(1, 1), 0, ShikakuLogic.SHAPE_SQUARE],
	])
	var rects: Array[Rect2i] = [Rect2i(0, 0, 3, 3)]
	assert_true(ShikakuSolver.validate_anchors(3, 3, anchors, rects),
		"validate_anchors must accept 3x3 SQUARE rect (area 9) for a shape-only anchor")


func test_solver_finds_unique_solution_with_large_unconstrained_shape() -> void:
	# 3x3 grid with a single SQUARE shape-only anchor: unique solution is 3×3 rect.
	var anchors := _make_anchors([
		[Vector2i(0, 0), 0, ShikakuLogic.SHAPE_SQUARE],
	])
	var n := ShikakuSolver.count_solutions(3, 3, anchors, 2)
	assert_eq(n, 1, "3x3 grid with single SQUARE anchor must have exactly 1 solution")


# ---------------------------------------------------------------------------
# Fix 1 — human-solvability guaranteed: generate never returns a non-human-
# solvable puzzle
# ---------------------------------------------------------------------------

func test_shapes_mode_generate_always_human_solvable_small_seeds() -> void:
	# Every generated 5x5 Shapes puzzle must be human-solvable.
	for seed in range(1, 8):
		var gen := ShikakuGenerator.generate(5, 5, seed, ShikakuLogic.RULE_SET_SHAPES)
		var anchors: Dictionary = gen.get("anchors", {})
		if anchors.is_empty():
			# Generation may fail on some seeds — skip those.
			continue
		assert_true(
			ShikakuSolver.is_human_solvable(5, 5, anchors),
			"5x5 Shapes seed=%d must be human-solvable" % seed
		)


func test_shapes_mode_generate_never_returns_non_human_solvable() -> void:
	# A puzzle returned by generate() for Shapes mode must either be empty
	# (generation failed) or human-solvable. It must never be a non-empty,
	# non-human-solvable result (the old fallback behaviour).
	for seed in [10, 11, 42]:
		var gen := ShikakuGenerator.generate(7, 7, seed, ShikakuLogic.RULE_SET_SHAPES)
		var anchors: Dictionary = gen.get("anchors", {})
		if anchors.is_empty():
			continue
		assert_true(
			ShikakuSolver.is_human_solvable(7, 7, anchors),
			"7x7 Shapes seed=%d returned by generate() must be human-solvable" % seed
		)


# ---------------------------------------------------------------------------
# Fix 2 — cancellation wired end-to-end
# ---------------------------------------------------------------------------

func test_is_human_solvable_returns_false_when_cancelled() -> void:
	var gen := ShikakuGenerator.generate(5, 5, 42, ShikakuLogic.RULE_SET_SHAPES)
	var anchors: Dictionary = gen.get("anchors", {})
	var cancel_check := func() -> bool: return true  # always cancel
	# Conservative: returns false when cancelled.
	var result := ShikakuSolver.is_human_solvable(5, 5, anchors, cancel_check)
	assert_false(result, "is_human_solvable must return false when cancelled")


func test_generate_shapes_returns_empty_when_cancelled() -> void:
	var cancel_check := func() -> bool: return true  # always cancel
	var gen := ShikakuGenerator.generate(5, 5, 42, ShikakuLogic.RULE_SET_SHAPES, cancel_check)
	assert_true(gen.is_empty(), "Shapes generate must return {} when cancelled immediately")


func test_generate_standard_returns_empty_when_cancelled() -> void:
	var cancel_check := func() -> bool: return true  # always cancel
	var gen := ShikakuGenerator.generate(5, 5, 42, ShikakuLogic.RULE_SET_STANDARD, cancel_check)
	assert_true(gen.is_empty(), "Standard generate must return {} when cancelled immediately")


func test_enumerate_rects_returns_empty_when_cancelled() -> void:
	# Unconstrained anchor: the outer w-loop in _enumerate_rects_for_anchor
	# should abort early when cancel fires.
	var covered := PackedByteArray()
	covered.resize(5 * 5)
	covered.fill(0)
	var anchor := {"area": 0, "shape": ShikakuLogic.SHAPE_ANY}
	var cancel_check := func() -> bool: return true  # always cancel
	var rects := ShikakuSolver._enumerate_rects_for_anchor(Vector2i(2, 2), anchor, 5, 5, covered, cancel_check)
	assert_true(rects.is_empty(), "_enumerate_rects_for_anchor must return [] when cancelled")


# ---------------------------------------------------------------------------
# Fix 7 — Standard generation uniqueness guaranteed
# ---------------------------------------------------------------------------

func test_standard_generation_produces_unique_solution_multiple_seeds() -> void:
	for seed in [1, 7, 13, 99]:
		var gen := ShikakuGenerator.generate(5, 5, seed, ShikakuLogic.RULE_SET_STANDARD)
		var anchors: Dictionary = gen.get("anchors", {})
		if anchors.is_empty():
			# Extremely unlikely for Standard mode but skip if generation failed.
			continue
		var n := ShikakuSolver.count_solutions(5, 5, anchors, 2)
		assert_eq(n, 1, "Standard 5x5 seed=%d must have exactly 1 solution after uniqueness fix" % seed)


func test_standard_generation_not_empty_for_common_seeds() -> void:
	# Standard mode should reliably produce puzzles within MAX_STANDARD_ATTEMPTS.
	for seed in [1, 2, 3, 42, 100]:
		var gen := ShikakuGenerator.generate(5, 5, seed, ShikakuLogic.RULE_SET_STANDARD)
		assert_false(gen.is_empty(), "Standard generate must succeed for seed=%d" % seed)


# ---------------------------------------------------------------------------
# Fix 5 — Standard generation verifies human-solvability
# ---------------------------------------------------------------------------

func test_standard_generated_puzzles_are_human_solvable() -> void:
	# Before this fix the generator only checked uniqueness; now it also checks
	# is_human_solvable() before returning.
	for seed in [1, 7, 42]:
		var gen := ShikakuGenerator.generate(5, 5, seed, ShikakuLogic.RULE_SET_STANDARD)
		if gen.is_empty():
			continue
		var anchors: Dictionary = gen.get("anchors", {})
		var result := ShikakuSolver.is_human_solvable(5, 5, anchors)
		assert_true(result,
			"Standard 5×5 seed=%d must be human-solvable after Fix 5" % seed)


# ---------------------------------------------------------------------------
# Fix 6 — Solver propagation: cell-ownership eliminates ambiguous candidates
# ---------------------------------------------------------------------------

func test_cell_ownership_resolves_ambiguous_candidates() -> void:
	# 3×2 grid with two unconstrained (SHAPE_ANY, area=0) anchors.
	#
	# Neither anchor is forced by Phase 1 alone:
	#   (0,0) valid candidates: {1×1@(0,0), 1×2@(0,0)}  (2 options)
	#   (1,0) valid candidates: {1×1@(1,0), 2×1@(1,0), 1×2@(1,0), 2×2@(1,0)} (4 options)
	#
	# Phase 2 resolves it via cell-ownership:
	#   Cell (0,1) can only be reached by anchor (0,0) via 1×2@(0,0) — uniquely owned.
	#   Restricting (0,0) to candidates containing (0,1) yields {1×2@(0,0)} → placed.
	#   Cell (2,1) can only be reached by anchor (1,0) via 2×2@(1,0) → placed.
	#
	# The unique solution is (0,0,1,2) + (1,0,2,2).
	# The old Phase-1-only solver returned false for this puzzle.
	var anchors := {
		Vector2i(0, 0): {"area": 0, "shape": ShikakuLogic.SHAPE_ANY},
		Vector2i(1, 0): {"area": 0, "shape": ShikakuLogic.SHAPE_ANY},
	}
	assert_true(ShikakuSolver.is_human_solvable(3, 2, anchors),
		"Cell-ownership pass must identify this puzzle as human-solvable")


# ---------------------------------------------------------------------------
# Fix 3 (current batch) — cell-ownership deduplication and restriction
#   propagation
# ---------------------------------------------------------------------------

func test_cell_ownership_deduplication_does_not_inflate_owner_count() -> void:
	# 4×2 grid, A at (0,0) SHAPE_ANY, B at (2,0) SHAPE_ANY.
	# A has two valid candidates: 1×2@(0,0) and 2×2@(0,0), both covering cell
	# (0,1).  Before deduplication, the old code added A's index twice to
	# cell_owners[(0,1)] → size 2 → restriction skipped. The solver still
	# resolved the puzzle via other cells, but the deduplication ensures the
	# restriction is correctly recorded and applied.
	# The unique solution is 2×2@(0,0) + 2×2@(2,0).
	var anchors := {
		Vector2i(0, 0): {"area": 0, "shape": ShikakuLogic.SHAPE_ANY},
		Vector2i(2, 0): {"area": 0, "shape": ShikakuLogic.SHAPE_ANY},
	}
	assert_true(ShikakuSolver.is_human_solvable(4, 2, anchors),
		"4×2 puzzle with two SHAPE_ANY anchors must be human-solvable")


func test_restriction_propagation_accumulates_across_iterations() -> void:
	# Verify that required_cells restrictions recorded in Phase 2 are applied
	# in subsequent Phase 1 and Phase 2 iterations, enabling cumulative
	# exact-cover deductions that neither phase could make independently.
	#
	# 4×2 grid, A at (0,0) SHAPE_ANY, B at (2,0) SHAPE_ANY.
	# The unique solution is A=2×2@(0,0), B=2×2@(2,0).
	# Phase 2 correctly deduces A's placement because (1,1) is uniquely owned by A;
	# additionally, with deduplication, (0,1) is correctly identified as uniquely
	# owned by A (two of A's candidates cover it, but no B candidate does).
	# With restriction propagation, A's required_cells accumulate so the solver
	# applies narrowed candidates across iterations.
	var anchors := {
		Vector2i(0, 0): {"area": 0, "shape": ShikakuLogic.SHAPE_ANY},
		Vector2i(2, 0): {"area": 0, "shape": ShikakuLogic.SHAPE_ANY},
	}
	assert_true(ShikakuSolver.is_human_solvable(4, 2, anchors),
		"4×2 puzzle with two SHAPE_ANY anchors must be human-solvable via combined deductions")


# ---------------------------------------------------------------------------
# Fix 4 (current batch) — cancellation polling in area-constrained enumeration
# ---------------------------------------------------------------------------

func test_enumerate_rects_returns_empty_when_cancelled_with_area_constraint() -> void:
	# Before this fix, the area-constrained branch (anchor_area > 0) in
	# _enumerate_rects_for_anchor never polled cancel_check.  Verify that it
	# now aborts early when the check fires.
	var covered := PackedByteArray()
	covered.resize(5 * 5)
	covered.fill(0)
	# Large area so the w-loop has many iterations to cancel through.
	var anchor := {"area": 15, "shape": ShikakuLogic.SHAPE_ABSENT}
	var cancel_check := func() -> bool: return true  # always cancel
	var rects := ShikakuSolver._enumerate_rects_for_anchor(
		Vector2i(2, 2), anchor, 5, 5, covered, cancel_check)
	assert_true(rects.is_empty(),
		"_enumerate_rects_for_anchor must return [] when cancel fires in area-constrained branch")


# ---------------------------------------------------------------------------
# Fix (current batch) — count_solutions returns -1 (not 0) on cancellation
# during area-constrained candidate enumeration
# ---------------------------------------------------------------------------

func test_count_solutions_returns_minus_one_when_cancelled_during_area_constrained_enumeration() -> void:
	# Before this fix, cancellation inside _enumerate_rects_for_anchor caused it
	# to return [].  _count_backtrack then saw zero candidates and returned without
	# setting cancelled[0]=true, so count_solutions returned 0 instead of -1.
	# The post-enumeration cancel re-poll now propagates the flag correctly.
	# Use a cancel_check that passes the first top-of-function poll but fires
	# on subsequent calls (including the one inside area-constrained enumeration).
	var call_count := [0]
	var cancel_check := func() -> bool:
		call_count[0] += 1
		return call_count[0] > 1  # First call passes; all subsequent calls cancel
	var anchors := {
		Vector2i(0, 0): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT},
		Vector2i(2, 0): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT},
	}
	var result := ShikakuSolver.count_solutions(4, 2, anchors, 2, cancel_check)
	assert_eq(result, -1,
		"count_solutions must return -1 (not 0) when cancelled during area-constrained enumeration")



# ---------------------------------------------------------------------------
# Stats history mode filtering
# ---------------------------------------------------------------------------

const StatsScreenScript := preload("res://scripts/shikaku/shikaku_stats_screen.gd")
const _TEST_STATS_FILTER_PATH := "user://test_shikaku_stats_filter.cfg"


func test_stats_history_standard_mode_excludes_shapes_entries() -> void:
	# _get_time_history_for_size_mode must NOT mix Shapes entries into
	# Standard history — history with mode=RULE_SET_SHAPES must be excluded.
	var orig_path := GameStatsManager.save_path
	GameStatsManager.save_path = _TEST_STATS_FILTER_PATH
	GameStatsManager.clear("shikaku")

	GameStatsManager.record("shikaku", {
		"type": "completion", "grid_size": 5, "time": 120.0,
		"mode": ShikakuLogic.RULE_SET_STANDARD,
	})
	GameStatsManager.record("shikaku", {
		"type": "completion", "grid_size": 5, "time": 200.0,
		"mode": ShikakuLogic.RULE_SET_SHAPES,
	})

	# Instantiate without adding to scene tree so _ready() is not triggered
	# (which would access @onready UI nodes absent in the test context).
	var screen := StatsScreenScript.new()
	var standard_times: Array = screen._get_time_history_for_size_mode(5, ShikakuLogic.RULE_SET_STANDARD)
	screen.free()

	assert_eq(standard_times.size(), 1, "Standard history must include only Standard entries")
	assert_eq(standard_times[0], 120.0, "Standard history must contain the Standard entry time")

	GameStatsManager.save_path = orig_path
	if FileAccess.file_exists(_TEST_STATS_FILTER_PATH):
		DirAccess.remove_absolute(_TEST_STATS_FILTER_PATH)


func test_stats_history_shapes_mode_excludes_standard_entries() -> void:
	# _get_time_history_for_size_mode must NOT mix Standard entries into
	# Shapes history — history with mode=RULE_SET_STANDARD must be excluded.
	var orig_path := GameStatsManager.save_path
	GameStatsManager.save_path = _TEST_STATS_FILTER_PATH
	GameStatsManager.clear("shikaku")

	GameStatsManager.record("shikaku", {
		"type": "completion", "grid_size": 7, "time": 90.0,
		"mode": ShikakuLogic.RULE_SET_STANDARD,
	})
	GameStatsManager.record("shikaku", {
		"type": "completion", "grid_size": 7, "time": 150.0,
		"mode": ShikakuLogic.RULE_SET_SHAPES,
	})

	var screen := StatsScreenScript.new()
	var shapes_times: Array = screen._get_time_history_for_size_mode(7, ShikakuLogic.RULE_SET_SHAPES)
	screen.free()

	assert_eq(shapes_times.size(), 1, "Shapes history must include only Shapes entries")
	assert_eq(shapes_times[0], 150.0, "Shapes history must contain the Shapes entry time")

	GameStatsManager.save_path = orig_path
	if FileAccess.file_exists(_TEST_STATS_FILTER_PATH):
		DirAccess.remove_absolute(_TEST_STATS_FILTER_PATH)


func test_stats_history_entries_without_mode_treated_as_standard() -> void:
	# Legacy entries without a "mode" key must be counted as Standard.
	var orig_path := GameStatsManager.save_path
	GameStatsManager.save_path = _TEST_STATS_FILTER_PATH
	GameStatsManager.clear("shikaku")

	GameStatsManager.record("shikaku", {
		"type": "completion", "grid_size": 5, "time": 180.0,
		# No "mode" key — legacy entry
	})

	var screen := StatsScreenScript.new()
	var standard_times: Array = screen._get_time_history_for_size_mode(5, ShikakuLogic.RULE_SET_STANDARD)
	var shapes_times: Array = screen._get_time_history_for_size_mode(5, ShikakuLogic.RULE_SET_SHAPES)
	screen.free()

	assert_eq(standard_times.size(), 1, "Legacy entries (no mode key) must appear in Standard history")
	assert_eq(shapes_times.size(), 0, "Legacy entries must not appear in Shapes history")

	GameStatsManager.save_path = orig_path
	if FileAccess.file_exists(_TEST_STATS_FILTER_PATH):
		DirAccess.remove_absolute(_TEST_STATS_FILTER_PATH)


# ---------------------------------------------------------------------------
# Fix — human solver must verify full grid coverage, not only anchor placement
# ---------------------------------------------------------------------------

func test_is_human_solvable_false_when_area1_anchor_leaves_grid_uncovered() -> void:
	# 2×2 grid, single anchor at (0,0) with area=1.
	# The only valid rect is 1×1@(0,0), leaving three cells uncovered.
	# All anchors are placed after one step, but the puzzle has no valid solution
	# that tiles the whole grid.  Without the full-coverage check,
	# is_human_solvable would return true (all anchors placed) even though the
	# grid is not fully tiled.
	var anchors := _make_anchors([
		[Vector2i(0, 0), 1, ShikakuLogic.SHAPE_ABSENT],
	])
	assert_false(ShikakuSolver.is_human_solvable(2, 2, anchors),
		"is_human_solvable must return false when placed anchors leave grid cells uncovered")


func test_is_human_solvable_true_when_all_cells_covered() -> void:
	# 2×2 grid, single anchor at (0,0) with area=4 — forced to 2×2 rect.
	# All anchors placed and all cells covered → human-solvable.
	var anchors := _make_anchors([
		[Vector2i(0, 0), 4, ShikakuLogic.SHAPE_ABSENT],
	])
	assert_true(ShikakuSolver.is_human_solvable(2, 2, anchors),
		"is_human_solvable must return true when the single forced placement covers all cells")


# ---------------------------------------------------------------------------
# Fix — MRV enumeration in count_solutions propagates cancel_check
# ---------------------------------------------------------------------------

func test_count_solutions_mrv_cancellation_does_not_proceed_to_backtrack() -> void:
	# Before the fix, _enumerate_rects_for_anchor was called without cancel_check
	# during MRV init, so a cancel that fired inside that call was silently ignored
	# (returned [] but cancelled[0] was not set, allowing backtracking to start).
	# After the fix the MRV loop polls cancel_check before each call and returns -1.
	var anchors := _make_anchors([
		[Vector2i(0, 0), 0, ShikakuLogic.SHAPE_ANY],
		[Vector2i(2, 0), 0, ShikakuLogic.SHAPE_ANY],
	])
	var cancel_check := func() -> bool: return true  # always cancel
	var result := ShikakuSolver.count_solutions(3, 2, anchors, 2, cancel_check)
	assert_eq(result, -1, "count_solutions must return -1 when cancel fires during MRV init")


# ---------------------------------------------------------------------------
# Fix — forward-checking path in _count_backtrack propagates cancel_check
# ---------------------------------------------------------------------------

func test_count_solutions_forward_check_cancellation_returns_minus_one() -> void:
	# count_solutions on a puzzle with multiple unconstrained anchors exercises
	# the forward-checking loop (_has_any_feasible_candidate).  With a callable
	# that cancels after a few calls, count_solutions must return -1.
	var anchors := _make_anchors([
		[Vector2i(0, 0), 0, ShikakuLogic.SHAPE_ANY],
		[Vector2i(3, 0), 0, ShikakuLogic.SHAPE_ANY],
		[Vector2i(0, 3), 0, ShikakuLogic.SHAPE_ANY],
		[Vector2i(3, 3), 0, ShikakuLogic.SHAPE_ANY],
	])
	var call_count := [0]
	# Allow a few calls so MRV init completes, then cancel during backtracking.
	var cancel_check := func() -> bool:
		call_count[0] += 1
		return call_count[0] > 10
	var result := ShikakuSolver.count_solutions(5, 5, anchors, 2, cancel_check)
	assert_eq(result, -1,
		"count_solutions must return -1 when cancel fires during forward-checking")
