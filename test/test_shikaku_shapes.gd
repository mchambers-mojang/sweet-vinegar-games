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
	var gen := ShikakuGenerator.generate(8, 8, 102, ShikakuLogic.RULE_SET_SHAPES)
	var anchors: Dictionary = gen.get("anchors", {})
	var solution: Array[Rect2i] = gen.get("solution", [])
	assert_true(ShikakuSolver.validate_anchors(8, 8, anchors, solution))


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
	var gen := ShikakuGenerator.generate(15, 15, 105, ShikakuLogic.RULE_SET_SHAPES)
	var anchors: Dictionary = gen.get("anchors", {})
	var solution: Array[Rect2i] = gen.get("solution", [])
	assert_true(ShikakuSolver.validate_anchors(15, 15, anchors, solution))


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
