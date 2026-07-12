class_name SudokuGenerator
extends RefCounted

## Seed grid - a known valid complete Sudoku
const SEED_GRID: Array[int] = [
	5, 3, 4, 6, 7, 8, 9, 1, 2,
	6, 7, 2, 1, 9, 5, 3, 4, 8,
	1, 9, 8, 3, 4, 2, 5, 6, 7,
	8, 5, 9, 7, 6, 1, 4, 2, 3,
	4, 2, 6, 8, 5, 3, 7, 9, 1,
	7, 1, 3, 9, 2, 4, 8, 5, 6,
	9, 6, 1, 5, 3, 7, 2, 8, 4,
	2, 8, 7, 4, 1, 9, 6, 3, 5,
	3, 4, 5, 2, 8, 6, 1, 7, 9,
]

## Target clue counts per difficulty (approximate, will adjust during generation)
const CLUE_TARGETS := {
	SudokuSolver.Difficulty.EASY: 38,
	SudokuSolver.Difficulty.MEDIUM: 32,
	SudokuSolver.Difficulty.HARD: 28,
	SudokuSolver.Difficulty.EXPERT: 25,
	SudokuSolver.Difficulty.EVIL: 22,
}

## Max attempts before giving up on a difficulty and retrying
const MAX_ATTEMPTS := 10


## Generate a puzzle of the requested difficulty.
## Returns a dictionary with "puzzle" (Array[int]) and "solution" (Array[int]).
## Pass a non-empty constraints Array to generate Anti-Knight (or other variant) puzzles.
func generate(difficulty: SudokuSolver.Difficulty, seed: int = -1, constraints: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	for attempt in MAX_ATTEMPTS:
		var full_grid: Array[int]
		if constraints.is_empty():
			full_grid = _generate_full_grid(rng)
		else:
			full_grid = _generate_full_grid_constrained(rng, constraints)
			if full_grid.is_empty():
				continue
		var puzzle := _remove_cells_constrained(full_grid, difficulty, rng, constraints)
		if puzzle.is_empty():
			continue

		# For easy/medium, skip the expensive difficulty analysis and just accept
		if difficulty <= SudokuSolver.Difficulty.MEDIUM and constraints.is_empty():
			return {
				"puzzle": puzzle,
				"solution": full_grid,
				"difficulty": difficulty,
			}

		var solutions := SudokuSolver.solve_brute_force(puzzle, 2, constraints)
		if solutions.size() == 1:
			return {
				"puzzle": puzzle,
				"solution": solutions[0],
				"difficulty": difficulty,
			}

	# Fallback: return whatever we can produce (best-effort, may not hit exact difficulty)
	var fallback_full_grid: Array[int]
	if constraints.is_empty():
		fallback_full_grid = _generate_full_grid(rng)
	else:
		fallback_full_grid = _generate_full_grid_constrained(rng, constraints)
		# _generate_full_grid_constrained always succeeds for satisfiable constraints, but
		# guard defensively — if it somehow fails there is nothing valid to return.
		if fallback_full_grid.is_empty():
			return {}
	var fallback_puzzle := _remove_cells_constrained(fallback_full_grid, difficulty, rng, constraints)
	if fallback_puzzle.is_empty():
		fallback_puzzle = _simple_remove_constrained(fallback_full_grid, CLUE_TARGETS[difficulty], rng, constraints)
	var fallback_solutions := SudokuSolver.solve_brute_force(fallback_puzzle, 2, constraints)
	return {
		"puzzle": fallback_puzzle,
		"solution": fallback_solutions[0] if fallback_solutions.size() >= 1 else fallback_full_grid,
		"difficulty": difficulty,
	}


## Generate a complete valid grid by transforming the seed
func _generate_full_grid(rng: RandomNumberGenerator) -> Array[int]:
	var grid: Array[int] = []
	grid.assign(SEED_GRID.duplicate())

	# Shuffle digits (relabel)
	var digits := [1, 2, 3, 4, 5, 6, 7, 8, 9]
	_shuffle_array(digits, rng)
	var mapping := {}
	for i in 9:
		mapping[i + 1] = digits[i]
	for i in 81:
		grid[i] = mapping[grid[i]]

	# Shuffle rows within each band
	for band in 3:
		var rows := [band * 3, band * 3 + 1, band * 3 + 2]
		_shuffle_array(rows, rng)
		var new_grid: Array[int] = []
		new_grid.resize(81)
		for i in 3:
			for c in 9:
				# This band's rows get rearranged
				pass
		# Rebuild the band
		_shuffle_rows_in_band(grid, band, rng)

	# Shuffle columns within each stack
	for stack in 3:
		_shuffle_cols_in_stack(grid, stack, rng)

	# Shuffle bands (groups of 3 rows)
	var band_order := [0, 1, 2]
	_shuffle_array(band_order, rng)
	grid = _reorder_bands(grid, band_order)

	# Shuffle stacks (groups of 3 columns)
	var stack_order := [0, 1, 2]
	_shuffle_array(stack_order, rng)
	grid = _reorder_stacks(grid, stack_order)

	return grid


func _shuffle_rows_in_band(grid: Array[int], band: int, rng: RandomNumberGenerator) -> void:
	var rows := [0, 1, 2]
	_shuffle_array(rows, rng)
	var temp: Array[Array] = [[], [], []]
	for i in 3:
		var src_row := band * 3 + i
		for c in 9:
			temp[i].append(grid[src_row * 9 + c])
	for i in 3:
		var dst_row := band * 3 + i
		for c in 9:
			grid[dst_row * 9 + c] = temp[rows[i]][c]


func _shuffle_cols_in_stack(grid: Array[int], stack: int, rng: RandomNumberGenerator) -> void:
	var cols := [0, 1, 2]
	_shuffle_array(cols, rng)
	var temp: Array[Array] = [[], [], []]
	for i in 3:
		var src_col := stack * 3 + i
		for r in 9:
			temp[i].append(grid[r * 9 + src_col])
	for i in 3:
		var dst_col := stack * 3 + i
		for r in 9:
			grid[r * 9 + dst_col] = temp[cols[i]][r]


func _reorder_bands(grid: Array[int], order: Array) -> Array[int]:
	var new_grid: Array[int] = []
	new_grid.resize(81)
	for i in 3:
		var src_band: int = order[i]
		for r in 3:
			for c in 9:
				new_grid[(i * 3 + r) * 9 + c] = grid[(src_band * 3 + r) * 9 + c]
	return new_grid


func _reorder_stacks(grid: Array[int], order: Array) -> Array[int]:
	var new_grid: Array[int] = []
	new_grid.resize(81)
	for i in 3:
		var src_stack: int = order[i]
		for c in 3:
			for r in 9:
				new_grid[r * 9 + (i * 3 + c)] = grid[r * 9 + (src_stack * 3 + c)]
	return new_grid


## Remove cells to create a puzzle, ensuring unique solution and target difficulty
func _remove_cells(full_grid: Array[int], target_difficulty: SudokuSolver.Difficulty, rng: RandomNumberGenerator) -> Array[int]:
	return _remove_cells_constrained(full_grid, target_difficulty, rng, [])


## Constraint-aware version of _remove_cells.
func _remove_cells_constrained(full_grid: Array[int], target_difficulty: SudokuSolver.Difficulty, rng: RandomNumberGenerator, constraints: Array) -> Array[int]:
	var puzzle: Array[int] = []
	puzzle.assign(full_grid.duplicate())
	# Constrained puzzles are naturally harder at the same clue count; add a few extra
	# clues to keep them playable at each tier.
	var target_clues: int = CLUE_TARGETS[target_difficulty]
	if not constraints.is_empty():
		target_clues += 3

	# Create a random removal order
	var indices := range(81)
	_shuffle_array(indices, rng)

	var removed_count := 0
	for idx in indices:
		if puzzle[idx] == 0:
			continue

		var backup: int = puzzle[idx]
		puzzle[idx] = 0
		removed_count += 1

		# Check unique solution (constraint-aware)
		var solutions := SudokuSolver.solve_brute_force(puzzle, 2, constraints)
		if solutions.size() != 1:
			puzzle[idx] = backup
			removed_count -= 1
			continue

		var clues_remaining := 81 - removed_count
		if clues_remaining <= target_clues:
			break

	return puzzle


## Simple fallback: just remove random cells without difficulty targeting
func _simple_remove(full_grid: Array[int], target_clues: int, rng: RandomNumberGenerator) -> Array[int]:
	return _simple_remove_constrained(full_grid, target_clues, rng, [])


## Constraint-aware version of _simple_remove.
func _simple_remove_constrained(full_grid: Array[int], target_clues: int, rng: RandomNumberGenerator, constraints: Array) -> Array[int]:
	var puzzle: Array[int] = []
	puzzle.assign(full_grid.duplicate())
	var indices := range(81)
	_shuffle_array(indices, rng)

	var removed := 0
	for idx in indices:
		if puzzle[idx] == 0:
			continue
		var backup: int = puzzle[idx]
		puzzle[idx] = 0
		removed += 1
		var solutions := SudokuSolver.solve_brute_force(puzzle, 2, constraints)
		if solutions.size() != 1:
			puzzle[idx] = backup
			removed -= 1
			continue
		if 81 - removed <= target_clues:
			break

	return puzzle


## Generate a complete valid grid that satisfies extra constraints by randomised
## constraint-aware backtracking.  Returns an empty array only if the constraints
## are unsatisfiable (which is never true for Anti-Knight on a 9x9 grid).
func _generate_full_grid_constrained(rng: RandomNumberGenerator, constraints: Array) -> Array[int]:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	if _backtrack_fill(grid, 0, rng, constraints):
		return grid
	return []


## Recursively fill grid from cell pos onward, trying digits in a shuffled order
## so every call with a fresh rng state produces a distinct random grid.
func _backtrack_fill(grid: Array[int], pos: int, rng: RandomNumberGenerator, constraints: Array) -> bool:
	while pos < 81 and grid[pos] != 0:
		pos += 1
	if pos == 81:
		return true

	var digits: Array = [1, 2, 3, 4, 5, 6, 7, 8, 9]
	_shuffle_array(digits, rng)

	for d: int in digits:
		if SudokuSolver.is_valid_placement_constrained(grid, pos, d, constraints):
			grid[pos] = d
			if _backtrack_fill(grid, pos + 1, rng, constraints):
				return true
			grid[pos] = 0

	return false


func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
