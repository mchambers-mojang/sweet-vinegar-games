extends GutTest

const KillerConstraintScript := preload("res://scripts/sudoku/killer_constraint.gd")
const KillerSudokuGeneratorScript := preload("res://scripts/sudoku/killer_sudoku_generator.gd")
const KillerSudokuSolverScript := preload("res://scripts/sudoku/killer_sudoku_solver.gd")


class DuplicateDigitGenerator extends KillerSudokuGeneratorScript:
	func _create_puzzle_with_minimal_givens(full_grid: Array[int], _constraint, _difficulty: int, _rng: RandomNumberGenerator, _cancel_check: Callable = Callable()) -> Array[int]:
		var invalid: Array[int] = []
		invalid.assign(full_grid.duplicate())
		invalid[0] = invalid[1]
		return invalid


## Generator subclass that bypasses the expensive give-minimization phase by
## returning the full grid directly.  This lets the loop reach solver.analyze()
## within the very first attempt so cancellation during analysis is exercised.
class AnalysisCancelGenerator extends KillerSudokuGeneratorScript:
	func _create_puzzle_with_minimal_givens(full_grid: Array[int], _constraint, _difficulty: int, _rng: RandomNumberGenerator, _cancel_check: Callable = Callable()) -> Array[int]:
		return full_grid.duplicate()


func test_generation_pipeline_returns_unique_logic_solvable_puzzle() -> void:
	var generator := KillerSudokuGeneratorScript.new()
	var result: Dictionary = generator.generate(SudokuSolver.Difficulty.EASY, 9)
	assert_true(result.has("puzzle"))
	assert_true(result.has("solution"))
	assert_true(result.has("cages"))
	assert_eq(result["puzzle"].size(), 81)
	assert_eq(result["solution"].size(), 81)
	assert_true(result["cages"].size() > 0)

	var constraint := KillerConstraintScript.new(result["cages"])
	var solver := KillerSudokuSolverScript.new(constraint)
	var puzzle: Array[int] = []
	puzzle.assign(result["puzzle"])
	var solutions := SudokuSolver.solve_brute_force(puzzle, 2, [constraint])
	assert_eq(solutions.size(), 1)
	assert_true(solver.solve_logic(puzzle.duplicate()))


func test_pure_killer_puzzle_generated_when_cages_provide_uniqueness() -> void:
	var full_grid: Array[int] = []
	full_grid.assign(SudokuGenerator.SEED_GRID.duplicate())
	var cages: Array = []
	for index in 81:
		cages.append({
			"cells": [index],
			"sum": full_grid[index],
		})

	var generator := KillerSudokuGeneratorScript.new()
	var puzzle := generator._minimize_from_full_grid(full_grid, KillerConstraintScript.new(cages), RandomNumberGenerator.new())
	assert_eq(_count_givens(puzzle), 0)


func test_fallback_adds_only_needed_givens_for_uniqueness() -> void:
	var full_grid: Array[int] = []
	full_grid.assign(SudokuGenerator.SEED_GRID.duplicate())
	var generator := KillerSudokuGeneratorScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var constraint := KillerConstraintScript.new([])
	var puzzle := generator._minimize_from_full_grid(full_grid, constraint, rng)
	assert_true(_count_givens(puzzle) > 0)
	assert_true(generator._is_acceptable_puzzle(puzzle, constraint))

	for index in 81:
		if puzzle[index] == 0:
			continue
		var candidate: Array[int] = []
		candidate.assign(puzzle.duplicate())
		candidate[index] = 0
		assert_false(generator._is_acceptable_puzzle(candidate, constraint))


func test_generate_returns_empty_result_when_attempts_are_rejected() -> void:
	var result: Dictionary = DuplicateDigitGenerator.new().generate(SudokuSolver.Difficulty.EASY, 9)
	assert_false(result.has("puzzle"))


func test_generate_returns_empty_when_cancelled_during_analysis() -> void:
	# Regression: cancel_check must be propagated through solver.analyze() so
	# that cancellation fired during the final brute-force uniqueness check (or
	# logic solve) causes generate() to return {} rather than blocking until
	# analysis completes.
	#
	# AnalysisCancelGenerator skips give-minimization, so the loop reaches
	# solver.analyze() on the very first attempt.  The cancel_check returns false
	# on the first poll (the loop-start guard) and true on all subsequent polls,
	# which fires inside solve_brute_force() called from analyze().
	#
	# NOTE: Use an Array as a reference-type counter.  GDScript lambdas do not
	# reliably mutate captured primitive locals across calls (Godot 4.6.3), so
	# an int counter would stay at 0 inside the lambda and cancellation would
	# never fire.
	var state := [0]  # state[0] = call count; Array is a reference type.
	var cancel := func() -> bool:
		state[0] += 1
		return state[0] > 1  # Let the first (loop-guard) poll pass; cancel inside analyze().

	var result := AnalysisCancelGenerator.new().generate(SudokuSolver.Difficulty.EASY, 9, cancel)
	assert_false(result.has("puzzle"),
			"generate() must return {} when cancelled during solver analysis")
	# state[0] starts at 0; the loop-start guard increments it to 1 (returns false,
	# letting the attempt continue).  If cancellation fired inside analyze() as
	# intended, the callable will have been invoked at least once more (state[0] >= 2).
	# A value of exactly 1 would mean cancellation only ever reached the loop-start
	# guard, which would indicate the code path being tested was not exercised.
	assert_gt(state[0], 1,
			"cancel_check must fire more than once, confirming it was invoked inside analyze() not only at the loop-start guard")


func _count_givens(puzzle: Array) -> int:
	var count := 0
	for value in puzzle:
		if int(value) != 0:
			count += 1
	return count
