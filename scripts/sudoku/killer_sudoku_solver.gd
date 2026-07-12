class_name KillerSudokuSolver
extends RefCounted

enum Technique {
	NAKED_SINGLE,
	HIDDEN_SINGLE,
	CAGE_COMBINATION,
}

var constraint = null
var solution: Array[int] = []
var is_unique: bool = false
var techniques_used: Array[Technique] = []
var difficulty: int = SudokuSolver.Difficulty.EASY


func _init(p_constraint = null) -> void:
	constraint = p_constraint


func solve_logic(grid: Array[int], p_constraint = null) -> bool:
	if p_constraint != null:
		constraint = p_constraint
	techniques_used.clear()

	while true:
		var candidates := _build_candidates(grid)
		if _has_dead_cell(grid, candidates):
			return false

		if _apply_naked_singles(grid, candidates):
			_record_technique(Technique.NAKED_SINGLE)
			continue
		if _apply_hidden_singles(grid, candidates):
			_record_technique(Technique.HIDDEN_SINGLE)
			continue
		break

	return _is_complete(grid)


func analyze(puzzle: Array[int]) -> void:
	var solutions := SudokuSolver.solve_brute_force(puzzle, 2, [constraint])
	is_unique = solutions.size() == 1
	if is_unique:
		solution = []
		solution.assign(solutions[0])
	else:
		solution.clear()

	var work: Array[int] = []
	work.assign(puzzle.duplicate())
	var logic_solved := solve_logic(work)
	difficulty = rate_difficulty(puzzle, logic_solved)


func rate_difficulty(puzzle: Array[int], logic_solved: bool) -> int:
	var givens := 0
	for value in puzzle:
		if int(value) != 0:
			givens += 1
	var max_cage_size := 0
	for cage in constraint.get_cages():
		max_cage_size = maxi(max_cage_size, (cage["cells"] as Array).size())
	if not logic_solved:
		return SudokuSolver.Difficulty.EVIL
	if Technique.CAGE_COMBINATION in techniques_used:
		if givens == 0 and max_cage_size >= 4:
			return SudokuSolver.Difficulty.EXPERT
		return SudokuSolver.Difficulty.HARD
	if givens == 0 and max_cage_size >= 4:
		return SudokuSolver.Difficulty.HARD
	if givens > 0:
		return SudokuSolver.Difficulty.EASY
	return SudokuSolver.Difficulty.MEDIUM


func _build_candidates(grid: Array[int]) -> Array:
	var candidates: Array = []
	candidates.resize(81)
	for index in 81:
		if grid[index] != 0:
			candidates[index] = []
			continue
		candidates[index] = SudokuSolver.get_candidates(grid, index, [constraint])
	var reduction_changed := _reduce_cage_candidates(grid, candidates)
	if reduction_changed:
		_record_technique(Technique.CAGE_COMBINATION)
	return candidates


func _reduce_cage_candidates(grid: Array[int], candidates: Array) -> bool:
	var changed := false
	for cage in constraint.get_cages():
		var empty_cells: Array[int] = []
		var used_digits: Array[int] = []
		var sum_so_far := 0
		var target_sum := int(cage["sum"])
		for cell in cage["cells"]:
			var digit := int(grid[cell])
			if digit == 0:
				empty_cells.append(cell)
				continue
			used_digits.append(digit)
			sum_so_far += digit
		if empty_cells.is_empty():
			continue

		var cell_valid_digits_out := {}
		for cell in empty_cells:
			cell_valid_digits_out[cell] = []
		var assignment_count := _enumerate_cage_assignments(empty_cells, 0, candidates, used_digits, sum_so_far, target_sum, cell_valid_digits_out)
		if assignment_count == 0:
			for cell in empty_cells:
				candidates[cell] = []
			continue

		for cell in empty_cells:
			var allowed: Array = cell_valid_digits_out[cell]
			var current: Array = candidates[cell]
			var filtered: Array[int] = []
			for digit in current:
				if digit in allowed:
					filtered.append(digit)
			if filtered != current:
				candidates[cell] = filtered
				changed = true
	return changed


func _enumerate_cage_assignments(empty_cells: Array[int], cell_index: int, candidates: Array, used_digits: Array[int], sum_so_far: int, target_sum: int, cell_valid_digits_out: Dictionary) -> int:
	if cell_index >= empty_cells.size():
		return 1 if sum_so_far == target_sum else 0

	var current_cell := int(empty_cells[cell_index])
	var current_candidates: Array[int] = candidates[current_cell]
	var count := 0

	for digit in current_candidates:
		if digit in used_digits:
			continue

		var next_sum := sum_so_far + digit
		if next_sum > target_sum:
			continue

		var next_used: Array[int] = used_digits.duplicate()
		next_used.append(digit)
		var remaining_cells := empty_cells.size() - cell_index - 1
		if not _remaining_sum_possible(next_used, next_sum, target_sum, remaining_cells):
			continue

		var sub_count := _enumerate_cage_assignments(empty_cells, cell_index + 1, candidates, next_used, next_sum, target_sum, cell_valid_digits_out)
		if sub_count > 0:
			var cell_digits: Array = cell_valid_digits_out[current_cell]
			if not digit in cell_digits:
				cell_digits.append(digit)
			count += sub_count
	return count


func _remaining_sum_possible(used_digits: Array[int], sum_so_far: int, target_sum: int, remaining_cells: int) -> bool:
	if remaining_cells == 0:
		return sum_so_far == target_sum
	var remaining_digits: Array[int] = []
	for digit in range(1, 10):
		if not digit in used_digits:
			remaining_digits.append(digit)
	if remaining_digits.size() < remaining_cells:
		return false
	var min_possible := 0
	var max_possible := 0
	for i in remaining_cells:
		min_possible += remaining_digits[i]
		max_possible += remaining_digits[remaining_digits.size() - 1 - i]
	var remaining_target := target_sum - sum_so_far
	return remaining_target >= min_possible and remaining_target <= max_possible


func _apply_naked_singles(grid: Array[int], candidates: Array) -> bool:
	var progress := false
	for index in 81:
		if grid[index] == 0 and candidates[index].size() == 1:
			grid[index] = int(candidates[index][0])
			progress = true
	return progress


func _apply_hidden_singles(grid: Array[int], candidates: Array) -> bool:
	var progress := false
	for unit in _get_units():
		for digit in range(1, 10):
			var positions: Array[int] = []
			for index in unit:
				if grid[index] == 0 and digit in candidates[index]:
					positions.append(index)
			if positions.size() == 1:
				grid[positions[0]] = digit
				progress = true
	return progress


func _get_units() -> Array:
	var units := SudokuSolver._get_all_units()
	for cage in constraint.get_cages():
		var unit: Array[int] = []
		for cell in cage["cells"]:
			unit.append(int(cell))
		units.append(unit)
	return units


func _has_dead_cell(grid: Array[int], candidates: Array) -> bool:
	for index in 81:
		if grid[index] == 0 and candidates[index].is_empty():
			return true
	return false


func _is_complete(grid: Array[int]) -> bool:
	for value in grid:
		if int(value) == 0:
			return false
	return true


func _record_technique(technique: Technique) -> void:
	if not technique in techniques_used:
		techniques_used.append(technique)
