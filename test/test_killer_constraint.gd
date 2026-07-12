extends GutTest

const KillerConstraintScript := preload("res://scripts/sudoku/killer_constraint.gd")

func test_get_id_and_serialized_cages() -> void:
	var constraint := KillerConstraintScript.new([
		{"cells": [0, 1], "sum": 3},
		{"cells": [2, 11, 20], "sum": 15},
	])
	assert_eq(constraint.get_id(), "killer")
	assert_eq(constraint.get_cages(), [
		{"cells": [0, 1], "sum": 3},
		{"cells": [2, 11, 20], "sum": 15},
	])


func test_duplicate_digits_in_cage_are_invalid() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	grid[1] = 1
	var constraint := KillerConstraintScript.new([
		{"cells": [0, 1], "sum": 3},
	])
	assert_false(constraint.is_valid(grid, 0, 1))
	assert_false(SudokuSolver.is_valid_placement(grid, 0, 1, [constraint]))
	assert_true(SudokuSolver.is_valid_placement(grid, 0, 2, [constraint]))


func test_filled_cage_must_match_target_sum() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	grid[1] = 4
	var constraint := KillerConstraintScript.new([
		{"cells": [0, 1], "sum": 7},
	])
	assert_false(constraint.is_valid(grid, 0, 2))
	assert_true(constraint.is_valid(grid, 0, 3))


func test_partial_sum_bounds_are_respected() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	grid[1] = 4
	var constraint := KillerConstraintScript.new([
		{"cells": [0, 1, 2], "sum": 10},
	])
	assert_false(constraint.is_valid(grid, 0, 7))
	assert_true(constraint.is_valid(grid, 0, 1))


func test_get_affected_indices_returns_other_cells_in_cage() -> void:
	var constraint := KillerConstraintScript.new([
		{"cells": [10, 11, 20], "sum": 14},
	])
	assert_eq(constraint.get_affected_indices(11), [10, 20])
