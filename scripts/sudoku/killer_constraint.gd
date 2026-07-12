class_name KillerConstraint
extends RefCounted

## Validates killer cage constraints against the current grid state.
##
## Provides two types of violations:
##   1. Duplicate digits within a cage
##   2. A fully-filled cage whose digit sum does not match the cage target
##
## Strict/free mode is handled by the caller; this class only reports which
## cells are in violation — it does not modify game state or add strikes.

## Internal cage record built from the raw cage dictionaries.
class CageInfo:
	var cells: Array[int] = []
	var target_sum: int = 0
	var anchor: int = 0

var _cages: Array[CageInfo] = []
var _cell_to_cage: Array[int] = []  # cell_index → cage index (-1 = none)


## Initialise from the cage array produced by KillerCageGenerator.
## Each entry: { "cells": Array[int], "sum": int, "anchor": int }
func setup(cage_dicts: Array) -> void:
	_cages.clear()
	_cell_to_cage.resize(81)
	_cell_to_cage.fill(-1)

	for i in cage_dicts.size():
		var d: Dictionary = cage_dicts[i]
		var info := CageInfo.new()
		for c in d.get("cells", []):
			info.cells.append(int(c))
		info.target_sum = int(d.get("sum", 0))
		info.anchor = int(d.get("anchor", -1))
		_cages.append(info)

		for c in info.cells:
			_cell_to_cage[c] = i


## Returns a Dictionary of cell indices → true for cells that are in violation.
## current_grid: Array[int] of length 81, 0 = empty.
## Violations:
##   - Any cell in a cage that shares a digit with another cell in the same cage
##   - All cells in a fully-filled cage whose sum ≠ the target
func get_error_cells(current_grid: Array[int]) -> Dictionary:
	var errors: Dictionary = {}

	for cage in _cages:
		var filled: Array[int] = []
		var digit_counts: Dictionary = {}
		var total := 0
		var all_filled := true

		for c in cage.cells:
			var v: int = current_grid[c]
			if v == 0:
				all_filled = false
				continue
			filled.append(c)
			total += v
			digit_counts[v] = digit_counts.get(v, 0) + 1

		# Flag duplicate digits
		for c in filled:
			var v: int = current_grid[c]
			if digit_counts.get(v, 0) > 1:
				errors[c] = true

		# Flag wrong sum on a fully filled cage (only if no digit duplicates)
		if all_filled and total != cage.target_sum:
			var has_dup := false
			for c in cage.cells:
				if errors.has(c):
					has_dup = true
					break
			if not has_dup:
				for c in cage.cells:
					errors[c] = true

	return errors


## Returns the cage index for the given cell, or -1 if none.
func get_cage_index(cell: int) -> int:
	if cell < 0 or cell >= _cell_to_cage.size():
		return -1
	return _cell_to_cage[cell]


## Returns true when at least one cage has been registered.
func is_active() -> bool:
	return not _cages.is_empty()
