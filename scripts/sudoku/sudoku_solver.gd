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
var techniques_used: Array[Technique] = []
var difficulty: Difficulty = Difficulty.EASY

## Optional constraints evaluated during solving and uniqueness checks.
## Set before calling analyze() to enable variant-aware analysis.
var constraints: Array = []


## Check if placing val at index is valid in the grid.
## Pass a non-empty constraints array to enforce variant rules in addition to
## the standard row/column/box checks.
static func is_valid_placement(grid: Array[int], index: int, val: int, constraints: Array = []) -> bool:
	var row := index / 9
	var col := index % 9
	var box_row := (row / 3) * 3
	var box_col := (col / 3) * 3

	for i in 9:
		# Check row
		if grid[row * 9 + i] == val:
			return false
		# Check column
		if grid[i * 9 + col] == val:
			return false
		# Check 3x3 box
		var br := box_row + i / 3
		var bc := box_col + i % 3
		if grid[br * 9 + bc] == val:
			return false
	for c in constraints:
		if not c.is_valid(grid, index, val):
			return false
	return true


## Get all candidates for a cell
static func get_candidates(grid: Array[int], index: int, constraints: Array = []) -> Array[int]:
	if grid[index] != 0:
		return []
	var candidates: Array[int] = []
	for val in range(1, 10):
		if is_valid_placement(grid, index, val, constraints):
			candidates.append(val)
	return candidates


## Brute-force solve using backtracking with MRV heuristic. Returns number of solutions found (stops at max_solutions).
static func solve_brute_force(grid: Array[int], max_solutions: int = 2, constraints: Array = []) -> Array[Array]:
	var solutions: Array[Array] = []
	var work := grid.duplicate()
	_backtrack_mrv(work, solutions, max_solutions, constraints)
	return solutions


static func _find_mrv_cell(grid: Array[int], constraints: Array = []) -> int:
	## Find the empty cell with the fewest candidates (MRV heuristic)
	var best_pos := -1
	var best_count := 10
	for i in 81:
		if grid[i] != 0:
			continue
		var count := 0
		for v in range(1, 10):
			if is_valid_placement(grid, i, v, constraints):
				count += 1
		if count == 0:
			return -2  # Dead end — no candidates
		if count < best_count:
			best_count = count
			best_pos = i
			if count == 1:
				break  # Can't do better than 1
	return best_pos


static func _backtrack_mrv(grid: Array[int], solutions: Array[Array], max_solutions: int, constraints: Array = []) -> void:
	if solutions.size() >= max_solutions:
		return

	var pos := _find_mrv_cell(grid, constraints)
	if pos == -1:
		# No empty cells — solved
		solutions.append(grid.duplicate())
		return
	if pos == -2:
		# Dead end
		return

	var candidates := get_candidates(grid, pos, constraints)
	for val in candidates:
		grid[pos] = val
		_backtrack_mrv(grid, solutions, max_solutions, constraints)
		grid[pos] = 0
		if solutions.size() >= max_solutions:
			return


## Logic-based solve that tracks which techniques were needed.
## Returns true if the puzzle was fully solved using logic alone.
func solve_logic(grid: Array[int]) -> bool:
	techniques_used.clear()
	var candidates: Array[Array] = []
	candidates.resize(81)
	# Initialize candidates
	for i in 81:
		if grid[i] == 0:
			candidates[i] = get_candidates(grid, i)
		else:
			candidates[i] = []

	var progress := true
	while progress:
		progress = false

		# Naked singles
		for i in 81:
			if grid[i] == 0 and candidates[i].size() == 1:
				grid[i] = candidates[i][0]
				_eliminate_candidates(candidates, grid, i, grid[i])
				candidates[i] = []
				progress = true
				if not Technique.NAKED_SINGLE in techniques_used:
					techniques_used.append(Technique.NAKED_SINGLE)

		if progress:
			continue

		# Hidden singles
		if _apply_hidden_singles(grid, candidates):
			progress = true
			continue

		# Naked pairs
		if _apply_naked_pairs(grid, candidates):
			progress = true
			continue

		# Naked triples
		if _apply_naked_triples(grid, candidates):
			progress = true
			continue

		# Hidden pairs
		if _apply_hidden_pairs(grid, candidates):
			progress = true
			continue

		# Pointing pairs / box-line reduction
		if _apply_pointing_pairs(grid, candidates):
			progress = true
			continue

		# X-Wing
		if _apply_x_wing(grid, candidates):
			progress = true
			continue

	# Check if fully solved
	for i in 81:
		if grid[i] == 0:
			return false
	return true


## Eliminate a value from candidates in the same row, column, and box
static func _eliminate_candidates(candidates: Array[Array], grid: Array[int], index: int, val: int) -> void:
	var row := index / 9
	var col := index % 9
	var box_row := (row / 3) * 3
	var box_col := (col / 3) * 3

	for i in 9:
		candidates[row * 9 + i].erase(val)
		candidates[i * 9 + col].erase(val)
		var br := box_row + i / 3
		var bc := box_col + i % 3
		candidates[br * 9 + bc].erase(val)


## Hidden singles: a value can only go in one place in a row/col/box
func _apply_hidden_singles(grid: Array[int], candidates: Array[Array]) -> bool:
	var found := false
	# Check each unit (row, col, box)
	for unit in _get_all_units():
		for val in range(1, 10):
			var positions: Array[int] = []
			for idx in unit:
				if grid[idx] == 0 and val in candidates[idx]:
					positions.append(idx)
			if positions.size() == 1:
				var idx := positions[0]
				grid[idx] = val
				_eliminate_candidates(candidates, grid, idx, val)
				candidates[idx] = []
				found = true
				if not Technique.HIDDEN_SINGLE in techniques_used:
					techniques_used.append(Technique.HIDDEN_SINGLE)
	return found


## Naked pairs: two cells in a unit with the same two candidates
func _apply_naked_pairs(grid: Array[int], candidates: Array[Array]) -> bool:
	var found := false
	for unit in _get_all_units():
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
func _apply_naked_triples(grid: Array[int], candidates: Array[Array]) -> bool:
	var found := false
	for unit in _get_all_units():
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
func _apply_hidden_pairs(grid: Array[int], candidates: Array[Array]) -> bool:
	var found := false
	for unit in _get_all_units():
		for v1 in range(1, 10):
			for v2 in range(v1 + 1, 10):
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
func _apply_pointing_pairs(grid: Array[int], candidates: Array[Array]) -> bool:
	var found := false
	for box_row in range(0, 9, 3):
		for box_col in range(0, 9, 3):
			for val in range(1, 10):
				var positions: Array[int] = []
				for r in range(box_row, box_row + 3):
					for c in range(box_col, box_col + 3):
						var idx := r * 9 + c
						if grid[idx] == 0 and val in candidates[idx]:
							positions.append(idx)
				if positions.size() < 2 or positions.size() > 3:
					continue
				# Check if all in same row
				var same_row := true
				var pr: int = positions[0] / 9
				for p in positions:
					if p / 9 != pr:
						same_row = false
						break
				if same_row:
					for c in 9:
						var row_idx := pr * 9 + c
						if not row_idx in positions and grid[row_idx] == 0 and val in candidates[row_idx]:
							candidates[row_idx].erase(val)
							found = true
							if not Technique.POINTING_PAIR in techniques_used:
								techniques_used.append(Technique.POINTING_PAIR)
				# Check if all in same col
				var same_col := true
				var pc: int = positions[0] % 9
				for p in positions:
					if p % 9 != pc:
						same_col = false
						break
				if same_col:
					for r in 9:
						var col_idx := r * 9 + pc
						if not col_idx in positions and grid[col_idx] == 0 and val in candidates[col_idx]:
							candidates[col_idx].erase(val)
							found = true
							if not Technique.POINTING_PAIR in techniques_used:
								techniques_used.append(Technique.POINTING_PAIR)
	return found


## X-Wing: a value appears in exactly 2 positions in two rows, aligned in columns
func _apply_x_wing(grid: Array[int], candidates: Array[Array]) -> bool:
	var found := false
	for val in range(1, 10):
		# Check rows
		var row_positions: Array[Array] = []
		row_positions.resize(9)
		for r in 9:
			row_positions[r] = []
			for c in 9:
				var idx := r * 9 + c
				if grid[idx] == 0 and val in candidates[idx]:
					row_positions[r].append(c)
		for r1 in range(9):
			if row_positions[r1].size() != 2:
				continue
			for r2 in range(r1 + 1, 9):
				if row_positions[r2] == row_positions[r1]:
					var c1: int = row_positions[r1][0]
					var c2: int = row_positions[r1][1]
					for r in 9:
						if r != r1 and r != r2:
							if val in candidates[r * 9 + c1]:
								candidates[r * 9 + c1].erase(val)
								found = true
							if val in candidates[r * 9 + c2]:
								candidates[r * 9 + c2].erase(val)
								found = true
					if found and not Technique.X_WING in techniques_used:
						techniques_used.append(Technique.X_WING)
		# Check columns
		var col_positions: Array[Array] = []
		col_positions.resize(9)
		for c in 9:
			col_positions[c] = []
			for r in 9:
				var col_scan_idx := r * 9 + c
				if grid[col_scan_idx] == 0 and val in candidates[col_scan_idx]:
					col_positions[c].append(r)
		for c1 in range(9):
			if col_positions[c1].size() != 2:
				continue
			for c2 in range(c1 + 1, 9):
				if col_positions[c2] == col_positions[c1]:
					var r1: int = col_positions[c1][0]
					var r2: int = col_positions[c1][1]
					for c in 9:
						if c != c1 and c != c2:
							if val in candidates[r1 * 9 + c]:
								candidates[r1 * 9 + c].erase(val)
								found = true
							if val in candidates[r2 * 9 + c]:
								candidates[r2 * 9 + c].erase(val)
								found = true
					if found and not Technique.X_WING in techniques_used:
						techniques_used.append(Technique.X_WING)
	return found


## Get all 27 units (9 rows + 9 cols + 9 boxes)
static func _get_all_units() -> Array[Array]:
	var units: Array[Array] = []
	# Rows
	for r in 9:
		var unit: Array[int] = []
		for c in 9:
			unit.append(r * 9 + c)
		units.append(unit)
	# Columns
	for c in 9:
		var col_unit: Array[int] = []
		for r in 9:
			col_unit.append(r * 9 + c)
		units.append(col_unit)
	# Boxes
	for br in range(0, 9, 3):
		for bc in range(0, 9, 3):
			var box_unit: Array[int] = []
			for r in range(br, br + 3):
				for c in range(bc, bc + 3):
					box_unit.append(r * 9 + c)
			units.append(box_unit)
	return units


## Check if a completed grid is valid
static func is_valid_grid(grid: Array[int]) -> bool:
	for unit in _get_all_units():
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


## Full solve and rate: solves a copy, checks uniqueness, rates difficulty
func analyze(puzzle: Array[int]) -> void:
	# Check uniqueness with brute force (respects any active constraints)
	var solutions := solve_brute_force(puzzle, 2, constraints)
	is_unique = solutions.size() == 1
	if is_unique:
		solution = []
		solution.assign(solutions[0])

	# Rate difficulty with logic solver
	var work: Array[int] = []
	work.assign(puzzle.duplicate())
	solve_logic(work)
	difficulty = rate_difficulty()
