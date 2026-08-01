class_name SudokuGenerator
extends RefCounted

## Seed grid - a known valid complete 9×9 Sudoku
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

## Seed grid - a known valid complete 6×6 Mini Sudoku (2×3 regions)
const SEED_GRID_6X6: Array[int] = [
	1, 2, 3, 4, 5, 6,
	4, 5, 6, 1, 2, 3,
	2, 3, 1, 5, 6, 4,
	5, 6, 4, 2, 3, 1,
	3, 1, 2, 6, 4, 5,
	6, 4, 5, 3, 1, 2,
]

## Target clue counts per difficulty (approximate, will adjust during generation)
const CLUE_TARGETS := {
	SudokuSolver.Difficulty.EASY: 38,
	SudokuSolver.Difficulty.MEDIUM: 32,
	SudokuSolver.Difficulty.HARD: 28,
	SudokuSolver.Difficulty.EXPERT: 25,
	SudokuSolver.Difficulty.EVIL: 22,
}

## Target clue counts for 6×6 Mini Sudoku (single quick-play difficulty = EASY tier)
const CLUE_TARGETS_6X6 := {
	SudokuSolver.Difficulty.EASY: 14,
}

## Max attempts before giving up on a difficulty and retrying
const MAX_ATTEMPTS := 10

## Max attempts to find a digit relabelling that satisfies active constraints
const MAX_RELABEL_ATTEMPTS := 8


## Generate a puzzle of the requested difficulty.
## Returns a dictionary with "puzzle" (Array[int]) and "solution" (Array[int]).
## Pass a non-empty constraints array for variant-aware generation; an empty
## array produces standard Sudoku behaviour.
## Pass spec to use a non-9×9 grid; defaults to standard_9×9 when null.
func generate(difficulty: SudokuSolver.Difficulty, seed: int = -1, constraints: Array = [], spec: SudokuGridSpec = null) -> Dictionary:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	for attempt in MAX_ATTEMPTS:
		var full_grid := _generate_full_grid(rng, constraints, s)
		if full_grid.is_empty():
			# Constraints are unsatisfiable — no valid grid exists, fail fast.
			return {}
		var puzzle := _remove_cells(full_grid, difficulty, rng, constraints, Callable(), s)
		if puzzle.is_empty():
			continue

		# For easy/medium on standard-sized grids, skip the expensive difficulty
		# analysis and just accept. Mini 6×6 is cheap to analyze, and uniqueness
		# verification is required to enforce human-logic solvability.
		if difficulty <= SudokuSolver.Difficulty.MEDIUM and s.id != "mini_6x6":
			return {
				"puzzle": puzzle,
				"solution": full_grid,
				"difficulty": difficulty,
			}

		var solver := SudokuSolver.new()
		solver.analyze(puzzle, constraints, s)

		# Mini 6×6 additionally requires a human-logic-only solution (no guessing).
		var acceptable: bool = solver.is_unique
		if s.id == "mini_6x6":
			acceptable = acceptable and solver.is_logic_solvable
		if acceptable:
			return {
				"puzzle": puzzle,
				"solution": solver.solution,
				"difficulty": difficulty,
			}

	# Fallback: return whatever we get closest to
	var fallback_full_grid := _generate_full_grid(rng, constraints, s)
	if fallback_full_grid.is_empty():
		# Constraints are unsatisfiable — signal failure to caller.
		return {}
	var fallback_puzzle := _remove_cells(fallback_full_grid, difficulty, rng, constraints, Callable(), s)
	if fallback_puzzle.is_empty():
		var clue_targets := CLUE_TARGETS_6X6 if s.id == "mini_6x6" else CLUE_TARGETS
		var simple_target: int = clue_targets.get(difficulty, clue_targets[SudokuSolver.Difficulty.EASY]) + (3 if not constraints.is_empty() else 0)
		fallback_puzzle = _simple_remove(fallback_full_grid, simple_target, rng, constraints, s)
	var fallback_solver := SudokuSolver.new()
	fallback_solver.analyze(fallback_puzzle, constraints, s)
	return {
		"puzzle": fallback_puzzle,
		"solution": fallback_solver.solution if fallback_solver.is_unique else fallback_full_grid,
		"difficulty": fallback_solver.difficulty,
	}


## Generate a complete valid grid by transforming the seed.
## For 6×6 grids, uses the 6×6 seed grid and adapts shuffling to 2×3 regions.
## When constraints are active, the transformation-based grid is validated
## against them. Spatial constraints may be violated by row/column shuffles;
## if so, brute-force fills an empty grid instead.
func _generate_full_grid(rng: RandomNumberGenerator, constraints: Array = [], spec: SudokuGridSpec = null) -> Array[int]:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var seed_src: Array[int] = SEED_GRID_6X6 if s.id == "mini_6x6" else SEED_GRID
	var grid: Array[int] = []
	grid.assign(seed_src.duplicate())

	# Shuffle digits (relabel)
	var sym_count := s.sym_max - s.sym_min + 1
	var digits: Array[int] = []
	for i in sym_count:
		digits.append(s.sym_min + i)
	_shuffle_array(digits, rng)
	var mapping := {}
	for i in sym_count:
		mapping[s.sym_min + i] = digits[i]
	for i in s.cell_count:
		grid[i] = mapping[grid[i]]

	# Shuffle rows within each band (each band is region_h rows tall)
	var num_bands := s.size / s.region_h
	for band in num_bands:
		_shuffle_rows_in_band(grid, band, rng, s)

	# Shuffle columns within each stack (each stack is region_w cols wide)
	var num_stacks := s.size / s.region_w
	for stack in num_stacks:
		_shuffle_cols_in_stack(grid, stack, rng, s)

	# Shuffle bands (groups of region_h rows)
	var band_order: Array[int] = []
	for i in num_bands:
		band_order.append(i)
	_shuffle_array(band_order, rng)
	grid = _reorder_bands(grid, band_order, s)

	# Shuffle stacks (groups of region_w columns)
	var stack_order: Array[int] = []
	for i in num_stacks:
		stack_order.append(i)
	_shuffle_array(stack_order, rng)
	grid = _reorder_stacks(grid, stack_order, s)

	# When constraints are active, verify the transformed grid satisfies them.
	# Spatial transformations (row/column/band/stack shuffles) can violate
	# positional constraints (e.g. Anti-Knight). If so, fall back to brute-force
	# on an empty grid and re-apply a random digit relabelling for variety.
	if not constraints.is_empty() and not SudokuSolver.is_complete_grid_valid(grid, constraints, s):
		var empty: Array[int] = []
		empty.resize(s.cell_count)
		empty.fill(0)
		var solutions := SudokuSolver.solve_brute_force(empty, 1, constraints, Callable(), s)
		if solutions.is_empty():
			# Constraints are unsatisfiable — propagate failure as empty array.
			var failure: Array[int] = []
			return failure
		var base_solution: Array[int] = solutions[0]
		# Try a random digit relabelling for variety. Value-sensitive
		# constraints (e.g. cage sums) are not invariant under arbitrary
		# bijections, so we validate each attempt and retry up to 8 times.
		# If no relabelling satisfies the constraints, use the raw solution.
		var relabel_digits: Array[int] = []
		for i in sym_count:
			relabel_digits.append(s.sym_min + i)
		var found_relabel := false
		for _r in MAX_RELABEL_ATTEMPTS:
			_shuffle_array(relabel_digits, rng)
			var relabel_map := {}
			for i in sym_count:
				relabel_map[s.sym_min + i] = relabel_digits[i]
			var candidate: Array[int] = base_solution.duplicate()
			for i in s.cell_count:
				candidate[i] = relabel_map[candidate[i]]
			if SudokuSolver.is_complete_grid_valid(candidate, constraints, s):
				grid = candidate
				found_relabel = true
				break
		if not found_relabel:
			grid = base_solution

	return grid


func _shuffle_rows_in_band(grid: Array[int], band: int, rng: RandomNumberGenerator, spec: SudokuGridSpec = null) -> void:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var n := s.size
	var rh := s.region_h
	var rows: Array[int] = []
	for i in rh:
		rows.append(i)
	_shuffle_array(rows, rng)
	var temp: Array[Array] = []
	for i in rh:
		temp.append([])
		var src_row := band * rh + i
		for c in n:
			temp[i].append(grid[src_row * n + c])
	for i in rh:
		var dst_row := band * rh + i
		for c in n:
			grid[dst_row * n + c] = temp[rows[i]][c]


func _shuffle_cols_in_stack(grid: Array[int], stack: int, rng: RandomNumberGenerator, spec: SudokuGridSpec = null) -> void:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var n := s.size
	var rw := s.region_w
	var cols: Array[int] = []
	for i in rw:
		cols.append(i)
	_shuffle_array(cols, rng)
	var temp: Array[Array] = []
	for i in rw:
		temp.append([])
		var src_col := stack * rw + i
		for r in n:
			temp[i].append(grid[r * n + src_col])
	for i in rw:
		var dst_col := stack * rw + i
		for r in n:
			grid[r * n + dst_col] = temp[cols[i]][r]


func _reorder_bands(grid: Array[int], order: Array, spec: SudokuGridSpec = null) -> Array[int]:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var n := s.size
	var rh := s.region_h
	var num_bands := n / rh
	var new_grid: Array[int] = []
	new_grid.resize(s.cell_count)
	for i in num_bands:
		var src_band: int = order[i]
		for r in rh:
			for c in n:
				new_grid[(i * rh + r) * n + c] = grid[(src_band * rh + r) * n + c]
	return new_grid


func _reorder_stacks(grid: Array[int], order: Array, spec: SudokuGridSpec = null) -> Array[int]:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var n := s.size
	var rw := s.region_w
	var num_stacks := n / rw
	var new_grid: Array[int] = []
	new_grid.resize(s.cell_count)
	for i in num_stacks:
		var src_stack: int = order[i]
		for c in rw:
			for r in n:
				new_grid[r * n + (i * rw + c)] = grid[r * n + (src_stack * rw + c)]
	return new_grid


## Remove cells to create a puzzle, ensuring unique solution and target difficulty.
## Pass constraints to verify uniqueness under variant rules.
## Constrained variants target 3 more clues so difficulty tiers remain
## comparable to standard Sudoku despite the additional constraint.
## Pass [param cancel_check] to allow cooperative cancellation during the removal loop.
## Pass spec to use a non-9×9 grid; defaults to standard_9×9 when null.
func _remove_cells(full_grid: Array[int], target_difficulty: SudokuSolver.Difficulty, rng: RandomNumberGenerator, constraints: Array = [], cancel_check: Callable = Callable(), spec: SudokuGridSpec = null) -> Array[int]:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var clue_targets := CLUE_TARGETS_6X6 if s.id == "mini_6x6" else CLUE_TARGETS
	var diff_key := target_difficulty if clue_targets.has(target_difficulty) else SudokuSolver.Difficulty.EASY
	var puzzle: Array[int] = []
	puzzle.assign(full_grid.duplicate())
	var target_clues: int = clue_targets[diff_key]
	if not constraints.is_empty():
		target_clues += 3

	# Create a random removal order
	var indices := range(s.cell_count)
	_shuffle_array(indices, rng)

	var removed_count := 0
	for idx in indices:
		if cancel_check.is_valid() and cancel_check.call():
			return []

		if puzzle[idx] == 0:
			continue

		var backup: int = puzzle[idx]
		puzzle[idx] = 0
		removed_count += 1

		# Check unique solution
		var solutions := SudokuSolver.solve_brute_force(puzzle, 2, constraints, cancel_check, s)
		if cancel_check.is_valid() and cancel_check.call():
			return []
		if solutions.size() != 1:
			puzzle[idx] = backup
			removed_count -= 1
			continue

		var clues_remaining := s.cell_count - removed_count
		if clues_remaining <= target_clues:
			break

	return puzzle


## Simple fallback: just remove random cells without difficulty targeting.
## Pass spec to use a non-9×9 grid; defaults to standard_9×9 when null.
func _simple_remove(full_grid: Array[int], target_clues: int, rng: RandomNumberGenerator, constraints: Array = [], spec: SudokuGridSpec = null) -> Array[int]:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var puzzle: Array[int] = []
	puzzle.assign(full_grid.duplicate())
	var indices := range(s.cell_count)
	_shuffle_array(indices, rng)

	var removed := 0
	for idx in indices:
		if puzzle[idx] == 0:
			continue
		var backup: int = puzzle[idx]
		puzzle[idx] = 0
		removed += 1
		var solutions := SudokuSolver.solve_brute_force(puzzle, 2, constraints, Callable(), s)
		if solutions.size() != 1:
			puzzle[idx] = backup
			removed -= 1
			continue
		if s.cell_count - removed <= target_clues:
			break

	return puzzle


func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
