class_name KillerCagePartitioner
extends RefCounted

const GRID_CELLS := 81
const MAX_ATTEMPTS := 40
const MAX_SHAPE_CANDIDATES := 14
const DIFFICULTY_SIZE_WEIGHTS := {
	SudokuSolver.Difficulty.EASY: {2: 6, 3: 4},
	SudokuSolver.Difficulty.MEDIUM: {2: 4, 3: 4, 4: 2},
	SudokuSolver.Difficulty.HARD: {2: 2, 3: 3, 4: 3, 5: 2},
	SudokuSolver.Difficulty.EXPERT: {2: 1, 3: 2, 4: 4, 5: 4},
	SudokuSolver.Difficulty.EVIL: {2: 1, 3: 2, 4: 4, 5: 4},
}


static func partition(grid: Array[int], difficulty: int, seed: int = -1) -> Array:
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	return partition_with_rng(grid, difficulty, rng)


static func partition_with_rng(grid: Array[int], difficulty: int, rng: RandomNumberGenerator) -> Array:
	for _attempt in MAX_ATTEMPTS:
		var target_sizes := _build_target_sizes(difficulty, rng)
		target_sizes.sort()
		target_sizes.reverse()
		var available: Array[bool] = []
		available.resize(GRID_CELLS)
		available.fill(true)
		var cage_cells: Array = []
		var success := true
		for target_size in target_sizes:
			var placed := false
			for _shape_attempt in MAX_SHAPE_CANDIDATES * 3:
				var start := _pick_start_cell(available, rng, int(target_size))
				if start < 0:
					success = false
					break
				var cells := _grow_shape(start, int(target_size), available, rng)
				if cells.size() != int(target_size):
					continue
				for cell in cells:
					available[cell] = false
				if not _remaining_components_valid(available):
					for cell in cells:
						available[cell] = true
					continue
				var stored_cells: Array[int] = cells.duplicate()
				stored_cells.sort()
				cage_cells.append(stored_cells)
				placed = true
				break
			if not placed:
				success = false
				break
		if success and _all_cells_assigned(available):
			var cages: Array = []
			for cells in cage_cells:
				var cage_sum := 0
				for cell in cells:
					cage_sum += int(grid[cell])
				cages.append({
					"cells": cells,
					"sum": cage_sum,
				})
			return cages
	return _build_row_fallback(grid, difficulty)


static func _pick_start_cell(available: Array[bool], rng: RandomNumberGenerator, min_neighbors: int = 1) -> int:
	var remaining: Array[int] = []
	for index in available.size():
		if available[index]:
			var neighbor_count := 0
			for neighbor in _neighbors(index):
				if available[neighbor]:
					neighbor_count += 1
			if neighbor_count >= min_neighbors:
				remaining.append(index)
	if remaining.is_empty() and min_neighbors > 0:
		return _pick_start_cell(available, rng, min_neighbors - 1)
	if remaining.is_empty():
		return -1
	return remaining[rng.randi_range(0, remaining.size() - 1)]


static func _build_target_sizes(difficulty: int, rng: RandomNumberGenerator) -> Array[int]:
	var weights: Dictionary = DIFFICULTY_SIZE_WEIGHTS.get(difficulty, DIFFICULTY_SIZE_WEIGHTS[SudokuSolver.Difficulty.MEDIUM])
	var allowed_sizes: Array[int] = []
	for size in weights.keys():
		allowed_sizes.append(int(size))
	allowed_sizes.sort()
	var fill_cache: Dictionary = {}
	for _attempt in 20:
		var sizes: Array[int] = []
		var remaining := GRID_CELLS
		while remaining > 0:
			var size := _pick_weighted_size(weights, rng)
			if size > remaining:
				continue
			if not _can_fill_remaining(remaining - size, allowed_sizes, fill_cache):
				continue
			sizes.append(size)
			remaining -= size
		if remaining == 0:
			return sizes
	var fallback_sizes: Array[int] = []
	for _i in 27:
		fallback_sizes.append(3)
	return fallback_sizes


static func _pick_weighted_size(weights: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0
	for weight in weights.values():
		total += int(weight)
	var roll := rng.randi_range(1, total)
	var cumulative := 0
	for size in weights.keys():
		cumulative += int(weights[size])
		if roll <= cumulative:
			return int(size)
	return int(weights.keys()[0])


static func _can_fill_remaining(remaining: int, allowed_sizes: Array[int], cache: Dictionary) -> bool:
	if remaining == 0:
		return true
	if remaining < 0:
		return false
	if cache.has(remaining):
		return bool(cache[remaining])
	for size in allowed_sizes:
		if _can_fill_remaining(remaining - size, allowed_sizes, cache):
			cache[remaining] = true
			return true
	cache[remaining] = false
	return false


static func _grow_shape(start: int, target_size: int, available: Array[bool], rng: RandomNumberGenerator) -> Array[int]:
	var shape: Array[int] = [start]
	var in_shape := {start: true}
	while shape.size() < target_size:
		var frontier := _collect_frontier(shape, available, in_shape)
		if frontier.is_empty():
			return []
		var next := int(frontier[rng.randi_range(0, frontier.size() - 1)])
		shape.append(next)
		in_shape[next] = true
	return shape


static func _collect_frontier(shape: Array[int], available: Array[bool], in_shape: Dictionary) -> Array[int]:
	var frontier: Array[int] = []
	var seen: Dictionary = {}
	for cell in shape:
		for neighbor in _neighbors(cell):
			if available[neighbor] and not in_shape.has(neighbor) and not seen.has(neighbor):
				frontier.append(neighbor)
				seen[neighbor] = true
	return frontier


static func _remaining_components_valid(available: Array[bool]) -> bool:
	var visited: Dictionary = {}
	for index in available.size():
		if not available[index] or visited.has(index):
			continue
		var size := 0
		var stack: Array[int] = [index]
		visited[index] = true
		while not stack.is_empty():
			var cell := int(stack.pop_back())
			size += 1
			for neighbor in _neighbors(cell):
				if available[neighbor] and not visited.has(neighbor):
					visited[neighbor] = true
					stack.append(neighbor)
		if size == 1:
			return false
	return true


static func _neighbors(index: int) -> Array[int]:
	var row := index / 9
	var col := index % 9
	var neighbors: Array[int] = []
	if row > 0:
		neighbors.append(index - 9)
	if row < 8:
		neighbors.append(index + 9)
	if col > 0:
		neighbors.append(index - 1)
	if col < 8:
		neighbors.append(index + 1)
	return neighbors


static func _all_cells_assigned(available: Array[bool]) -> bool:
	for is_available in available:
		if is_available:
			return false
	return true


static func _build_row_fallback(grid: Array[int], difficulty: int) -> Array:
	var patterns := {
		SudokuSolver.Difficulty.EASY: [[3, 3, 3]],
		SudokuSolver.Difficulty.MEDIUM: [[2, 3, 4], [4, 3, 2]],
		SudokuSolver.Difficulty.HARD: [[4, 5], [2, 2, 5], [5, 4]],
		SudokuSolver.Difficulty.EXPERT: [[5, 4], [4, 5], [2, 2, 5]],
		SudokuSolver.Difficulty.EVIL: [[5, 4], [4, 5], [2, 2, 5]],
	}
	var row_patterns: Array = patterns.get(difficulty, patterns[SudokuSolver.Difficulty.MEDIUM])
	var cages: Array = []
	for row in 9:
		var pattern: Array = row_patterns[row % row_patterns.size()]
		var col := 0
		for size in pattern:
			var cells: Array[int] = []
			var cage_sum := 0
			for offset in int(size):
				var index := row * 9 + col + offset
				cells.append(index)
				cage_sum += int(grid[index])
			cages.append({
				"cells": cells,
				"sum": cage_sum,
			})
			col += int(size)
	return cages

