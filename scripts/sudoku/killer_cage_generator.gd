class_name KillerCageGenerator
extends RefCounted

## Partitions a complete 9x9 Sudoku solution into killer cages.
##
## Each cage is a contiguous (edge-connected) group of cells.  Within a cage
## no digit repeats, and the cage carries a target sum equal to the sum of
## the solution values for its cells.
##
## Returned cage format:
##   Array of Dictionaries:  [{ "cells": Array[int], "sum": int, "anchor": int }, …]
##     cells  — flat cell indices (0-80) belonging to the cage
##     sum    — target sum (sum of solution digits in those cells)
##     anchor — top-left-most cell index in the cage (used for the sum label)

const MIN_CAGE_SIZE := 2
const MAX_CAGE_SIZE := 5
const MAX_ATTEMPTS := 120


## Generate a cage partition from a complete 9×9 solution grid.
## solution: Array[int] of length 81, values 1-9, fully solved.
## seed_val: RNG seed; pass -1 to randomise.
static func generate(solution: Array[int], seed_val: int = -1) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	if seed_val >= 0:
		rng.seed = seed_val
	else:
		rng.randomize()

	for _attempt in MAX_ATTEMPTS:
		var cages := _try_partition(solution, rng)
		if not cages.is_empty():
			return cages

	# Fallback: deterministic partition that always succeeds
	return _fallback_partition(solution)


static func _try_partition(solution: Array[int], rng: RandomNumberGenerator) -> Array[Dictionary]:
	# cell_cage[i] = cage index for cell i, -1 = unassigned
	var cell_cage: Array[int] = []
	cell_cage.resize(81)
	cell_cage.fill(-1)

	var cages: Array[Dictionary] = []

	# Visit cells in random order so cage shapes vary
	var visit_order := range(81)
	_shuffle_array(visit_order, rng)

	for start in visit_order:
		if cell_cage[start] != -1:
			continue

		# Try to grow a new cage from this seed cell
		var cage_cells: Array[int] = [start]
		var cage_values: Dictionary = {}
		cage_values[solution[start]] = true
		cell_cage[start] = cages.size()

		var target_size := rng.randi_range(MIN_CAGE_SIZE, MAX_CAGE_SIZE)

		# Frontier: unassigned orthogonal neighbours of the growing cage
		var frontier: Array[int] = _unassigned_neighbors(start, cell_cage)
		_shuffle_array(frontier, rng)

		while cage_cells.size() < target_size and not frontier.is_empty():
			var next: int = frontier.pop_front()
			if cell_cage[next] != -1:
				continue
			var val: int = solution[next]
			if cage_values.has(val):
				continue  # Would introduce a duplicate digit

			cage_cells.append(next)
			cage_values[val] = true
			cell_cage[next] = cages.size()

			# Add newly reachable unassigned neighbours to the frontier
			for nb in _unassigned_neighbors(next, cell_cage):
				if nb not in frontier:
					frontier.append(nb)
			_shuffle_array(frontier, rng)

		# Finalise the cage
		if cage_cells.size() < MIN_CAGE_SIZE:
			# Too small — try to merge with an adjacent cage that won't get duplicates
			var merged := _try_merge_into_neighbor(start, cage_cells, cages, cell_cage, solution)
			if not merged:
				# Cannot merge — abort and retry the whole partition
				return []
			continue

		cages.append(_build_cage_dict(cage_cells, solution))

	return cages


## Attempt to merge a single orphan cell (or small cage) into an adjacent cage.
## Returns true on success, false if no valid merge exists.
static func _try_merge_into_neighbor(
		start: int,
		cage_cells: Array[int],
		cages: Array[Dictionary],
		cell_cage: Array[int],
		solution: Array[int]
) -> bool:
	# Collect candidate neighbour cages
	var neighbors := _orthogonal_neighbors(start)
	for nb in neighbors:
		if cell_cage[nb] < 0:
			continue
		var cage_idx: int = cell_cage[nb]
		var cage: Dictionary = cages[cage_idx]
		# Check that merging won't introduce duplicate digits
		var existing_values: Dictionary = {}
		for c in cage["cells"]:
			existing_values[solution[c]] = true
		var conflict := false
		for c in cage_cells:
			if existing_values.has(solution[c]):
				conflict = true
				break
		if conflict:
			continue
		# Merge
		for c in cage_cells:
			cage["cells"].append(c)
			cell_cage[c] = cage_idx
		# Recalculate sum and anchor
		cage["sum"] = 0
		cage["anchor"] = cage["cells"][0]
		for c in cage["cells"]:
			cage["sum"] += solution[c]
			if c < cage["anchor"]:
				cage["anchor"] = c
		return true
	return false


## Deterministic fallback: row-by-row pairs, no duplicate concern.
## Should only be reached if the random partition keeps failing (very unlikely).
static func _fallback_partition(solution: Array[int]) -> Array[Dictionary]:
	var cages: Array[Dictionary] = []
	var used: Array[bool] = []
	used.resize(81)
	used.fill(false)

	for i in 81:
		if used[i]:
			continue
		# Pair with the right neighbour if available, else go solo
		var col := i % 9
		if col < 8 and not used[i + 1] and solution[i] != solution[i + 1]:
			cages.append(_build_cage_dict([i, i + 1], solution))
			used[i] = true
			used[i + 1] = true
		else:
			# Isolated cell — make a size-1 cage (not ideal but valid)
			cages.append(_build_cage_dict([i], solution))
			used[i] = true

	return cages


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _build_cage_dict(cells: Array, solution: Array[int]) -> Dictionary:
	var cage_sum := 0
	var anchor: int = cells[0]
	for c in cells:
		cage_sum += solution[c]
		if c < anchor:
			anchor = c
	return {
		"cells": cells.duplicate(),
		"sum": cage_sum,
		"anchor": anchor,
	}


static func _unassigned_neighbors(index: int, cell_cage: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for nb in _orthogonal_neighbors(index):
		if cell_cage[nb] == -1:
			result.append(nb)
	return result


static func _orthogonal_neighbors(index: int) -> Array[int]:
	var result: Array[int] = []
	var row := index / 9
	var col := index % 9
	if row > 0:
		result.append((row - 1) * 9 + col)
	if row < 8:
		result.append((row + 1) * 9 + col)
	if col > 0:
		result.append(row * 9 + col - 1)
	if col < 8:
		result.append(row * 9 + col + 1)
	return result


static func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
