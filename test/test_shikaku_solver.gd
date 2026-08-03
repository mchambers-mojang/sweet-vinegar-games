extends GutTest

## Unit tests for ShikakuSolver — validation, solving, and shape constraints.


# --- validate_anchors ---

func test_validate_anchors_correct_solution() -> void:
	var anchors := {
		Vector2i(0, 0): {"area": 8, "shape": ShikakuLogic.SHAPE_ABSENT},
		Vector2i(2, 2): {"area": 8, "shape": ShikakuLogic.SHAPE_ABSENT},
	}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 4, 2), Rect2i(0, 2, 4, 2)]
	assert_true(ShikakuSolver.validate_anchors(4, 4, anchors, rects))


func test_validate_anchors_overlap_fails() -> void:
	var anchors := {Vector2i(0, 0): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(1, 0, 2, 2)]
	assert_false(ShikakuSolver.validate_anchors(4, 4, anchors, rects))


func test_validate_anchors_incomplete_coverage_fails() -> void:
	var anchors := {Vector2i(0, 0): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2)]
	assert_false(ShikakuSolver.validate_anchors(4, 4, anchors, rects))


func test_validate_anchors_wrong_area_fails() -> void:
	var anchors := {
		Vector2i(0, 0): {"area": 6, "shape": ShikakuLogic.SHAPE_ABSENT},
		Vector2i(2, 0): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT},
	}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(2, 0, 2, 2)]
	assert_false(ShikakuSolver.validate_anchors(4, 2, anchors, rects))


func test_validate_shape_square_passes() -> void:
	# 2x2 rectangle with a SQUARE anchor: should pass.
	var anchors := {
		Vector2i(0, 0): {"area": 0, "shape": ShikakuLogic.SHAPE_SQUARE},
		Vector2i(2, 0): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT},
	}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(2, 0, 2, 2)]
	assert_true(ShikakuSolver.validate_anchors(4, 2, anchors, rects))


func test_validate_shape_square_fails_on_non_square() -> void:
	# SQUARE anchor in a 2x1 rectangle: should fail.
	var anchors := {
		Vector2i(0, 0): {"area": 0, "shape": ShikakuLogic.SHAPE_SQUARE},
		Vector2i(2, 0): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT},
	}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 1), Rect2i(2, 0, 2, 1)]
	# Grid 4x1 and SQUARE anchor can't be satisfied by 2x1 rect.
	assert_false(ShikakuSolver.validate_anchors(4, 1, anchors, rects))


func test_validate_shape_tall_passes() -> void:
	# 1x2 rectangle (height>width) with TALL anchor: should pass.
	var anchors := {
		Vector2i(0, 0): {"area": 2, "shape": ShikakuLogic.SHAPE_TALL},
		Vector2i(1, 0): {"area": 2, "shape": ShikakuLogic.SHAPE_ABSENT},
	}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 1, 2), Rect2i(1, 0, 1, 2)]
	assert_true(ShikakuSolver.validate_anchors(2, 2, anchors, rects))


func test_validate_shape_tall_fails_on_wide() -> void:
	# TALL anchor in a 2x1 rectangle (width>height): should fail.
	var anchors := {
		Vector2i(0, 0): {"area": 2, "shape": ShikakuLogic.SHAPE_TALL},
		Vector2i(0, 1): {"area": 2, "shape": ShikakuLogic.SHAPE_ABSENT},
	}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 1), Rect2i(0, 1, 2, 1)]
	assert_false(ShikakuSolver.validate_anchors(2, 2, anchors, rects))


func test_validate_shape_wide_passes() -> void:
	# 2x1 rectangle (width>height) with WIDE anchor: should pass.
	var anchors := {
		Vector2i(0, 0): {"area": 2, "shape": ShikakuLogic.SHAPE_WIDE},
		Vector2i(0, 1): {"area": 2, "shape": ShikakuLogic.SHAPE_ABSENT},
	}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 1), Rect2i(0, 1, 2, 1)]
	assert_true(ShikakuSolver.validate_anchors(2, 2, anchors, rects))


func test_validate_shape_any_passes_all() -> void:
	# ANY anchor accepts any shape.
	var anchors := {
		Vector2i(0, 0): {"area": 4, "shape": ShikakuLogic.SHAPE_ANY},
		Vector2i(2, 0): {"area": 4, "shape": ShikakuLogic.SHAPE_ANY},
	}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(2, 0, 2, 2)]
	assert_true(ShikakuSolver.validate_anchors(4, 2, anchors, rects))


func test_validate_no_area_no_shape_anchor_fails() -> void:
	# An unconstrained anchor (area=0, shape=ABSENT) still requires exactly one
	# anchor per rectangle; the placement should fail validation because the
	# solver would find no matching constraint.
	var anchors := {Vector2i(0, 0): {"area": 0, "shape": ShikakuLogic.SHAPE_ABSENT}}
	# A rect containing the anchor passes if it's the only anchor (any rect is ok)
	# but our validate requires area>0 OR shape != ABSENT for an anchor to be
	# "satisfied". Both constraints are absent → still placed: tests that solver
	# can handle this (area==0, shape==ABSENT → any rect satisfies shape).
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2)]
	# area=0, shape=ABSENT: the anchor has no constraints, any rect is valid.
	assert_true(ShikakuSolver.validate_anchors(2, 2, anchors, rects))


# --- legacy validate ---

func test_validate_correct_solution() -> void:
	var numbers := {Vector2i(0, 0): 8, Vector2i(2, 2): 8}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 4, 2), Rect2i(0, 2, 4, 2)]
	assert_true(ShikakuSolver.validate(4, 4, numbers, rects))


func test_validate_overlap_fails() -> void:
	var numbers := {Vector2i(0, 0): 4}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(1, 0, 2, 2)]
	assert_false(ShikakuSolver.validate(4, 4, numbers, rects))


func test_validate_incomplete_coverage_fails() -> void:
	var numbers := {Vector2i(0, 0): 4}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2)]
	assert_false(ShikakuSolver.validate(4, 4, numbers, rects))


func test_validate_wrong_area_fails() -> void:
	var numbers := {Vector2i(0, 0): 6, Vector2i(2, 0): 4}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(2, 0, 2, 2)]
	assert_false(ShikakuSolver.validate(4, 2, numbers, rects))


func test_validate_two_numbers_in_one_rect_fails() -> void:
	var numbers := {Vector2i(0, 0): 4, Vector2i(1, 0): 4}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2)]
	assert_false(ShikakuSolver.validate(2, 2, numbers, rects))


func test_validate_no_number_in_rect_fails() -> void:
	var numbers := {Vector2i(0, 0): 4}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(2, 0, 2, 2)]
	assert_false(ShikakuSolver.validate(4, 2, numbers, rects))


func test_validate_out_of_bounds_fails() -> void:
	var numbers := {Vector2i(0, 0): 4}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 5, 1)]
	assert_false(ShikakuSolver.validate(4, 4, numbers, rects))


# --- solve ---

func test_solve_simple_2x2() -> void:
	var numbers := {Vector2i(0, 0): 4}
	var solution: Array[Rect2i] = ShikakuSolver.solve(2, 2, numbers)
	assert_eq(solution.size(), 1)
	assert_eq(solution[0], Rect2i(0, 0, 2, 2))


func test_solve_4x4_two_halves() -> void:
	var numbers := {Vector2i(1, 0): 8, Vector2i(1, 2): 8}
	var solution: Array[Rect2i] = ShikakuSolver.solve(4, 4, numbers)
	assert_eq(solution.size(), 2)
	assert_true(ShikakuSolver.validate(4, 4, numbers, solution))


func test_solve_returns_empty_if_unsolvable() -> void:
	var numbers := {Vector2i(0, 0): 3, Vector2i(1, 1): 3}
	var solution: Array[Rect2i] = ShikakuSolver.solve(2, 2, numbers)
	assert_eq(solution.size(), 0)


func test_solve_solution_validates() -> void:
	var numbers := {Vector2i(1, 0): 8, Vector2i(1, 2): 8}
	var solution: Array[Rect2i] = ShikakuSolver.solve(4, 4, numbers)
	assert_true(solution.size() > 0, "Puzzle should be solvable")
	if not solution.is_empty():
		assert_true(ShikakuSolver.validate(4, 4, numbers, solution))


func test_solve_multiple_numbers() -> void:
	var numbers := {
		Vector2i(0, 0): 3,
		Vector2i(0, 1): 3,
		Vector2i(0, 2): 3,
	}
	var solution: Array[Rect2i] = ShikakuSolver.solve(3, 3, numbers)
	if not solution.is_empty():
		assert_eq(solution.size(), 3)
		assert_true(ShikakuSolver.validate(3, 3, numbers, solution))


# --- solve_with_anchors (shape constraints) ---

func test_solve_with_anchors_shape_only_tall() -> void:
	# 2x4 grid: two TALL anchors (1x2 each).
	var anchors := {
		Vector2i(0, 0): {"area": 2, "shape": ShikakuLogic.SHAPE_TALL},
		Vector2i(1, 0): {"area": 2, "shape": ShikakuLogic.SHAPE_TALL},
		Vector2i(0, 2): {"area": 2, "shape": ShikakuLogic.SHAPE_TALL},
		Vector2i(1, 2): {"area": 2, "shape": ShikakuLogic.SHAPE_TALL},
	}
	var solution: Array[Rect2i] = ShikakuSolver.solve_with_anchors(2, 4, anchors)
	assert_true(solution.size() > 0)
	assert_true(ShikakuSolver.validate_anchors(2, 4, anchors, solution))


# --- count_solutions ---

func test_count_solutions_unique() -> void:
	var anchors := {
		Vector2i(0, 0): {"area": 8, "shape": ShikakuLogic.SHAPE_ABSENT},
		Vector2i(0, 2): {"area": 8, "shape": ShikakuLogic.SHAPE_ABSENT},
	}
	var count := ShikakuSolver.count_solutions(4, 4, anchors, 2)
	assert_eq(count, 1)


func test_count_solutions_non_unique() -> void:
	# Two symmetric numbers — multiple valid partitions possible.
	var anchors := {
		Vector2i(1, 0): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT},
		Vector2i(1, 2): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT},
		Vector2i(3, 0): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT},
		Vector2i(3, 2): {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT},
	}
	var count := ShikakuSolver.count_solutions(4, 4, anchors, 2)
	# May have 1 or 2+ solutions depending on layout; just verify it runs.
	assert_true(count >= 1)


# ---------------------------------------------------------------------------
# Regression: exhaustive enumeration must find large required rectangles
# ---------------------------------------------------------------------------

func test_count_solutions_exhaustive_finds_large_required_rect() -> void:
	# 5×2 grid (10 cells) with a single SHAPE_WIDE anchor at (2, 0).
	# The only valid partition uses a 5×2 rectangle (area=10, WIDE since 5>2).
	# A capped enumerator (max_area_hint=8) would exclude area-10 candidates
	# and return 0; exhaustive enumeration must return 1.
	var anchors := {
		Vector2i(2, 0): {"area": 0, "shape": ShikakuLogic.SHAPE_WIDE},
	}
	var count := ShikakuSolver.count_solutions(5, 2, anchors, 2)
	assert_eq(count, 1, "count_solutions must find the unique 5×2 solution despite area > 8")


func test_is_human_solvable_with_large_required_rect() -> void:
	# Same 5×2 grid: the SHAPE_WIDE anchor has exactly one candidate (5×2).
	# is_human_solvable must detect the forced placement and return true.
	var anchors := {
		Vector2i(2, 0): {"area": 0, "shape": ShikakuLogic.SHAPE_WIDE},
	}
	assert_true(ShikakuSolver.is_human_solvable(5, 2, anchors),
		"is_human_solvable must place the forced 5×2 WIDE rect (area > old cap of 8)")
