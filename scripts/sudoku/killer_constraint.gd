class_name KillerConstraint
extends "res://scripts/sudoku/sudoku_constraint.gd"

const GRID_CELLS := 81

var _cages: Array = []
var _index_to_cage: Dictionary = {}


func _init(cages: Array = []) -> void:
	_set_cages(cages)


func _set_cages(cages: Array) -> void:
	_cages.clear()
	_index_to_cage.clear()
	for cage_data in cages:
		var cells: Array[int] = []
		for cell in cage_data.get("cells", []):
			cells.append(int(cell))
		cells.sort()
		var cage := {
			"cells": cells,
			"sum": int(cage_data.get("sum", 0)),
		}
		_cages.append(cage)
		for index in cells:
			_index_to_cage[index] = _cages.size() - 1


func get_id() -> String:
	return "killer"


func get_cages() -> Array:
	var serialized: Array = []
	for cage in _cages:
		serialized.append({
			"cells": (cage["cells"] as Array[int]).duplicate(),
			"sum": cage["sum"],
		})
	return serialized


func get_affected_indices(index: int) -> Array[int]:
	var cage := get_cage_for_index(index)
	if cage.is_empty():
		return []
	var affected: Array[int] = []
	for other in cage["cells"]:
		if other != index:
			affected.append(other)
	return affected


func get_cage_for_index(index: int) -> Dictionary:
	if not _index_to_cage.has(index):
		return {}
	return _cages[int(_index_to_cage[index])]


func is_valid(grid: Array[int], index: int, value: int) -> bool:
	var cage := get_cage_for_index(index)
	if cage.is_empty():
		return true

	var used_digits: Array[int] = [value]
	var sum_so_far := value
	var empty_count := 0

	for other in cage["cells"]:
		if other == index:
			continue
		var digit := int(grid[other])
		if digit == 0:
			empty_count += 1
			continue
		if digit in used_digits:
			return false
		used_digits.append(digit)
		sum_so_far += digit

	var target_sum := int(cage["sum"])
	if sum_so_far > target_sum:
		return false
	if empty_count == 0:
		return sum_so_far == target_sum

	var available_digits: Array[int] = []
	for digit in range(1, 10):
		if not digit in used_digits:
			available_digits.append(digit)
	if available_digits.size() < empty_count:
		return false

	var min_possible := 0
	var max_possible := 0
	for i in empty_count:
		min_possible += available_digits[i]
		max_possible += available_digits[available_digits.size() - 1 - i]

	var remaining_sum := target_sum - sum_so_far
	return remaining_sum >= min_possible and remaining_sum <= max_possible
