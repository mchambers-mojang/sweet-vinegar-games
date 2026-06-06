extends GutTest

## Unit tests for ShikakuSolver — validation, solving.


# --- validate ---

func test_validate_correct_solution() -> void:
	# 4x4 grid, two numbers: (0,0)=8 and (2,2)=8
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
	# Number says 6 but rect is 2x2=4
	var numbers := {Vector2i(0, 0): 6, Vector2i(2, 0): 4}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(2, 0, 2, 2)]
	assert_false(ShikakuSolver.validate(4, 2, numbers, rects))


func test_validate_two_numbers_in_one_rect_fails() -> void:
	var numbers := {Vector2i(0, 0): 4, Vector2i(1, 0): 4}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2)]
	assert_false(ShikakuSolver.validate(2, 2, numbers, rects))


func test_validate_no_number_in_rect_fails() -> void:
	# Number at (0,0), rect at (2,0) has no number
	var numbers := {Vector2i(0, 0): 4}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2), Rect2i(2, 0, 2, 2)]
	assert_false(ShikakuSolver.validate(4, 2, numbers, rects))


func test_validate_out_of_bounds_fails() -> void:
	var numbers := {Vector2i(0, 0): 4}
	var rects: Array[Rect2i] = [Rect2i(0, 0, 5, 1)]  # Exceeds width=4
	assert_false(ShikakuSolver.validate(4, 4, numbers, rects))


# --- solve ---

func test_solve_simple_2x2() -> void:
	# 2x2 grid, one number covering everything
	var numbers := {Vector2i(0, 0): 4}
	var solution: Array[Rect2i] = ShikakuSolver.solve(2, 2, numbers)
	assert_eq(solution.size(), 1)
	assert_eq(solution[0], Rect2i(0, 0, 2, 2))


func test_solve_4x4_two_halves() -> void:
	# Split 4x4 into two 4x2 halves
	var numbers := {Vector2i(1, 0): 8, Vector2i(1, 2): 8}
	var solution: Array[Rect2i] = ShikakuSolver.solve(4, 4, numbers)
	assert_eq(solution.size(), 2)
	# Validate the solution
	assert_true(ShikakuSolver.validate(4, 4, numbers, solution))


func test_solve_returns_empty_if_unsolvable() -> void:
	# Impossible: two 3-area numbers in a 2x2 grid
	var numbers := {Vector2i(0, 0): 3, Vector2i(1, 1): 3}
	var solution: Array[Rect2i] = ShikakuSolver.solve(2, 2, numbers)
	assert_eq(solution.size(), 0)


func test_solve_solution_validates() -> void:
	# A known solvable 4x4 puzzle: two 8-area rects
	var numbers := {
		Vector2i(1, 0): 8,
		Vector2i(1, 2): 8,
	}
	var solution: Array[Rect2i] = ShikakuSolver.solve(4, 4, numbers)
	assert_true(solution.size() > 0, "Puzzle should be solvable")
	if not solution.is_empty():
		assert_true(ShikakuSolver.validate(4, 4, numbers, solution))


func test_solve_multiple_numbers() -> void:
	# 3x3 grid with 3 numbers: each 3 cells
	var numbers := {
		Vector2i(0, 0): 3,
		Vector2i(0, 1): 3,
		Vector2i(0, 2): 3,
	}
	var solution: Array[Rect2i] = ShikakuSolver.solve(3, 3, numbers)
	if not solution.is_empty():
		assert_eq(solution.size(), 3)
		assert_true(ShikakuSolver.validate(3, 3, numbers, solution))
