extends GutTest

const KillerConstraintScript := preload("res://scripts/sudoku/killer_constraint.gd")
const KillerSudokuSolverScript := preload("res://scripts/sudoku/killer_sudoku_solver.gd")


func test_hidden_singles_do_not_treat_cages_as_units() -> void:
	var solver := KillerSudokuSolverScript.new(KillerConstraintScript.new([
		{"cells": [0, 1], "sum": 5},
	]))
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	var candidates: Array = []
	candidates.resize(81)
	for index in 81:
		candidates[index] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
	candidates[0] = [1, 2, 4]
	candidates[1] = [1, 3, 4]

	assert_false(solver._apply_hidden_singles(grid, candidates))
	assert_eq(grid[0], 0)
	assert_eq(grid[1], 0)


func test_analyze_respects_cancel_check() -> void:
	# Regression: analyze() must propagate cancel_check so that brute-force and
	# logic-solving inside it can be interrupted before the full solve completes.
	var solver := KillerSudokuSolverScript.new(KillerConstraintScript.new([]))
	var puzzle: Array[int] = []
	puzzle.resize(81)
	puzzle.fill(0)

	# A cancel_check that fires immediately on the first poll.
	var cancel := func() -> bool: return true

	solver.analyze(puzzle, cancel)

	# Brute-force was cancelled before it could confirm uniqueness, so is_unique
	# must remain false (its default) rather than flipping to true.
	assert_false(solver.is_unique,
			"analyze() cancelled before brute-force completes must leave is_unique false")
