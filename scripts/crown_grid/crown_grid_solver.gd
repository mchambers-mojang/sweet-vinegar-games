class_name CrownGridSolver
extends RefCounted

## Human-style solver for Crown Grid puzzles.
##
## Cell states:
##   EMPTY    = 0
##   EXCLUDED = 1
##   CROWN    = 2
##
## Reasoning ranks:
##   1 - single row/column/region/adjacency constraint determines a cell
##   2 - combining two constraint types
##   3 - locked candidate set or region-line interaction
##   4 - non-branching chain of 3+ dependent eliminations

const CELL_EMPTY := 0
const CELL_EXCLUDED := 1
const CELL_CROWN := 2

const RANK_NONE := 0
const RANK_SINGLE := 1
const RANK_COMBINED := 2
const RANK_LOCKED := 3
const RANK_CHAIN := 4


## A single human-logic deduction step.
class SolveStep:
	var reason: String = ""
	var affected_cells: Array[Vector2i] = []
	var result: int = CELL_EXCLUDED  # CELL_CROWN or CELL_EXCLUDED
	var rank: int = RANK_NONE

	func _init(r: String = "", cells: Array[Vector2i] = [], res: int = CELL_EXCLUDED, rk: int = RANK_NONE) -> void:
		reason = r
		affected_cells = cells
		result = res
		rank = rk


## Validate that the given crown positions are a complete, correct solution.
## size: board dimension
## regions: PackedInt32Array of length size*size, regions[r*size+c] = region_id
## crown_cols: Array[int] of length size, crown_cols[row] = col (or -1 if not placed)
static func validate_solution(size: int, regions: PackedInt32Array, crown_cols: Array) -> bool:
	if crown_cols.size() != size:
		return false
	# Check each row has exactly one crown
	var col_used := PackedInt32Array()
	col_used.resize(size)
	col_used.fill(0)
	var region_used := PackedInt32Array()
	region_used.resize(size)
	region_used.fill(0)
	for r in range(size):
		var c: int = int(crown_cols[r])
		if c < 0 or c >= size:
			return false
		if col_used[c] != 0:
			return false
		col_used[c] = 1
		var reg: int = regions[r * size + c]
		if reg < 0 or reg >= size:
			return false
		if region_used[reg] != 0:
			return false
		region_used[reg] = 1
	# Check no diagonal adjacency
	for r in range(size - 1):
		var c1: int = int(crown_cols[r])
		var c2: int = int(crown_cols[r + 1])
		if absi(c1 - c2) == 1:
			return false
	return true


## Count solutions using backtracking. Returns 0, 1, or 2 (stops at 2 for speed).
## regions: PackedInt32Array of length size*size
## fixed_crowns: Dictionary[int -> int] row->col for pre-placed crowns (optional)
## cancel_check: Callable() -> bool, return true to abort (returns -1 on cancel)
static func count_solutions(size: int, regions: PackedInt32Array, fixed_crowns: Dictionary = {}, cancel_check: Callable = Callable()) -> int:
	var candidates := _build_candidates(size, regions, fixed_crowns)
	var count_state := [0]
	_count_backtrack(size, regions, candidates, 0, count_state, fixed_crowns, cancel_check)
	if cancel_check.is_valid() and cancel_check.call():
		return -1
	return count_state[0]


## Find the next human-logic deduction step given current board state.
## Returns null if no logical step found (puzzle requires guessing or is solved).
## crowns_by_row: Array[int] length size, -1 = no crown in that row
## excluded: Dictionary[Vector2i -> bool] of excluded cells
## cancel_check: Callable() -> bool, return true to abort (returns null on cancel)
static func find_next_step(
		size: int,
		regions: PackedInt32Array,
		crowns_by_row: Array,
		excluded: Dictionary,
		cancel_check: Callable = Callable()) -> SolveStep:

	# Honour cancellation before doing any work.
	if cancel_check.is_valid() and cancel_check.call():
		return null

	# Build candidate set: cells that could still have a crown
	var cands := _compute_candidates(size, regions, crowns_by_row, excluded)
	if cands.is_empty():
		return null

	# Try deductions in rank order, re-checking cancellation before each
	# potentially expensive rank.
	var step: SolveStep

	step = _try_rank1_singles(size, regions, cands)
	if step:
		return step

	if cancel_check.is_valid() and cancel_check.call():
		return null

	step = _try_rank2_combined(size, regions, cands)
	if step:
		return step

	if cancel_check.is_valid() and cancel_check.call():
		return null

	step = _try_rank3_locked(size, regions, cands, cancel_check)
	if step:
		return step

	step = _try_rank4_chain(size, regions, cands, crowns_by_row, excluded, cancel_check)
	if step:
		return step

	return null


## Perform a full human-style solve and return the maximum rank needed.
## Returns RANK_NONE if the puzzle cannot be solved without guessing.
## cancel_check: Callable() -> bool, return true to abort (returns RANK_NONE on cancel)
static func analyze_difficulty(size: int, regions: PackedInt32Array, cancel_check: Callable = Callable()) -> int:
	var crowns_by_row: Array = []
	crowns_by_row.resize(size)
	crowns_by_row.fill(-1)
	var excluded: Dictionary = {}
	var max_rank := RANK_NONE

	for _iter in range(size * size * 4):
		if cancel_check.is_valid() and cancel_check.call():
			return RANK_NONE
		var step := find_next_step(size, regions, crowns_by_row, excluded, cancel_check)
		if step == null:
			break
		max_rank = maxi(max_rank, step.rank)
		_apply_step(size, regions, crowns_by_row, excluded, step)
		if _is_solved(size, crowns_by_row):
			return max_rank

	if _is_solved(size, crowns_by_row):
		return max_rank
	return RANK_NONE  # Could not solve without guessing


## Apply a solve step to the mutable crown/excluded state.
static func _apply_step(
		size: int,
		regions: PackedInt32Array,
		crowns_by_row: Array,
		excluded: Dictionary,
		step: SolveStep) -> void:

	for cell in step.affected_cells:
		if step.result == CELL_CROWN:
			crowns_by_row[cell.y] = cell.x
			# Propagate crown placement: exclude row, col, region, diagonals
			_exclude_from_crown(size, regions, crowns_by_row, excluded, cell)
		else:
			excluded[cell] = true


## Check whether all rows have a crown placed.
static func _is_solved(size: int, crowns_by_row: Array) -> bool:
	for r in range(size):
		if int(crowns_by_row[r]) < 0:
			return false
	return true


# ---------------------------------------------------------------------------
# Rank 1 — Singles
# ---------------------------------------------------------------------------

static func _try_rank1_singles(size: int, regions: PackedInt32Array, cands: Dictionary) -> SolveStep:
	# A. Only one candidate in a row
	for r in range(size):
		var row_cands := _cands_in_row(cands, r)
		if row_cands.size() == 1:
			return SolveStep.new(
				"Only one candidate cell in row %d" % r,
				row_cands, CELL_CROWN, RANK_SINGLE)

	# B. Only one candidate in a column
	for c in range(size):
		var col_cands := _cands_in_col(cands, c, size)
		if col_cands.size() == 1:
			return SolveStep.new(
				"Only one candidate cell in column %d" % c,
				col_cands, CELL_CROWN, RANK_SINGLE)

	# C. Only one candidate in a region
	for reg in range(size):
		var reg_cands := _cands_in_region(cands, reg, size, regions)
		if reg_cands.size() == 1:
			return SolveStep.new(
				"Only one candidate cell in region %d" % reg,
				reg_cands, CELL_CROWN, RANK_SINGLE)

	# D. Adjacency exclusion already applied during candidate building,
	#    but if placing a crown creates a naked single elsewhere, that's still rank 1.
	return null


# ---------------------------------------------------------------------------
# Rank 2 — Two constraint types combined
# ---------------------------------------------------------------------------

static func _try_rank2_combined(size: int, regions: PackedInt32Array, cands: Dictionary) -> SolveStep:
	# Region-line lock: all candidates in a region are in the same row →
	#   that row's crown is in this region → exclude other regions' cells in that row
	for reg in range(size):
		var reg_cands := _cands_in_region(cands, reg, size, regions)
		if reg_cands.is_empty():
			continue
		var rows := _unique_rows(reg_cands)
		if rows.size() == 1:
			var locked_row: int = rows[0]
			var to_exclude: Array[Vector2i] = []
			for cell in _cands_in_row(cands, locked_row):
				if regions[cell.y * size + cell.x] != reg:
					to_exclude.append(cell)
			if not to_exclude.is_empty():
				return SolveStep.new(
					"Region %d is locked to row %d" % [reg, locked_row],
					to_exclude, CELL_EXCLUDED, RANK_COMBINED)

	# Region-column lock: all candidates in a region are in the same col
	for reg in range(size):
		var reg_cands := _cands_in_region(cands, reg, size, regions)
		if reg_cands.is_empty():
			continue
		var cols := _unique_cols(reg_cands)
		if cols.size() == 1:
			var locked_col: int = cols[0]
			var to_exclude: Array[Vector2i] = []
			for cell in _cands_in_col(cands, locked_col, size):
				if regions[cell.y * size + cell.x] != reg:
					to_exclude.append(cell)
			if not to_exclude.is_empty():
				return SolveStep.new(
					"Region %d is locked to column %d" % [reg, locked_col],
					to_exclude, CELL_EXCLUDED, RANK_COMBINED)

	# Row-region lock: all candidates in a row are in the same region →
	#   that region's crown is in this row → exclude other rows in that region
	for r in range(size):
		var row_cands := _cands_in_row(cands, r)
		if row_cands.is_empty():
			continue
		var regs := _unique_regions(row_cands, size, regions)
		if regs.size() == 1:
			var locked_reg: int = regs[0]
			var to_exclude: Array[Vector2i] = []
			for cell in _cands_in_region(cands, locked_reg, size, regions):
				if cell.y != r:
					to_exclude.append(cell)
			if not to_exclude.is_empty():
				return SolveStep.new(
					"Row %d candidates are all in region %d" % [r, locked_reg],
					to_exclude, CELL_EXCLUDED, RANK_COMBINED)

	# Col-region lock
	for c in range(size):
		var col_cands := _cands_in_col(cands, c, size)
		if col_cands.is_empty():
			continue
		var regs := _unique_regions(col_cands, size, regions)
		if regs.size() == 1:
			var locked_reg: int = regs[0]
			var to_exclude: Array[Vector2i] = []
			for cell in _cands_in_region(cands, locked_reg, size, regions):
				if cell.x != c:
					to_exclude.append(cell)
			if not to_exclude.is_empty():
				return SolveStep.new(
					"Column %d candidates are all in region %d" % [c, locked_reg],
					to_exclude, CELL_EXCLUDED, RANK_COMBINED)

	return null


# ---------------------------------------------------------------------------
# Rank 3 — Locked candidate sets / region-line interactions
# ---------------------------------------------------------------------------

static func _try_rank3_locked(size: int, regions: PackedInt32Array, cands: Dictionary, cancel_check: Callable = Callable()) -> SolveStep:
	# N regions whose combined candidates span exactly N rows →
	#   those N rows are claimed by those N regions → exclude other regions in those rows
	var region_row_sets: Array = []
	for reg in range(size):
		var reg_cands := _cands_in_region(cands, reg, size, regions)
		if reg_cands.is_empty():
			continue
		var rows := _unique_rows(reg_cands)
		region_row_sets.append({"reg": reg, "rows": rows})

	# Check subsets of size 2..N-1
	var step := _find_locked_subset(size, regions, cands, region_row_sets, true, cancel_check)
	if step:
		return step

	if cancel_check.is_valid() and cancel_check.call():
		return null

	# N regions with N columns
	var region_col_sets: Array = []
	for reg in range(size):
		var reg_cands := _cands_in_region(cands, reg, size, regions)
		if reg_cands.is_empty():
			continue
		var cols := _unique_cols(reg_cands)
		region_col_sets.append({"reg": reg, "cols": cols})

	step = _find_locked_subset(size, regions, cands, region_col_sets, false, cancel_check)
	if step:
		return step

	return null


static func _find_locked_subset(
		size: int,
		regions: PackedInt32Array,
		cands: Dictionary,
		sets: Array,
		use_rows: bool,
		cancel_check: Callable = Callable()) -> SolveStep:

	var n := sets.size()
	for subset_size in range(2, n):
		if cancel_check.is_valid() and cancel_check.call():
			return null
		# Iterate combinations of size subset_size
		var indices := _combinations(n, subset_size)
		for combo in indices:
			var combined_lines: Array[int] = []
			var subset_regs: Array[int] = []
			for idx in combo:
				subset_regs.append(sets[idx]["reg"])
				var lines: Array = sets[idx]["rows"] if use_rows else sets[idx]["cols"]
				for line in lines:
					if not combined_lines.has(line):
						combined_lines.append(line)
			if combined_lines.size() == subset_size:
				# Lock found: exclude other regions from these lines
				var to_exclude: Array[Vector2i] = []
				for line in combined_lines:
					var line_cands: Array[Vector2i] = (
						_cands_in_row(cands, line) if use_rows
						else _cands_in_col(cands, line, size))
					for cell in line_cands:
						var reg: int = regions[cell.y * size + cell.x]
						if not subset_regs.has(reg):
							to_exclude.append(cell)
				if not to_exclude.is_empty():
					var line_type := "rows" if use_rows else "columns"
					return SolveStep.new(
						"%d regions locked to %d %s" % [subset_size, subset_size, line_type],
						to_exclude, CELL_EXCLUDED, RANK_LOCKED)
	return null


# ---------------------------------------------------------------------------
# Rank 4 — Bilocal X-chain (genuinely non-speculative, 3+ dependent links)
# ---------------------------------------------------------------------------

## An X-chain is a path of cells  C0 — C1 — C2 — … — Cn  where each
## consecutive pair (C_{k−1}, C_k) is a *strong link*: the only two remaining
## candidates in some shared unit (row, column, or region).
##
## For a chain of odd length L ≥ 3:
##   C0 NOT crown  ⟹  C1 IS  crown  (link 1, strong)
##                 ⟹  C2 NOT crown  (link 2, strong)
##                 ⟹  …
##                 ⟹  Cn  IS  crown  (link L, strong)
##   ∴ "C0 IS crown  OR  Cn IS crown"
##
## Any candidate Z that sees both C0 and Cn is eliminated regardless of which
## endpoint holds the Crown — a genuinely forced, non-speculative deduction
## using L dependent reasoning steps.
##
## Three or more links are required (L ≥ 3) so the deduction is a proper chain
## and not a single direct elimination.
##
## Implementation: depth-first search over the strong-link graph, capped at
## MAX_CHAIN_LINKS to keep the search tractable.
## cancel_check is polled at the start of every top-level DFS expansion.
static func _try_rank4_chain(
		size: int,
		regions: PackedInt32Array,
		cands: Dictionary,
		_crowns_by_row: Array,
		_excluded: Dictionary,
		cancel_check: Callable = Callable()) -> SolveStep:

	# Build bilocal adjacency: cell → Dictionary[neighbor_cell → true].
	# A bilocal pair (A, B) exists when A and B are the *only* 2 candidates
	# in some shared row, column, or region.
	var adj: Dictionary = {}
	for cell in cands.keys():
		adj[cell as Vector2i] = {}

	for r in range(size):
		var rc := _cands_in_row(cands, r)
		if rc.size() == 2:
			var adj_a: Dictionary = adj[rc[0]]
			var adj_b: Dictionary = adj[rc[1]]
			adj_a[rc[1]] = true
			adj_b[rc[0]] = true
	for c in range(size):
		var cc := _cands_in_col(cands, c, size)
		if cc.size() == 2:
			var adj_a: Dictionary = adj[cc[0]]
			var adj_b: Dictionary = adj[cc[1]]
			adj_a[cc[1]] = true
			adj_b[cc[0]] = true
	for reg in range(size):
		var rc := _cands_in_region(cands, reg, size, regions)
		if rc.size() == 2:
			var adj_a: Dictionary = adj[rc[0]]
			var adj_b: Dictionary = adj[rc[1]]
			adj_a[rc[1]] = true
			adj_b[rc[0]] = true

	# DFS for odd-length chains with 3+ links that produce eliminations.
	for start_cell in cands.keys():
		if cancel_check.is_valid() and cancel_check.call():
			return null
		var start := start_cell as Vector2i
		var visited: Dictionary = {start: true}
		var result := _dfs_xchain(
				start, start, 0, visited, adj, size, regions, cands, cancel_check)
		if result:
			return result

	return null


## DFS helper: extend the X-chain from `current` and check for eliminations.
## `depth` = number of strong links traversed so far.
## At odd depth ≥ 3 the chain proves "start IS crown OR current IS crown", so
## any candidate seeing both endpoints can be excluded.
static func _dfs_xchain(
		start: Vector2i,
		current: Vector2i,
		depth: int,
		visited: Dictionary,
		adj: Dictionary,
		size: int,
		regions: PackedInt32Array,
		cands: Dictionary,
		cancel_check: Callable) -> SolveStep:

	const MAX_CHAIN_LINKS := 7

	if depth >= 3 and depth % 2 == 1:
		var to_exclude: Array[Vector2i] = []
		for cand_cell in cands.keys():
			var v := cand_cell as Vector2i
			if v == start or v == current:
				continue
			if _cell_sees(v, start, size, regions) and _cell_sees(v, current, size, regions):
				to_exclude.append(v)
		if not to_exclude.is_empty():
			return SolveStep.new(
				"X-chain (%d links): Crown in %s or %s" % [depth, str(start), str(current)],
				to_exclude, CELL_EXCLUDED, RANK_CHAIN)

	if depth >= MAX_CHAIN_LINKS:
		return null

	if not adj.has(current):
		return null
	var neighbors: Dictionary = adj[current]
	for next_cell in neighbors.keys():
		var next := next_cell as Vector2i
		if visited.has(next):
			continue
		if cancel_check.is_valid() and cancel_check.call():
			return null
		visited[next] = true
		var result := _dfs_xchain(
				start, next, depth + 1, visited, adj, size, regions, cands, cancel_check)
		visited.erase(next)
		if result:
			return result

	return null


## Return true if cell `a` "sees" cell `b`: they share a row, column, region,
## or are diagonally adjacent (|Δrow| = |Δcol| = 1).  A cell does not see itself.
static func _cell_sees(a: Vector2i, b: Vector2i, size: int, regions: PackedInt32Array) -> bool:
	if a == b:
		return false
	if a.y == b.y or a.x == b.x:
		return true
	if regions[a.y * size + a.x] == regions[b.y * size + b.x]:
		return true
	return absi(a.y - b.y) == 1 and absi(a.x - b.x) == 1


# ---------------------------------------------------------------------------
# Candidate helpers
# ---------------------------------------------------------------------------

## Build initial candidates from fixed crowns (used for count_solutions).
static func _build_candidates(size: int, regions: PackedInt32Array, fixed_crowns: Dictionary) -> Dictionary:
	var cands: Dictionary = {}
	for r in range(size):
		for c in range(size):
			cands[Vector2i(c, r)] = true
	for row in fixed_crowns:
		var col: int = int(fixed_crowns[row])
		var crown_cell := Vector2i(col, int(row))
		var dummy_excluded: Dictionary = {}
		var dummy_crowns: Array = []
		dummy_crowns.resize(size)
		dummy_crowns.fill(-1)
		dummy_crowns[int(row)] = col
		_exclude_from_crown(size, regions, dummy_crowns, dummy_excluded, crown_cell)
		cands.erase(crown_cell)
		for cell in dummy_excluded:
			cands.erase(cell)
	return cands


## Compute candidate cells given current board state.
## Filters out cells in used rows/cols/regions, explicitly excluded cells,
## and cells diagonally adjacent to already-placed crowns.
static func _compute_candidates(
		size: int,
		regions: PackedInt32Array,
		crowns_by_row: Array,
		excluded: Dictionary) -> Dictionary:

	# Build sets of used rows, cols, regions, and diagonal-adjacent cells
	var used_rows: Dictionary = {}
	var used_cols: Dictionary = {}
	var used_regions: Dictionary = {}
	var diag_adjacent: Dictionary = {}
	for r in range(size):
		var c: int = int(crowns_by_row[r])
		if c >= 0:
			used_rows[r] = true
			used_cols[c] = true
			used_regions[regions[r * size + c]] = true
			for dr in [-1, 1]:
				for dc in [-1, 1]:
					var nr: int = r + dr
					var nc: int = c + dc
					if nr >= 0 and nr < size and nc >= 0 and nc < size:
						diag_adjacent[Vector2i(nc, nr)] = true

	var cands: Dictionary = {}
	for r in range(size):
		if used_rows.has(r):
			continue
		for c in range(size):
			if used_cols.has(c):
				continue
			var reg: int = regions[r * size + c]
			if used_regions.has(reg):
				continue
			var cell := Vector2i(c, r)
			if excluded.has(cell):
				continue
			if diag_adjacent.has(cell):
				continue
			cands[cell] = true
	return cands


## When a crown is placed at (cc, rc), exclude all conflicting cells.
static func _exclude_from_crown(
		size: int,
		regions: PackedInt32Array,
		crowns_by_row: Array,
		excluded: Dictionary,
		crown_cell: Vector2i) -> void:

	var cc: int = crown_cell.x
	var rc: int = crown_cell.y
	var reg: int = regions[rc * size + cc]

	# Exclude rest of row
	for c in range(size):
		if c != cc:
			excluded[Vector2i(c, rc)] = true

	# Exclude rest of col
	for r in range(size):
		if r != rc:
			excluded[Vector2i(cc, r)] = true

	# Exclude rest of region
	for r in range(size):
		for c in range(size):
			if regions[r * size + c] == reg and not (r == rc and c == cc):
				excluded[Vector2i(c, r)] = true

	# Exclude diagonal neighbors
	for dr in [-1, 1]:
		for dc in [-1, 1]:
			var nr: int = rc + dr
			var nc: int = cc + dc
			if nr >= 0 and nr < size and nc >= 0 and nc < size:
				excluded[Vector2i(nc, nr)] = true


static func _cands_in_row(cands: Dictionary, r: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in cands.keys():
		if (cell as Vector2i).y == r:
			result.append(cell)
	return result


static func _cands_in_col(cands: Dictionary, c: int, _size: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in cands.keys():
		if (cell as Vector2i).x == c:
			result.append(cell)
	return result


static func _cands_in_region(cands: Dictionary, reg: int, size: int, regions: PackedInt32Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in cands.keys():
		var v := cell as Vector2i
		if regions[v.y * size + v.x] == reg:
			result.append(v)
	return result


static func _unique_rows(cells: Array[Vector2i]) -> Array[int]:
	var seen: Dictionary = {}
	for cell in cells:
		seen[cell.y] = true
	var result: Array[int] = []
	for r in seen:
		result.append(r)
	return result


static func _unique_cols(cells: Array[Vector2i]) -> Array[int]:
	var seen: Dictionary = {}
	for cell in cells:
		seen[cell.x] = true
	var result: Array[int] = []
	for c in seen:
		result.append(c)
	return result


static func _unique_regions(cells: Array[Vector2i], size: int, regions: PackedInt32Array) -> Array[int]:
	var seen: Dictionary = {}
	for cell in cells:
		seen[regions[cell.y * size + cell.x]] = true
	var result: Array[int] = []
	for reg in seen:
		result.append(reg)
	return result


static func _clone_cands(cands: Dictionary) -> Dictionary:
	return cands.duplicate()


# ---------------------------------------------------------------------------
# Backtracking solver (for uniqueness / count)
# ---------------------------------------------------------------------------

static func _count_backtrack(
		size: int,
		regions: PackedInt32Array,
		cands: Dictionary,
		row: int,
		count_state: Array,
		fixed_crowns: Dictionary,
		cancel_check: Callable = Callable()) -> void:

	if count_state[0] >= 2:
		return

	if cancel_check.is_valid() and cancel_check.call():
		return

	if row >= size:
		count_state[0] += 1
		return

	# Skip row if already has a fixed crown
	if fixed_crowns.has(row):
		_count_backtrack(size, regions, cands, row + 1, count_state, fixed_crowns, cancel_check)
		return

	var row_cands: Array[Vector2i] = _cands_in_row(cands, row)
	for cell in row_cands:
		if count_state[0] >= 2:
			return
		if cancel_check.is_valid() and cancel_check.call():
			return
		# Save and apply
		var newly_removed: Array[Vector2i] = []
		for c2 in cands.keys():
			var v := c2 as Vector2i
			if v == cell:
				continue
			var same_row := v.y == cell.y
			var same_col := v.x == cell.x
			var same_reg := regions[v.y * size + v.x] == regions[cell.y * size + cell.x]
			var diag_adj := absi(v.y - cell.y) == 1 and absi(v.x - cell.x) == 1
			if same_row or same_col or same_reg or diag_adj:
				newly_removed.append(v)
		for v2 in newly_removed:
			cands.erase(v2)
		cands.erase(cell)

		_count_backtrack(size, regions, cands, row + 1, count_state, fixed_crowns, cancel_check)

		# Restore
		cands[cell] = true
		for v2 in newly_removed:
			cands[v2] = true


# ---------------------------------------------------------------------------
# Combination helper
# ---------------------------------------------------------------------------

static func _combinations(n: int, k: int) -> Array[Array]:
	var result: Array[Array] = []
	var combo: Array[int] = []
	combo.resize(k)
	_combo_helper(n, k, 0, 0, combo, result)
	return result


static func _combo_helper(n: int, k: int, start: int, depth: int, combo: Array[int], result: Array[Array]) -> void:
	if depth == k:
		result.append(combo.duplicate())
		return
	for i in range(start, n - (k - depth - 1)):
		combo[depth] = i
		_combo_helper(n, k, i + 1, depth + 1, combo, result)
