class_name EclipseGridSolver
extends RefCounted

## Validates Eclipse Grid solutions and performs human-logic solving.
##
## Cells are stored as a flat Array[int] of size×size:
##   0 = Empty, 1 = PLUS, 2 = MINUS.
##
## Relations are two Dictionaries:
##   h_relations[Vector2i(col, row)] = EQ or NEQ  (between (col,row) and (col+1,row))
##   v_relations[Vector2i(col, row)] = EQ or NEQ  (between (col,row) and (col,row+1))

const EMPTY := 0
const PLUS  := 1
const MINUS := 2

const EQ  := 1   # = clue: cells must be equal
const NEQ := 2   # ≠ clue: cells must be different

const RANK_1 := 1
const RANK_2 := 2
const RANK_3 := 3
const RANK_4 := 4


## Structured solver step returned by human-logic passes.
class SolverStep:
	var reason: String = ""
	var affected_cells: Array[int] = []   # flat indices
	var result_value: int = 0             # PLUS or MINUS
	var rank: int = 0

	func _init(r: String, cells: Array[int], val: int, rk: int) -> void:
		reason = r
		affected_cells = cells
		result_value = val
		rank = rk


## Analysis result returned by analyze().
class Analysis:
	var is_unique: bool = false
	var steps: Array = []        # Array of SolverStep
	var max_rank: int = 0


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

## Return true if the completed board satisfies all Eclipse Grid rules.
static func validate(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary) -> bool:
	if cells.size() != size * size:
		return false
	# All cells filled
	for v in cells:
		if v == EMPTY:
			return false
	# Balance and no-three rules per row and column
	for r in size:
		if not _check_line(cells, size, r, true):
			return false
	for c in size:
		if not _check_line(cells, size, c, false):
			return false
	# Relation clues
	for pos in h_relations.keys():
		var cell: Vector2i = pos
		var rel: int = h_relations[pos]
		var left: int = cells[cell.y * size + cell.x]
		var right: int = cells[cell.y * size + (cell.x + 1)]
		if rel == EQ and left != right:
			return false
		if rel == NEQ and left == right:
			return false
	for pos in v_relations.keys():
		var cell: Vector2i = pos
		var rel: int = v_relations[pos]
		var top: int = cells[cell.y * size + cell.x]
		var bot: int = cells[(cell.y + 1) * size + cell.x]
		if rel == EQ and top != bot:
			return false
		if rel == NEQ and top == bot:
			return false
	return true


# ---------------------------------------------------------------------------
# Solution counting
# ---------------------------------------------------------------------------

## Count solutions up to max_count using backtracking.
## Pass cancel_check to abort early.
static func count_solutions(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		max_count: int = 2,
		cancel_check: Callable = Callable()) -> int:
	var working: Array[int] = cells.duplicate()
	var counter := [0]
	_backtrack_count(size, working, h_relations, v_relations, 0, max_count, counter, cancel_check)
	return counter[0]


static func _backtrack_count(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		start: int,
		max_count: int,
		counter: Array,
		cancel_check: Callable) -> void:
	if cancel_check.is_valid() and cancel_check.call():
		return
	# Find next empty cell
	var idx := -1
	for i in range(start, cells.size()):
		if cells[i] == EMPTY:
			idx = i
			break
	if idx == -1:
		# All filled — validate
		if validate(size, cells, h_relations, v_relations):
			counter[0] += 1
		return
	for val in [PLUS, MINUS]:
		cells[idx] = val
		if is_consistent(size, cells, h_relations, v_relations):
			_backtrack_count(size, cells, h_relations, v_relations, idx + 1, max_count, counter, cancel_check)
			if counter[0] >= max_count:
				cells[idx] = EMPTY
				return
		if cancel_check.is_valid() and cancel_check.call():
			cells[idx] = EMPTY
			return
	cells[idx] = EMPTY


# ---------------------------------------------------------------------------
# Human-logic solver
# ---------------------------------------------------------------------------

## Run the human-logic solver and return an Analysis.
## cells should be the given/partial board (0=Empty, 1=PLUS, 2=MINUS).
## Returns Analysis with steps in order and max_rank found.
static func analyze(
		size: int,
		initial_cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		cancel_check: Callable = Callable()) -> Analysis:
	var result := Analysis.new()
	var cells: Array[int] = initial_cells.duplicate()

	while true:
		if cancel_check.is_valid() and cancel_check.call():
			return result
		var step: SolverStep = _find_next_step(size, cells, h_relations, v_relations)
		if step == null:
			break
		cells[step.affected_cells[0]] = step.result_value
		result.steps.append(step)
		if step.rank > result.max_rank:
			result.max_rank = step.rank

	# Check if solved
	var all_filled := true
	for v in cells:
		if v == EMPTY:
			all_filled = false
			break
	# If the human solver (using only forced deductions) fills the board completely
	# and it validates, the solution is unique: every step was logically forced, so
	# no alternative assignment exists.  A separate count_solutions call is still
	# available for callers that need an independent uniqueness guarantee.
	if all_filled and validate(size, cells, h_relations, v_relations):
		result.is_unique = true
	return result


## Find the next deducible cell using human-logic techniques in rank order.
static func _find_next_step(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary) -> SolverStep:
	# Rank 1 techniques
	var step: SolverStep

	# Quota completion: if a row/column has size/2 of one glyph, the rest are the other
	step = _quota_completion(size, cells)
	if step:
		return step

	# Adjacent pair prevention: if two consecutive cells are the same glyph,
	# the neighbors must be the opposite
	step = _adjacent_pair_prevention(size, cells)
	if step:
		return step

	# Sandwich: if a cell is surrounded by two cells of the same glyph, it must be the other
	step = _sandwich_rule(size, cells)
	if step:
		return step

	# Direct relation: = or ≠ with one known endpoint determines the other
	step = _direct_relation(size, cells, h_relations, v_relations)
	if step:
		return step

	# Rank 2 techniques
	# Combined local: pair + quota in same line forces one or more cells
	step = _combined_local(size, cells, h_relations, v_relations)
	if step:
		return step

	# Relation propagation: a relation chain propagates to an adjacent unknown
	step = _relation_propagation_rank2(size, cells, h_relations, v_relations)
	if step:
		return step

	# Rank 3 techniques
	step = _relation_chain_rank3(size, cells, h_relations, v_relations)
	if step:
		return step

	# Rank 4 techniques
	step = _global_quota_chain(size, cells, h_relations, v_relations)
	if step:
		return step

	return null


# ---------------------------------------------------------------------------
# Rank 1 techniques
# ---------------------------------------------------------------------------

static func _quota_completion(size: int, cells: Array[int]) -> SolverStep:
	var half := size / 2
	# Rows
	for r in size:
		var plus := 0
		var minus := 0
		var first_empty_idx := -1
		var empty_count := 0
		for c in size:
			var v: int = cells[r * size + c]
			if v == PLUS:
				plus += 1
			elif v == MINUS:
				minus += 1
			else:
				if first_empty_idx < 0:
					first_empty_idx = r * size + c
				empty_count += 1
		if empty_count >= 1:
			if plus == half:
				var af: Array[int] = [first_empty_idx]
				return SolverStep.new("Row quota: %d/%d + filled" % [plus, half], af, MINUS, RANK_1)
			elif minus == half:
				var af: Array[int] = [first_empty_idx]
				return SolverStep.new("Row quota: %d/%d - filled" % [minus, half], af, PLUS, RANK_1)
	# Columns
	for c in size:
		var plus := 0
		var minus := 0
		var first_empty_idx := -1
		var empty_count := 0
		for r in size:
			var v: int = cells[r * size + c]
			if v == PLUS:
				plus += 1
			elif v == MINUS:
				minus += 1
			else:
				if first_empty_idx < 0:
					first_empty_idx = r * size + c
				empty_count += 1
		if empty_count >= 1:
			if plus == half:
				var af: Array[int] = [first_empty_idx]
				return SolverStep.new("Column quota: %d/%d + filled" % [plus, half], af, MINUS, RANK_1)
			elif minus == half:
				var af: Array[int] = [first_empty_idx]
				return SolverStep.new("Column quota: %d/%d - filled" % [minus, half], af, PLUS, RANK_1)
	return null


static func _adjacent_pair_prevention(size: int, cells: Array[int]) -> SolverStep:
	# Rows: if cells[i] == cells[i+1] != EMPTY, cells[i-1] and cells[i+2] must be opposite
	for r in size:
		for c in range(size - 1):
			var a: int = cells[r * size + c]
			var b: int = cells[r * size + c + 1]
			if a == EMPTY or b == EMPTY or a != b:
				continue
			var opposite: int = MINUS if a == PLUS else PLUS
			# Left neighbor
			if c > 0 and cells[r * size + c - 1] == EMPTY:
				var af: Array[int] = [r * size + c - 1]
				return SolverStep.new("Pair prevention: row %d col %d-%d are same" % [r, c, c + 1], af, opposite, RANK_1)
			# Right neighbor
			if c + 2 < size and cells[r * size + c + 2] == EMPTY:
				var af: Array[int] = [r * size + c + 2]
				return SolverStep.new("Pair prevention: row %d col %d-%d are same" % [r, c, c + 1], af, opposite, RANK_1)
	# Columns
	for c in size:
		for r in range(size - 1):
			var a: int = cells[r * size + c]
			var b: int = cells[(r + 1) * size + c]
			if a == EMPTY or b == EMPTY or a != b:
				continue
			var opposite: int = MINUS if a == PLUS else PLUS
			if r > 0 and cells[(r - 1) * size + c] == EMPTY:
				var af: Array[int] = [(r - 1) * size + c]
				return SolverStep.new("Pair prevention: col %d row %d-%d are same" % [c, r, r + 1], af, opposite, RANK_1)
			if r + 2 < size and cells[(r + 2) * size + c] == EMPTY:
				var af: Array[int] = [(r + 2) * size + c]
				return SolverStep.new("Pair prevention: col %d row %d-%d are same" % [c, r, r + 1], af, opposite, RANK_1)
	return null


static func _sandwich_rule(size: int, cells: Array[int]) -> SolverStep:
	# If cell[i-1] == cell[i+1] != EMPTY, and cell[i] == EMPTY, cell[i] must be opposite
	# Rows
	for r in size:
		for c in range(1, size - 1):
			var left: int = cells[r * size + c - 1]
			var right: int = cells[r * size + c + 1]
			var mid: int = cells[r * size + c]
			if mid == EMPTY and left != EMPTY and left == right:
				var opposite: int = MINUS if left == PLUS else PLUS
				var af: Array[int] = [r * size + c]
				return SolverStep.new("Sandwich: row %d col %d between matching cells" % [r, c], af, opposite, RANK_1)
	# Columns
	for c in size:
		for r in range(1, size - 1):
			var top: int = cells[(r - 1) * size + c]
			var bot: int = cells[(r + 1) * size + c]
			var mid: int = cells[r * size + c]
			if mid == EMPTY and top != EMPTY and top == bot:
				var opposite: int = MINUS if top == PLUS else PLUS
				var af: Array[int] = [r * size + c]
				return SolverStep.new("Sandwich: col %d row %d between matching cells" % [c, r], af, opposite, RANK_1)
	return null


static func _direct_relation(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary) -> SolverStep:
	for pos in h_relations.keys():
		var cell: Vector2i = pos
		var rel: int = h_relations[pos]
		var li: int = cell.y * size + cell.x
		var ri: int = cell.y * size + (cell.x + 1)
		var lv: int = cells[li]
		var rv: int = cells[ri]
		if lv != EMPTY and rv == EMPTY:
			var needed: int = lv if rel == EQ else (_opposite(lv))
			var af: Array[int] = [ri]
			return SolverStep.new("Direct relation %s at row %d col %d-%d" % [_rel_str(rel), cell.y, cell.x, cell.x + 1], af, needed, RANK_1)
		if rv != EMPTY and lv == EMPTY:
			var needed: int = rv if rel == EQ else (_opposite(rv))
			var af: Array[int] = [li]
			return SolverStep.new("Direct relation %s at row %d col %d-%d" % [_rel_str(rel), cell.y, cell.x, cell.x + 1], af, needed, RANK_1)
	for pos in v_relations.keys():
		var cell: Vector2i = pos
		var rel: int = v_relations[pos]
		var ti: int = cell.y * size + cell.x
		var bi: int = (cell.y + 1) * size + cell.x
		var tv: int = cells[ti]
		var bv: int = cells[bi]
		if tv != EMPTY and bv == EMPTY:
			var needed: int = tv if rel == EQ else (_opposite(tv))
			var af: Array[int] = [bi]
			return SolverStep.new("Direct relation %s at col %d row %d-%d" % [_rel_str(rel), cell.x, cell.y, cell.y + 1], af, needed, RANK_1)
		if bv != EMPTY and tv == EMPTY:
			var needed: int = bv if rel == EQ else (_opposite(bv))
			var af: Array[int] = [ti]
			return SolverStep.new("Direct relation %s at col %d row %d-%d" % [_rel_str(rel), cell.x, cell.y, cell.y + 1], af, needed, RANK_1)
	return null


# ---------------------------------------------------------------------------
# Rank 2 techniques
# ---------------------------------------------------------------------------

static func _combined_local(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary) -> SolverStep:
	# Two-cell rows: try placing each combination; if only one is consistent, deduce
	# This covers "pair + quota" and "relation propagates one additional edge"
	for r in size:
		var empties: Array[int] = []
		for c in size:
			if cells[r * size + c] == EMPTY:
				empties.append(c)
		if empties.size() == 2:
			var step := _deduce_two_empties_row(size, cells, h_relations, v_relations, r, empties[0], empties[1])
			if step:
				step.rank = RANK_2
				return step
	for c in size:
		var empties: Array[int] = []
		for r in size:
			if cells[r * size + c] == EMPTY:
				empties.append(r)
		if empties.size() == 2:
			var step := _deduce_two_empties_col(size, cells, h_relations, v_relations, c, empties[0], empties[1])
			if step:
				step.rank = RANK_2
				return step
	return null


static func _deduce_two_empties_row(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		row: int,
		c0: int,
		c1: int) -> SolverStep:
	var i0: int = row * size + c0
	var i1: int = row * size + c1
	# Count existing glyphs in this row
	var plus := 0
	var minus := 0
	for c in size:
		var v: int = cells[row * size + c]
		if v == PLUS:
			plus += 1
		elif v == MINUS:
			minus += 1
	var half := size / 2
	# Try all 4 combinations
	var valid_combos: Array[Array] = []
	for va in [PLUS, MINUS]:
		for vb in [PLUS, MINUS]:
			var p2 := plus + (1 if va == PLUS else 0) + (1 if vb == PLUS else 0)
			var m2 := minus + (1 if va == MINUS else 0) + (1 if vb == MINUS else 0)
			if p2 > half or m2 > half:
				continue
			# Check no-three in row with these assignments
			cells[i0] = va
			cells[i1] = vb
			var ok := _check_partial_line(cells, size, row, true, h_relations, v_relations)
			cells[i0] = EMPTY
			cells[i1] = EMPTY
			if ok:
				valid_combos.append([va, vb])
	if valid_combos.size() == 1:
		var combo: Array = valid_combos[0]
		var af: Array[int] = [i0]
		return SolverStep.new("Combined local row %d forces col %d" % [row, c0], af, int(combo[0]), RANK_2)
	# Check if one position is forced
	if valid_combos.size() == 2:
		var v0_set: Dictionary = {}
		var v1_set: Dictionary = {}
		for combo in valid_combos:
			v0_set[int(combo[0])] = true
			v1_set[int(combo[1])] = true
		if v0_set.size() == 1:
			var af: Array[int] = [i0]
			return SolverStep.new("Combined local row %d forces col %d" % [row, c0], af, int(valid_combos[0][0]), RANK_2)
		if v1_set.size() == 1:
			var af: Array[int] = [i1]
			return SolverStep.new("Combined local row %d forces col %d" % [row, c1], af, int(valid_combos[0][1]), RANK_2)
	return null


static func _deduce_two_empties_col(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		col: int,
		r0: int,
		r1: int) -> SolverStep:
	var i0: int = r0 * size + col
	var i1: int = r1 * size + col
	var plus := 0
	var minus := 0
	for r in size:
		var v: int = cells[r * size + col]
		if v == PLUS:
			plus += 1
		elif v == MINUS:
			minus += 1
	var half := size / 2
	var valid_combos: Array[Array] = []
	for va in [PLUS, MINUS]:
		for vb in [PLUS, MINUS]:
			var p2 := plus + (1 if va == PLUS else 0) + (1 if vb == PLUS else 0)
			var m2 := minus + (1 if va == MINUS else 0) + (1 if vb == MINUS else 0)
			if p2 > half or m2 > half:
				continue
			cells[i0] = va
			cells[i1] = vb
			var ok := _check_partial_line(cells, size, col, false, h_relations, v_relations)
			cells[i0] = EMPTY
			cells[i1] = EMPTY
			if ok:
				valid_combos.append([va, vb])
	if valid_combos.size() == 1:
		var combo: Array = valid_combos[0]
		var af: Array[int] = [i0]
		return SolverStep.new("Combined local col %d forces row %d" % [col, r0], af, int(combo[0]), RANK_2)
	if valid_combos.size() == 2:
		var v0_set: Dictionary = {}
		var v1_set: Dictionary = {}
		for combo in valid_combos:
			v0_set[int(combo[0])] = true
			v1_set[int(combo[1])] = true
		if v0_set.size() == 1:
			var af: Array[int] = [i0]
			return SolverStep.new("Combined local col %d forces row %d" % [col, r0], af, int(valid_combos[0][0]), RANK_2)
		if v1_set.size() == 1:
			var af: Array[int] = [i1]
			return SolverStep.new("Combined local col %d forces row %d" % [col, r1], af, int(valid_combos[0][1]), RANK_2)
	return null


static func _relation_propagation_rank2(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary) -> SolverStep:
	# A relation chain of length 2: known → rel → unknown → rel → unknown2
	# Try propagating both h and v chains
	for pos in h_relations.keys():
		var cell: Vector2i = pos
		var rel: int = h_relations[pos]
		var li: int = cell.y * size + cell.x
		var ri: int = cell.y * size + (cell.x + 1)
		# Both empty: check if one can be deduced via another relation
		if cells[li] == EMPTY and cells[ri] == EMPTY:
			# Try: does a known cell next to li (via another relation) force li→ri?
			var step := _propagate_through_empty_h(size, cells, h_relations, v_relations, cell.y, cell.x, rel, true)
			if step:
				return step
			step = _propagate_through_empty_h(size, cells, h_relations, v_relations, cell.y, cell.x + 1, rel, false)
			if step:
				return step
	for pos in v_relations.keys():
		var cell: Vector2i = pos
		var rel: int = v_relations[pos]
		var ti: int = cell.y * size + cell.x
		var bi: int = (cell.y + 1) * size + cell.x
		if cells[ti] == EMPTY and cells[bi] == EMPTY:
			var step := _propagate_through_empty_v(size, cells, h_relations, v_relations, cell.y, cell.x, rel, true)
			if step:
				return step
			step = _propagate_through_empty_v(size, cells, h_relations, v_relations, cell.y + 1, cell.x, rel, false)
			if step:
				return step
	return null


static func _propagate_through_empty_h(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		row: int,
		col: int,
		downstream_rel: int,
		going_right: bool) -> SolverStep:
	# Check if cell at (col, row) can be determined by its other horizontal neighbor
	var src_col := col - 1 if going_right else col + 1
	if src_col < 0 or src_col >= size:
		return null
	var src_pos := Vector2i(mini(src_col, col), row)
	if not h_relations.has(src_pos):
		return null
	var src_rel: int = h_relations[src_pos]
	var src_v: int = cells[row * size + src_col]
	if src_v == EMPTY:
		return null
	# src_v is known; src_rel determines col; then downstream_rel determines the downstream cell
	var mid_v: int = src_v if src_rel == EQ else _opposite(src_v)
	var dst_col := col + 1 if going_right else col - 1
	if dst_col < 0 or dst_col >= size:
		return null
	if cells[row * size + dst_col] != EMPTY:
		return null
	var dst_v: int = mid_v if downstream_rel == EQ else _opposite(mid_v)
	var af: Array[int] = [row * size + dst_col]
	return SolverStep.new("Relation chain row %d: col %d→%d→%d" % [row, src_col, col, dst_col], af, dst_v, RANK_2)


static func _propagate_through_empty_v(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		row: int,
		col: int,
		downstream_rel: int,
		going_down: bool) -> SolverStep:
	var src_row := row - 1 if going_down else row + 1
	if src_row < 0 or src_row >= size:
		return null
	var src_pos := Vector2i(col, mini(src_row, row))
	if not v_relations.has(src_pos):
		return null
	var src_rel: int = v_relations[src_pos]
	var src_v: int = cells[src_row * size + col]
	if src_v == EMPTY:
		return null
	var mid_v: int = src_v if src_rel == EQ else _opposite(src_v)
	var dst_row := row + 1 if going_down else row - 1
	if dst_row < 0 or dst_row >= size:
		return null
	if cells[dst_row * size + col] != EMPTY:
		return null
	var dst_v: int = mid_v if downstream_rel == EQ else _opposite(mid_v)
	var af: Array[int] = [dst_row * size + col]
	return SolverStep.new("Relation chain col %d: row %d→%d→%d" % [col, src_row, row, dst_row], af, dst_v, RANK_2)


# ---------------------------------------------------------------------------
# Rank 3 techniques
# ---------------------------------------------------------------------------

static func _relation_chain_rank3(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary) -> SolverStep:
	# For each row and column, enumerate all valid line completions and return
	# the first cell that is forced in every valid completion (Rank-3 enumeration).
	for r in size:
		var step := _line_propagate_rank3(size, cells, h_relations, v_relations, r, true)
		if step:
			return step
	for c in size:
		var step := _line_propagate_rank3(size, cells, h_relations, v_relations, c, false)
		if step:
			return step
	return null


## Cross-line Rank-3 technique: enumerate all valid line completions, filter by
## LOCAL perpendicular-dimension compatibility (quota + no-three at position `line`
## + adjacent perpendicular relations with FILLED neighbors), and return the first
## cell whose value is unanimous across all cross-compatible completions.
## The perpendicular compatibility step makes this genuinely cross-dimensional and
## finds deductions that single-line Rank-1/2 exhaustion cannot.
## Does NOT modify cells[].
static func _line_propagate_rank3(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		line: int,
		is_row: bool) -> SolverStep:
	var plus_count := 0
	var minus_count := 0
	var empties: Array[int] = []
	var line_vals: Array[int] = []

	for i in size:
		var idx := line * size + i if is_row else i * size + line
		var v: int = cells[idx]
		line_vals.append(v)
		match v:
			PLUS:  plus_count += 1
			MINUS: minus_count += 1
			_:     empties.append(i)

	var k := empties.size()
	if k < 2:
		return null  # Rank 1/2 handles 0–1 empty cells

	var half := size / 2
	var plus_needed  := half - plus_count
	var minus_needed := half - minus_count

	if plus_needed < 0 or minus_needed < 0 or plus_needed + minus_needed != k:
		return null  # Quota already violated or impossible

	# forced_val[j] tracks the consensus value for empties[j] across valid completions:
	#   -1    = no cross-compatible completion seen yet
	#   PLUS/MINUS = all cross-compatible completions agree on this value
	#   EMPTY = completions disagree → not universally forced
	var forced_val: Array[int] = []
	forced_val.resize(k)
	forced_val.fill(-1)
	var has_any := false

	for mask in range(1 << k):
		if _popcount(mask) != plus_needed:
			continue

		# Build trial line
		var trial := line_vals.duplicate()
		for j in k:
			trial[empties[j]] = PLUS if (mask >> j) & 1 else MINUS

		# Validate no-three consecutive in-line
		var valid := true
		for i in range(2, size):
			if trial[i] != EMPTY and trial[i] == trial[i - 1] and trial[i - 1] == trial[i - 2]:
				valid = false
				break
		if not valid:
			continue

		# Validate in-line relations
		if not _line_check_relations(trial, line, is_row, size, h_relations, v_relations):
			continue

		# Cross-line LOCAL compatibility: for each newly-assigned empty cell, verify that
		# placing trial[pos] at (line, pos) (if is_row) or (pos, line) (if is_col)
		# is compatible with the perpendicular dimension's quota, no-three pattern at
		# position `line`, and adjacent perpendicular relation clues with FILLED neighbors.
		var cross_ok := true
		for j in k:
			var pos := empties[j]    # position along this line (col if is_row, row if is_col)
			var tv: int = trial[pos]

			# (a) Perpendicular quota: count plus/minus in the perpendicular line for `pos`.
			var pp := 0
			var pm := 0
			for ii in size:
				var pv: int = cells[ii * size + pos] if is_row else cells[pos * size + ii]
				if pv == PLUS:   pp += 1
				elif pv == MINUS: pm += 1
			if tv == PLUS:  pp += 1
			else:            pm += 1
			if pp > half or pm > half:
				cross_ok = false
				break

			# (b) No-three in the perpendicular dimension at position `line`
			# (the row or column position where we are placing tv).
			var r_perp := line   # perpendicular index: row if is_row, col if is_col
			if is_row:
				# Perpendicular = column pos; check three patterns around row r_perp.
				if r_perp >= 2 \
						and cells[(r_perp - 1) * size + pos] == tv \
						and cells[(r_perp - 2) * size + pos] == tv:
					cross_ok = false
					break
				if r_perp >= 1 and r_perp + 1 < size \
						and cells[(r_perp - 1) * size + pos] == tv \
						and cells[(r_perp + 1) * size + pos] == tv:
					cross_ok = false
					break
				if r_perp + 2 < size \
						and cells[(r_perp + 1) * size + pos] == tv \
						and cells[(r_perp + 2) * size + pos] == tv:
					cross_ok = false
					break
				# (c) Adjacent v-relations at column pos around row r_perp.
				if r_perp > 0:
					var vpos := Vector2i(pos, r_perp - 1)
					if v_relations.has(vpos):
						var above: int = cells[(r_perp - 1) * size + pos]
						if above != EMPTY:
							var rel: int = v_relations[vpos]
							if (rel == EQ and tv != above) or (rel == NEQ and tv == above):
								cross_ok = false
								break
				if r_perp + 1 < size:
					var vpos := Vector2i(pos, r_perp)
					if v_relations.has(vpos):
						var below: int = cells[(r_perp + 1) * size + pos]
						if below != EMPTY:
							var rel: int = v_relations[vpos]
							if (rel == EQ and tv != below) or (rel == NEQ and tv == below):
								cross_ok = false
								break
			else:
				# Perpendicular = row pos; check three patterns around col r_perp.
				if r_perp >= 2 \
						and cells[pos * size + (r_perp - 1)] == tv \
						and cells[pos * size + (r_perp - 2)] == tv:
					cross_ok = false
					break
				if r_perp >= 1 and r_perp + 1 < size \
						and cells[pos * size + (r_perp - 1)] == tv \
						and cells[pos * size + (r_perp + 1)] == tv:
					cross_ok = false
					break
				if r_perp + 2 < size \
						and cells[pos * size + (r_perp + 1)] == tv \
						and cells[pos * size + (r_perp + 2)] == tv:
					cross_ok = false
					break
				# (c) Adjacent h-relations at row pos around col r_perp.
				if r_perp > 0:
					var hpos := Vector2i(r_perp - 1, pos)
					if h_relations.has(hpos):
						var left: int = cells[pos * size + (r_perp - 1)]
						if left != EMPTY:
							var rel: int = h_relations[hpos]
							if (rel == EQ and tv != left) or (rel == NEQ and tv == left):
								cross_ok = false
								break
				if r_perp + 1 < size:
					var hpos := Vector2i(r_perp, pos)
					if h_relations.has(hpos):
						var right: int = cells[pos * size + (r_perp + 1)]
						if right != EMPTY:
							var rel: int = h_relations[hpos]
							if (rel == EQ and tv != right) or (rel == NEQ and tv == right):
								cross_ok = false
								break

		if not cross_ok:
			continue

		# This completion passed cross-line checks: update consensus.
		has_any = true
		for j in k:
			var val: int = trial[empties[j]]
			if forced_val[j] == -1:
				forced_val[j] = val
			elif forced_val[j] != val:
				forced_val[j] = EMPTY  # Disagreement — not universally forced

	if not has_any:
		return null

	# Return the first universally-forced empty cell
	for j in k:
		if forced_val[j] == PLUS or forced_val[j] == MINUS:
			var pos_in_line := empties[j]
			var idx := line * size + pos_in_line if is_row else pos_in_line * size + line
			var ltype := "row" if is_row else "col"
			var af: Array[int] = [idx]
			return SolverStep.new(
				"Rank-3 %s %d: cross-line enumeration forces position %d to %s" % [
					ltype, line, pos_in_line, "+" if forced_val[j] == PLUS else "-"],
				af, forced_val[j], RANK_3)

	return null


## Check all in-line relation constraints for a 1D trial array.
## trial[i] is the value at position i in the line (0..size-1).
## is_row=true means line is a row and uses h_relations; false uses v_relations.
## EMPTY endpoints are skipped. Returns false if any constraint is violated.
static func _line_check_relations(
		trial: Array[int],
		line: int,
		is_row: bool,
		size: int,
		h_relations: Dictionary,
		v_relations: Dictionary) -> bool:
	for i in range(size - 1):
		var a: int = trial[i]
		var b: int = trial[i + 1]
		if a == EMPTY or b == EMPTY:
			continue
		if is_row:
			var pos := Vector2i(i, line)
			if h_relations.has(pos):
				var rel: int = h_relations[pos]
				if (rel == EQ and a != b) or (rel == NEQ and a == b):
					return false
		else:
			var pos := Vector2i(line, i)
			if v_relations.has(pos):
				var rel: int = v_relations[pos]
				if (rel == EQ and a != b) or (rel == NEQ and a == b):
					return false
	return true


## Count set bits (popcount) for small non-negative integers.
static func _popcount(n: int) -> int:
	var count := 0
	var m := n
	while m:
		count += m & 1
		m >>= 1
	return count


# ---------------------------------------------------------------------------
# Rank 4 techniques
# ---------------------------------------------------------------------------

## Non-speculative Rank-4 technique: global consistency check.
## For each row, enumerate all valid row completions (quota + no-three + in-row
## relations), apply each to a copy of cells[], and keep only those that are
## globally consistent (is_consistent passes for ALL rows, columns, and relations).
## Return the first cell whose value is unanimous across ALL globally-consistent
## completions.  This is strictly stronger than the Rank-3 cross-line check because
## is_consistent examines every column and every filled relation pair simultaneously,
## detecting constraints that per-cell local checks miss.
## Does NOT modify cells[].
static func _global_quota_chain(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary) -> SolverStep:
	var half := size / 2

	for r in size:
		var row_plus := 0
		var row_minus := 0
		var row_empties: Array[int] = []
		var row_vals: Array[int] = []
		for c in size:
			var v: int = cells[r * size + c]
			row_vals.append(v)
			match v:
				PLUS:  row_plus += 1
				MINUS: row_minus += 1
				_:     row_empties.append(c)

		var k := row_empties.size()
		if k == 0:
			continue  # No empties to fill

		var row_plus_need  := half - row_plus
		var row_minus_need := half - row_minus
		if row_plus_need < 0 or row_minus_need < 0:
			continue

		# forced_val[j]: consensus across all globally-consistent row completions.
		var forced_val: Array[int] = []
		forced_val.resize(k)
		forced_val.fill(-1)
		var has_any := false

		for mask in range(1 << k):
			if _popcount(mask) != row_plus_need:
				continue

			# Build a trial row completion
			var trial_row := row_vals.duplicate()
			for j in k:
				trial_row[row_empties[j]] = PLUS if (mask >> j) & 1 else MINUS

			# Check no-three consecutive in this trial row
			var row_ok := true
			for i in range(2, size):
				if trial_row[i] == trial_row[i - 1] \
						and trial_row[i - 1] == trial_row[i - 2]:
					row_ok = false
					break
			if not row_ok:
				continue

			# Check in-row relation clues
			if not _line_check_relations(trial_row, r, true, size,
					h_relations, v_relations):
				continue

			# Apply this row completion to a scratch copy and verify global consistency.
			# is_consistent checks ALL rows and columns for quota and no-three, plus
			# ALL filled-endpoint relation pairs — including relations between the newly
			# filled cells and any already-filled perpendicular neighbors.
			var trial_cells := cells.duplicate()
			for c in size:
				trial_cells[r * size + c] = trial_row[c]

			if not is_consistent(size, trial_cells, h_relations, v_relations):
				continue

			# This completion is globally consistent: update per-column consensus.
			has_any = true
			for j in k:
				var val: int = trial_row[row_empties[j]]
				if forced_val[j] == -1:
					forced_val[j] = val
				elif forced_val[j] != val:
					forced_val[j] = EMPTY  # Disagreement — not universally forced

		if has_any:
			for j in k:
				if forced_val[j] == PLUS or forced_val[j] == MINUS:
					var c := row_empties[j]
					var idx := r * size + c
					var af: Array[int] = [idx]
					return SolverStep.new(
						"Rank-4 row %d: globally-consistent completions force col %d to %s" % [
							r, c, "+" if forced_val[j] == PLUS else "-"],
						af, forced_val[j], RANK_4)

	return null


# ---------------------------------------------------------------------------
# Line helpers
# ---------------------------------------------------------------------------

## Full validation of a completed line (row or column).
static func _check_line(cells: Array[int], size: int, line: int, is_row: bool) -> bool:
	var half := size / 2
	var plus := 0
	var minus := 0
	for i in size:
		var v: int = cells[line * size + i] if is_row else cells[i * size + line]
		if v == PLUS:
			plus += 1
		elif v == MINUS:
			minus += 1
		else:
			return false  # Incomplete line
		# No-three check
		if i >= 2:
			var a: int = cells[line * size + (i - 2)] if is_row else cells[(i - 2) * size + line]
			var b: int = cells[line * size + (i - 1)] if is_row else cells[(i - 1) * size + line]
			if v == a and v == b:
				return false
	return plus == half and minus == half


## Partial validation of a line (may have empties).
static func _check_partial_line(
		cells: Array[int],
		size: int,
		line: int,
		is_row: bool,
		h_relations: Dictionary,
		v_relations: Dictionary) -> bool:
	var half := size / 2
	var plus := 0
	var minus := 0
	var run := 0
	var prev := EMPTY
	for i in size:
		var v: int = cells[line * size + i] if is_row else cells[i * size + line]
		if v == EMPTY:
			run = 0
			prev = EMPTY
			continue
		if v == PLUS:
			plus += 1
		else:
			minus += 1
		if plus > half or minus > half:
			return false
		if v == prev:
			run += 1
		else:
			run = 1
		if run >= 3:
			return false
		prev = v
	# Check relation clues within the line
	if is_row:
		var r := line
		for c in range(size - 1):
			var pos := Vector2i(c, r)
			if h_relations.has(pos):
				var lv := cells[r * size + c]
				var rv := cells[r * size + c + 1]
				var rel: int = h_relations[pos]
				if lv != EMPTY and rv != EMPTY:
					if rel == EQ and lv != rv:
						return false
					if rel == NEQ and lv == rv:
						return false
	else:
		var col := line
		for r in range(size - 1):
			var pos := Vector2i(col, r)
			if v_relations.has(pos):
				var tv := cells[r * size + col]
				var bv := cells[(r + 1) * size + col]
				var rel: int = v_relations[pos]
				if tv != EMPTY and bv != EMPTY:
					if rel == EQ and tv != bv:
						return false
					if rel == NEQ and tv == bv:
						return false
	return true


## Partial validation for is_consistent (rows/cols without relation check — that's done separately).
static func _check_partial_line_no_rel(cells: Array[int], size: int, line: int, is_row: bool) -> bool:
	var half := size / 2
	var plus := 0
	var minus := 0
	var run := 0
	var prev := EMPTY
	for i in size:
		var v: int = cells[line * size + i] if is_row else cells[i * size + line]
		if v == EMPTY:
			run = 0
			prev = EMPTY
			continue
		if v == PLUS:
			plus += 1
		else:
			minus += 1
		if plus > half or minus > half:
			return false
		if v == prev:
			run += 1
		else:
			run = 1
		if run >= 3:
			return false
		prev = v
	return true


## Return true if the partial board contains no rule violations in filled cells.
static func is_consistent(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary) -> bool:
	for r in size:
		if not _check_partial_line_no_rel(cells, size, r, true):
			return false
	for c in size:
		if not _check_partial_line_no_rel(cells, size, c, false):
			return false
	for pos in h_relations.keys():
		var cell: Vector2i = pos
		var rel: int = h_relations[pos]
		var lv: int = cells[cell.y * size + cell.x]
		var rv: int = cells[cell.y * size + (cell.x + 1)]
		if lv != EMPTY and rv != EMPTY:
			if rel == EQ and lv != rv:
				return false
			if rel == NEQ and lv == rv:
				return false
	for pos in v_relations.keys():
		var cell: Vector2i = pos
		var rel: int = v_relations[pos]
		var tv: int = cells[cell.y * size + cell.x]
		var bv: int = cells[(cell.y + 1) * size + cell.x]
		if tv != EMPTY and bv != EMPTY:
			if rel == EQ and tv != bv:
				return false
			if rel == NEQ and tv == bv:
				return false
	return true


static func _opposite(v: int) -> int:
	return MINUS if v == PLUS else PLUS


static func _rel_str(rel: int) -> String:
	return "=" if rel == EQ else "≠"
