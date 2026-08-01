class_name SudokuSolver
extends RefCounted

## Solving techniques used, ordered by difficulty
enum Technique {
	NAKED_SINGLE,
	HIDDEN_SINGLE,
	NAKED_PAIR,
	NAKED_TRIPLE,
	HIDDEN_PAIR,
	HIDDEN_TRIPLE,
	POINTING_PAIR,
	BOX_LINE_REDUCTION,
	X_WING,
	SWORDFISH,
	XY_WING,
}

## Difficulty thresholds based on techniques required
enum Difficulty {
	EASY,
	MEDIUM,
	HARD,
	EXPERT,
	EVIL,
}

## Result of a solve attempt
var solution: Array[int] = []
var is_unique: bool = false
## True when the puzzle can be completed using logic techniques alone (no guessing).
## Set by analyze(); remains false until analyze() is called.
var is_logic_solvable: bool = false
var techniques_used: Array[Technique] = []
var difficulty: Difficulty = Difficulty.EASY

## Optional constraints evaluated during solving and uniqueness checks.
## Set before calling analyze() to enable variant-aware analysis.
var constraints: Array = []


## Check if placing val at index is valid in the grid.
## Pass a non-empty constraints array to enforce variant rules in addition to
## the standard row/column/box checks.
## Pass spec to use a non-9×9 grid; defaults to standard_9×9 when null.
static func is_valid_placement(grid: Array[int], index: int, val: int, constraints: Array = [], spec: SudokuGridSpec = null) -> bool:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var n := s.size
	var row := index / n
	var col := index % n
	var box_row := (row / s.region_h) * s.region_h
	var box_col := (col / s.region_w) * s.region_w
	var box_cells := s.region_h * s.region_w

	for i in n:
		# Check row
		if grid[row * n + i] == val:
			return false
		# Check column
		if grid[i * n + col] == val:
			return false

	# Check region (box)
	for i in box_cells:
		var br := box_row + i / s.region_w
		var bc := box_col + i % s.region_w
		if grid[br * n + bc] == val:
			return false

	for c in constraints:
		if not c.is_valid(grid, index, val):
			return false
	return true


## Get all candidates for a cell.
## Pass spec to use a non-9×9 grid; defaults to standard_9×9 when null.
static func get_candidates(grid: Array[int], index: int, constraints: Array = [], spec: SudokuGridSpec = null) -> Array[int]:
	if grid[index] != 0:
		return []
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var candidates: Array[int] = []
	for val in range(s.sym_min, s.sym_max + 1):
		if is_valid_placement(grid, index, val, constraints, s):
			candidates.append(val)
	return candidates


## Brute-force solve using backtracking with MRV heuristic. Returns number of solutions found (stops at max_solutions).
## Pass [param cancel_check] to allow cooperative cancellation: the callable is polled at the
## start of each recursive call and returns [code]true[/code] when the caller wants to abort.
## Pass spec to use a non-9×9 grid; defaults to standard_9×9 when null.
static func solve_brute_force(grid: Array[int], max_solutions: int = 2, constraints: Array = [], cancel_check: Callable = Callable(), spec: SudokuGridSpec = null) -> Array[Array]:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	# Validate any pre-filled cells (givens) before entering backtracking.
	# A constraint-invalid given can never be part of a valid solution, so
	# skip the entire search rather than enumerating all completions.
	if not constraints.is_empty():
		for i in s.cell_count:
			if grid[i] != 0:
				var val := grid[i]
				grid[i] = 0
				var ok := is_valid_placement(grid, i, val, constraints, s)
				grid[i] = val
				if not ok:
					return []
	var solutions: Array[Array] = []
	var work := grid.duplicate()
	# Validate the callable once here; pass the result as a plain bool to avoid
	# repeated is_valid() calls inside the recursive backtracking hot path.
	_backtrack_mrv(work, solutions, max_solutions, constraints, cancel_check, cancel_check.is_valid(), s)
	return solutions


static func _find_mrv_cell(grid: Array[int], constraints: Array = [], spec: SudokuGridSpec = null) -> int:
	## Find the empty cell with the fewest candidates (MRV heuristic)
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var best_pos := -1
	var best_count := s.sym_max + 1
	for i in s.cell_count:
		if grid[i] != 0:
			continue
		var count := 0
		for v in range(s.sym_min, s.sym_max + 1):
			if is_valid_placement(grid, i, v, constraints, s):
				count += 1
		if count == 0:
			return -2  # Dead end — no candidates
		if count < best_count:
			best_count = count
			best_pos = i
			if count == 1:
				break  # Can't do better than 1
	return best_pos


## Returns false if any filled cell in a complete grid violates constraints.
## Temporarily clears each cell to evaluate placement validity against the
## remaining grid, which is the same test the backtracking solver uses during fill.
## Always returns true when constraints is empty (standard Sudoku path).
static func is_complete_grid_valid(grid: Array[int], constraints: Array, spec: SudokuGridSpec = null) -> bool:
	if constraints.is_empty():
		return true
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	for i in s.cell_count:
		if grid[i] == 0:
			continue
		var val := grid[i]
		grid[i] = 0
		var ok := is_valid_placement(grid, i, val, constraints, s)
		grid[i] = val
		if not ok:
			return false
	return true


static func _backtrack_mrv(grid: Array[int], solutions: Array[Array], max_solutions: int, constraints: Array = [], cancel_check: Callable = Callable(), do_cancel: bool = false, spec: SudokuGridSpec = null) -> void:
	if solutions.size() >= max_solutions:
		return
	if do_cancel and cancel_check.call():
		return  # Cooperative cancellation

	var pos := _find_mrv_cell(grid, constraints, spec)
	if pos == -1:
		# No empty cells - validate all filled cells (including givens) against
		# constraints before recording this as a solution.
		if is_complete_grid_valid(grid, constraints, spec):
			solutions.append(grid.duplicate())
		return
	if pos == -2:
		# Dead end
		return

	var candidates := get_candidates(grid, pos, constraints, spec)
	for val in candidates:
		grid[pos] = val
		_backtrack_mrv(grid, solutions, max_solutions, constraints, cancel_check, do_cancel, spec)
		grid[pos] = 0
		if solutions.size() >= max_solutions:
			return
		if do_cancel and cancel_check.call():
			return


## Logic-based solve that tracks which techniques were needed.
## Returns true if the puzzle was fully solved using logic alone.
## Pass p_constraints to filter candidates and propagate constraint side-effects
## after each placement; an empty array reproduces standard behaviour.
## Pass p_spec to use a non-9×9 grid; defaults to standard_9×9 when null.
func solve_logic(grid: Array[int], p_constraints: Array = [], p_spec: SudokuGridSpec = null) -> bool:
	var s := p_spec if p_spec != null else SudokuGridSpec.STANDARD_9X9
	techniques_used.clear()
	# Validate any pre-filled cells (givens) against constraints before solving.
	# An invalid given means no solution can exist.
	if not p_constraints.is_empty():
		for i in s.cell_count:
			if grid[i] != 0:
				var val := grid[i]
				grid[i] = 0
				var ok := is_valid_placement(grid, i, val, p_constraints, s)
				grid[i] = val
				if not ok:
					return false
	var candidates: Array[Array] = []
	candidates.resize(s.cell_count)
	# Initialize candidates respecting any active constraints
	for i in s.cell_count:
		if grid[i] == 0:
			candidates[i] = get_candidates(grid, i, p_constraints, s)
		else:
			candidates[i] = []

	var progress := true
	while progress:
		progress = false

		# Naked singles
		for i in s.cell_count:
			if grid[i] == 0 and candidates[i].size() == 1:
				var placed_val: int = candidates[i][0]
				grid[i] = placed_val
				_update_candidates_after_placement(candidates, grid, i, placed_val, p_constraints, s)
				candidates[i] = []
				progress = true
				if not Technique.NAKED_SINGLE in techniques_used:
					techniques_used.append(Technique.NAKED_SINGLE)

		if progress:
			continue

		# Hidden singles
		if _apply_hidden_singles(grid, candidates, p_constraints, s):
			progress = true
			continue

		# Naked pairs
		if _apply_naked_pairs(grid, candidates, s):
			progress = true
			continue

		# Naked triples
		if _apply_naked_triples(grid, candidates, s):
			progress = true
			continue

		# Hidden pairs
		if _apply_hidden_pairs(grid, candidates, s):
			progress = true
			continue

		# Pointing pairs / box-line reduction
		if _apply_pointing_pairs(grid, candidates, s):
			progress = true
			continue

		# X-Wing
		if _apply_x_wing(grid, candidates, s):
			progress = true
			continue

	# Check if fully solved and the completed grid satisfies all constraints
	for i in s.cell_count:
		if grid[i] == 0:
			return false
	return is_complete_grid_valid(grid, p_constraints, s)


## Eliminate a value from candidates in the same row, column, and box
static func _eliminate_candidates(candidates: Array[Array], grid: Array[int], index: int, val: int, spec: SudokuGridSpec = null) -> void:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var n := s.size
	var row := index / n
	var col := index % n
	var box_row := (row / s.region_h) * s.region_h
	var box_col := (col / s.region_w) * s.region_w
	var box_cells := s.region_h * s.region_w

	for i in n:
		candidates[row * n + i].erase(val)
		candidates[i * n + col].erase(val)

	for i in box_cells:
		var br := box_row + i / s.region_w
		var bc := box_col + i % s.region_w
		candidates[br * n + bc].erase(val)


## Standard elimination plus re-evaluation of any cells linked by constraints.
## Constraint-affected cells are re-computed from scratch so that multi-value
## constraint effects (e.g. Anti-Knight neighbours) are handled correctly.
static func _update_candidates_after_placement(candidates: Array[Array], grid: Array[int], index: int, val: int, p_constraints: Array, spec: SudokuGridSpec = null) -> void:
	_eliminate_candidates(candidates, grid, index, val, spec)
	for c in p_constraints:
		for affected_idx in c.get_affected_indices(index):
			if grid[affected_idx] == 0:
				candidates[affected_idx] = get_candidates(grid, affected_idx, p_constraints, spec)


## Hidden singles: a value can only go in one place in a row/col/box
func _apply_hidden_singles(grid: Array[int], candidates: Array[Array], p_constraints: Array = [], spec: SudokuGridSpec = null) -> bool:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var found := false
	# Check each unit (row, col, box)
	for unit in _get_all_units(s):
		for val in range(s.sym_min, s.sym_max + 1):
			var positions: Array[int] = []
			for idx in unit:
				if grid[idx] == 0 and val in candidates[idx]:
					positions.append(idx)
			if positions.size() == 1:
				var idx := positions[0]
				grid[idx] = val
				_update_candidates_after_placement(candidates, grid, idx, val, p_constraints, s)
				candidates[idx] = []
				found = true
				if not Technique.HIDDEN_SINGLE in techniques_used:
					techniques_used.append(Technique.HIDDEN_SINGLE)
	return found


## Naked pairs: two cells in a unit with the same two candidates
func _apply_naked_pairs(grid: Array[int], candidates: Array[Array], spec: SudokuGridSpec = null) -> bool:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var found := false
	for unit in _get_all_units(s):
		var pairs: Array[int] = []
		for idx in unit:
			if candidates[idx].size() == 2:
				pairs.append(idx)
		for i in range(pairs.size()):
			for j in range(i + 1, pairs.size()):
				var a: int = pairs[i]
				var b: int = pairs[j]
				if candidates[a] == candidates[b]:
					var v1: int = candidates[a][0]
					var v2: int = candidates[a][1]
					for idx in unit:
						if idx != a and idx != b and grid[idx] == 0:
							var removed := false
							if v1 in candidates[idx]:
								candidates[idx].erase(v1)
								removed = true
							if v2 in candidates[idx]:
								candidates[idx].erase(v2)
								removed = true
							if removed:
								found = true
								if not Technique.NAKED_PAIR in techniques_used:
									techniques_used.append(Technique.NAKED_PAIR)
	return found


## Naked triples: three cells in a unit whose combined candidates are exactly 3 values
func _apply_naked_triples(grid: Array[int], candidates: Array[Array], spec: SudokuGridSpec = null) -> bool:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var found := false
	for unit in _get_all_units(s):
		var cells: Array[int] = []
		for idx in unit:
			if grid[idx] == 0 and candidates[idx].size() >= 2 and candidates[idx].size() <= 3:
				cells.append(idx)
		if cells.size() < 3:
			continue
		for i in range(cells.size()):
			for j in range(i + 1, cells.size()):
				for k in range(j + 1, cells.size()):
					var combined: Array[int] = []
					for v in candidates[cells[i]]:
						if not v in combined:
							combined.append(v)
					for v in candidates[cells[j]]:
						if not v in combined:
							combined.append(v)
					for v in candidates[cells[k]]:
						if not v in combined:
							combined.append(v)
					if combined.size() == 3:
						var a: int = cells[i]
						var b: int = cells[j]
						var c: int = cells[k]
						for idx in unit:
							if idx != a and idx != b and idx != c and grid[idx] == 0:
								for v in combined:
									if v in candidates[idx]:
										candidates[idx].erase(v)
										found = true
										if not Technique.NAKED_TRIPLE in techniques_used:
											techniques_used.append(Technique.NAKED_TRIPLE)
	return found


## Hidden pairs: two values that only appear in two cells in a unit
func _apply_hidden_pairs(grid: Array[int], candidates: Array[Array], spec: SudokuGridSpec = null) -> bool:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var found := false
	for unit in _get_all_units(s):
		for v1 in range(s.sym_min, s.sym_max + 1):
			for v2 in range(v1 + 1, s.sym_max + 1):
				var positions: Array[int] = []
				for idx in unit:
					if grid[idx] == 0 and (v1 in candidates[idx] or v2 in candidates[idx]):
						if v1 in candidates[idx] and v2 in candidates[idx]:
							positions.append(idx)
				if positions.size() == 2:
					# Check these are the only cells with both values
					var v1_count := 0
					var v2_count := 0
					for idx in unit:
						if grid[idx] == 0:
							if v1 in candidates[idx]:
								v1_count += 1
							if v2 in candidates[idx]:
								v2_count += 1
					if v1_count == 2 and v2_count == 2:
						for idx in positions:
							var new_cands: Array[int] = [v1, v2]
							if candidates[idx] != new_cands and candidates[idx].size() > 2:
								candidates[idx] = new_cands
								found = true
								if not Technique.HIDDEN_PAIR in techniques_used:
									techniques_used.append(Technique.HIDDEN_PAIR)
	return found


## Pointing pairs: candidates in a box restricted to one row/col
func _apply_pointing_pairs(grid: Array[int], candidates: Array[Array], spec: SudokuGridSpec = null) -> bool:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var n := s.size
	var found := false
	for box_row in range(0, n, s.region_h):
		for box_col in range(0, n, s.region_w):
			for val in range(s.sym_min, s.sym_max + 1):
				var positions: Array[int] = []
				for r in range(box_row, box_row + s.region_h):
					for c in range(box_col, box_col + s.region_w):
						var idx := r * n + c
						if grid[idx] == 0 and val in candidates[idx]:
							positions.append(idx)
				if positions.size() < 2 or positions.size() > s.region_w:
					continue
				# Check if all in same row
				var same_row := true
				var pr: int = positions[0] / n
				for p in positions:
					if p / n != pr:
						same_row = false
						break
				if same_row:
					for c in n:
						var row_idx := pr * n + c
						if not row_idx in positions and grid[row_idx] == 0 and val in candidates[row_idx]:
							candidates[row_idx].erase(val)
							found = true
							if not Technique.POINTING_PAIR in techniques_used:
								techniques_used.append(Technique.POINTING_PAIR)
				# Check if all in same col
				var same_col := true
				var pc: int = positions[0] % n
				for p in positions:
					if p % n != pc:
						same_col = false
						break
				if same_col:
					for r in n:
						var col_idx := r * n + pc
						if not col_idx in positions and grid[col_idx] == 0 and val in candidates[col_idx]:
							candidates[col_idx].erase(val)
							found = true
							if not Technique.POINTING_PAIR in techniques_used:
								techniques_used.append(Technique.POINTING_PAIR)
	return found


## X-Wing: a value appears in exactly 2 positions in two rows, aligned in columns
func _apply_x_wing(grid: Array[int], candidates: Array[Array], spec: SudokuGridSpec = null) -> bool:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var n := s.size
	var found := false
	for val in range(s.sym_min, s.sym_max + 1):
		# Check rows
		var row_positions: Array[Array] = []
		row_positions.resize(n)
		for r in n:
			row_positions[r] = []
			for c in n:
				var idx := r * n + c
				if grid[idx] == 0 and val in candidates[idx]:
					row_positions[r].append(c)
		for r1 in range(n):
			if row_positions[r1].size() != 2:
				continue
			for r2 in range(r1 + 1, n):
				if row_positions[r2] == row_positions[r1]:
					var c1: int = row_positions[r1][0]
					var c2: int = row_positions[r1][1]
					for r in n:
						if r != r1 and r != r2:
							if val in candidates[r * n + c1]:
								candidates[r * n + c1].erase(val)
								found = true
							if val in candidates[r * n + c2]:
								candidates[r * n + c2].erase(val)
								found = true
					if found and not Technique.X_WING in techniques_used:
						techniques_used.append(Technique.X_WING)
		# Check columns
		var col_positions: Array[Array] = []
		col_positions.resize(n)
		for c in n:
			col_positions[c] = []
			for r in n:
				var col_scan_idx := r * n + c
				if grid[col_scan_idx] == 0 and val in candidates[col_scan_idx]:
					col_positions[c].append(r)
		for c1 in range(n):
			if col_positions[c1].size() != 2:
				continue
			for c2 in range(c1 + 1, n):
				if col_positions[c2] == col_positions[c1]:
					var r1: int = col_positions[c1][0]
					var r2: int = col_positions[c1][1]
					for c in n:
						if c != c1 and c != c2:
							if val in candidates[r1 * n + c]:
								candidates[r1 * n + c].erase(val)
								found = true
							if val in candidates[r2 * n + c]:
								candidates[r2 * n + c].erase(val)
								found = true
					if found and not Technique.X_WING in techniques_used:
						techniques_used.append(Technique.X_WING)
	return found


## Get all units (rows + cols + regions) for the given spec.
## Defaults to standard_9×9 units when spec is null.
static func _get_all_units(spec: SudokuGridSpec = null) -> Array[Array]:
	var s := spec if spec != null else SudokuGridSpec.STANDARD_9X9
	var n := s.size
	var units: Array[Array] = []
	# Rows
	for r in n:
		var unit: Array[int] = []
		for c in n:
			unit.append(r * n + c)
		units.append(unit)
	# Columns
	for c in n:
		var col_unit: Array[int] = []
		for r in n:
			col_unit.append(r * n + c)
		units.append(col_unit)
	# Regions (boxes)
	for br in range(0, n, s.region_h):
		for bc in range(0, n, s.region_w):
			var box_unit: Array[int] = []
			for r in range(br, br + s.region_h):
				for c in range(bc, bc + s.region_w):
					box_unit.append(r * n + c)
			units.append(box_unit)
	return units


## Check if a completed grid is valid.
## Pass spec to use a non-9×9 grid; defaults to standard_9×9 when null.
static func is_valid_grid(grid: Array[int], spec: SudokuGridSpec = null) -> bool:
	for unit in _get_all_units(spec):
		var seen: Array[int] = []
		for idx in unit:
			if grid[idx] == 0:
				return false
			if grid[idx] in seen:
				return false
			seen.append(grid[idx])
	return true


## Determine difficulty based on techniques used
func rate_difficulty() -> Difficulty:
	if techniques_used.is_empty() or techniques_used == [Technique.NAKED_SINGLE]:
		return Difficulty.EASY
	var max_technique: Technique = techniques_used[0]
	for t in techniques_used:
		if t > max_technique:
			max_technique = t
	if max_technique <= Technique.HIDDEN_SINGLE:
		return Difficulty.MEDIUM
	if max_technique <= Technique.HIDDEN_TRIPLE:
		return Difficulty.HARD
	if max_technique <= Technique.BOX_LINE_REDUCTION:
		return Difficulty.EXPERT
	return Difficulty.EVIL


## Full solve and rate: solves a copy, checks uniqueness, rates difficulty.
## Pass constraints explicitly or set the instance constraints field before
## calling.  The explicit parameter takes precedence when non-empty.
## Pass p_spec to use a non-9×9 grid; defaults to standard_9×9 when null.
func analyze(puzzle: Array[int], p_constraints: Array = [], p_spec: SudokuGridSpec = null) -> void:
	var active: Array = p_constraints if not p_constraints.is_empty() else constraints
	var s := p_spec if p_spec != null else SudokuGridSpec.STANDARD_9X9
	# Check uniqueness with brute force (respects any active constraints)
	var solutions := solve_brute_force(puzzle, 2, active, Callable(), s)
	is_unique = solutions.size() == 1
	if is_unique:
		solution = []
		solution.assign(solutions[0])

	# Rate difficulty with logic solver and track whether logic alone completes it.
	var work: Array[int] = []
	work.assign(puzzle.duplicate())
	is_logic_solvable = solve_logic(work, active, s)
	difficulty = rate_difficulty()
