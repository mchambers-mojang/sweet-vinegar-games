extends GutTest

## Unit tests for KillerConstraint

# A simple 9×9 grid where all cells are 0 (empty) or explicitly set values.
# We only use a 9-cell grid conceptually; actual indices are 0-80.

func _make_grid(overrides: Dictionary = {}) -> Array[int]:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	for k in overrides:
		grid[int(k)] = int(overrides[k])
	return grid


func _make_constraint(cage_dicts: Array) -> KillerConstraint:
	var kc := KillerConstraint.new()
	kc.setup(cage_dicts)
	return kc


# ---------------------------------------------------------------------------
# Empty grid — no errors
# ---------------------------------------------------------------------------

func test_empty_grid_no_errors() -> void:
	var kc := _make_constraint([
		{"cells": [0, 1], "sum": 8, "anchor": 0},
		{"cells": [2, 3], "sum": 9, "anchor": 2},
	])
	var errors := kc.get_error_cells(_make_grid())
	assert_true(errors.is_empty())


# ---------------------------------------------------------------------------
# Correct partial fill — no errors
# ---------------------------------------------------------------------------

func test_correct_partial_fill_no_errors() -> void:
	var kc := _make_constraint([
		{"cells": [0, 1], "sum": 8, "anchor": 0},
	])
	# 3 + 5 = 8, cage not full yet → no error
	var grid := _make_grid({0: 3})
	var errors := kc.get_error_cells(grid)
	assert_true(errors.is_empty())


# ---------------------------------------------------------------------------
# Duplicate digit within a cage
# ---------------------------------------------------------------------------

func test_duplicate_digit_in_cage_flagged() -> void:
	# Cells 0 and 1 both get digit 4
	var kc := _make_constraint([
		{"cells": [0, 1], "sum": 5, "anchor": 0},
	])
	var grid := _make_grid({0: 4, 1: 4})
	var errors := kc.get_error_cells(grid)
	assert_true(errors.has(0), "cell 0 should be flagged")
	assert_true(errors.has(1), "cell 1 should be flagged")


func test_duplicate_only_flags_duplicated_cells() -> void:
	# Three-cell cage: cells 0, 1, 2.  Cells 0 and 2 share digit 3; cell 1 is unique.
	var kc := _make_constraint([
		{"cells": [0, 1, 2], "sum": 10, "anchor": 0},
	])
	var grid := _make_grid({0: 3, 1: 5, 2: 3})
	var errors := kc.get_error_cells(grid)
	assert_true(errors.has(0))
	assert_true(errors.has(2))
	assert_false(errors.has(1), "non-duplicate cell 1 must not be flagged")


# ---------------------------------------------------------------------------
# Completed cage wrong sum
# ---------------------------------------------------------------------------

func test_completed_cage_wrong_sum_flagged() -> void:
	# Two-cell cage with target sum 5.  Placed: 3 + 5 = 8 ≠ 5.
	var kc := _make_constraint([
		{"cells": [0, 1], "sum": 5, "anchor": 0},
	])
	var grid := _make_grid({0: 3, 1: 5})
	var errors := kc.get_error_cells(grid)
	assert_true(errors.has(0))
	assert_true(errors.has(1))


func test_completed_cage_correct_sum_no_error() -> void:
	var kc := _make_constraint([
		{"cells": [0, 1], "sum": 8, "anchor": 0},
	])
	var grid := _make_grid({0: 3, 1: 5})
	var errors := kc.get_error_cells(grid)
	assert_true(errors.is_empty())


# ---------------------------------------------------------------------------
# Wrong sum vs duplicate: duplicate takes precedence
# ---------------------------------------------------------------------------

func test_duplicate_hides_wrong_sum() -> void:
	# If there are duplicates in the cage, wrong-sum logic is suppressed for that cage
	# so we do not double-flag.
	var kc := _make_constraint([
		{"cells": [0, 1], "sum": 5, "anchor": 0},
	])
	# Both cells = 4.  Sum = 8 ≠ 5.  Duplicate detected → wrong-sum NOT applied.
	var grid := _make_grid({0: 4, 1: 4})
	var errors := kc.get_error_cells(grid)
	# Both cells flagged for duplicate (correct) but there should not be extra entries
	assert_eq(errors.size(), 2)


# ---------------------------------------------------------------------------
# Multi-cage independence
# ---------------------------------------------------------------------------

func test_errors_in_one_cage_do_not_affect_other() -> void:
	var kc := _make_constraint([
		{"cells": [0, 1], "sum": 8, "anchor": 0},
		{"cells": [9, 10], "sum": 5, "anchor": 9},
	])
	# First cage OK; second cage wrong sum (3 + 4 = 7 ≠ 5)
	var grid := _make_grid({0: 3, 1: 5, 9: 3, 10: 4})
	var errors := kc.get_error_cells(grid)
	assert_false(errors.has(0))
	assert_false(errors.has(1))
	assert_true(errors.has(9))
	assert_true(errors.has(10))


# ---------------------------------------------------------------------------
# is_active()
# ---------------------------------------------------------------------------

func test_is_active_after_setup() -> void:
	var kc := _make_constraint([{"cells": [0, 1], "sum": 5, "anchor": 0}])
	assert_true(kc.is_active())


func test_is_not_active_before_setup() -> void:
	var kc := KillerConstraint.new()
	assert_false(kc.is_active())


# ---------------------------------------------------------------------------
# get_cage_index
# ---------------------------------------------------------------------------

func test_get_cage_index_known_cell() -> void:
	var kc := _make_constraint([
		{"cells": [5, 6], "sum": 7, "anchor": 5},
	])
	assert_eq(kc.get_cage_index(5), 0)
	assert_eq(kc.get_cage_index(6), 0)


func test_get_cage_index_out_of_range() -> void:
	var kc := _make_constraint([{"cells": [0], "sum": 1, "anchor": 0}])
	assert_eq(kc.get_cage_index(-1), -1)
	assert_eq(kc.get_cage_index(81), -1)
