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
