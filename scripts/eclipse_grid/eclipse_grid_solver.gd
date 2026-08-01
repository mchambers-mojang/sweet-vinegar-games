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
	# Iterate over each row/column and propagate direct constraints without
	# placing any trial values.  A cell is forced when one value is immediately
	# ruled out by quota, no-three, or relation constraints given the current
	# line state; repeated passes propagate cascading forced values.
	for r in size:
		var step := _line_propagate_rank3(size, cells, h_relations, v_relations, r, true)
		if step:
			return step
	for c in size:
		var step := _line_propagate_rank3(size, cells, h_relations, v_relations, c, false)
		if step:
			return step
	return null


## Iterative non-speculative Rank-3 propagation for a single line.
## Checks whether each empty cell's value is directly forced by quota, no-three,
## or relation constraints using only the current known state — no trial placement.
## Propagates: each newly forced value is committed to a working copy so that
## subsequent positions can benefit from the deduction.
static func _line_propagate_rank3(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		line: int,
		is_row: bool) -> SolverStep:
	# Collect empties and current counts for the line.
	var plus_count := 0
	var minus_count := 0
	var empties: Array[int] = []
	for i in size:
		var idx := line * size + i if is_row else i * size + line
		match cells[idx]:
			PLUS:  plus_count += 1
			MINUS: minus_count += 1
			_:     empties.append(i)

	if empties.size() < 3:
		return null  # Rank 1/2 handles 0-2 empty cells in a line

	var half := size / 2
	var working: Array[int] = cells.duplicate()
	var w_plus  := plus_count
	var w_minus := minus_count
	var first_step: SolverStep = null
	var propagated_count := 0  # How many cells were forced before the reported step
	var changed := true

	while changed:
		changed = false
		for e in empties:
			var idx := line * size + e if is_row else e * size + line
			if working[idx] != EMPTY:
				continue

			# Check whether each value is immediately ruled out by the current
			# working state — purely by examining existing neighbours; no placement.
			var plus_blocked  := (w_plus  >= half) \
				or _is_no_three_blocked_in_line(working, size, line, is_row, e, PLUS) \
				or _is_relation_blocked_in_line(working, size, line, is_row, e, PLUS,
												h_relations, v_relations)
			var minus_blocked := (w_minus >= half) \
				or _is_no_three_blocked_in_line(working, size, line, is_row, e, MINUS) \
				or _is_relation_blocked_in_line(working, size, line, is_row, e, MINUS,
												h_relations, v_relations)

			if plus_blocked and not minus_blocked:
				# Only record this as the return step if cascade has already
				# happened (propagated_count > 0).  Deductions visible on the
				# original board state (propagated_count == 0) are equivalent to
				# Rank-1 and are handled by the global Rank-1 functions; returning
				# them here would both mislabel them and cause max_rank to stay low,
				# making Hard/Expert puzzles impossible to generate.
				if first_step == null and propagated_count > 0:
					var af: Array[int] = [idx]
					var ltype := "row" if is_row else "col"
					first_step = SolverStep.new(
						"Rank-3 %s %d: cascade forces position %d to MINUS" % [ltype, line, e],
						af, MINUS, RANK_3)
				working[idx] = MINUS
				w_minus += 1
				propagated_count += 1
				changed = true
			elif minus_blocked and not plus_blocked:
				if first_step == null and propagated_count > 0:
					var af: Array[int] = [idx]
					var ltype := "row" if is_row else "col"
					first_step = SolverStep.new(
						"Rank-3 %s %d: cascade forces position %d to PLUS" % [ltype, line, e],
						af, PLUS, RANK_3)
				working[idx] = PLUS
				w_plus += 1
				propagated_count += 1
				changed = true

	# Also handle the unique-completion case: after cascade propagation, if the
	# remaining quota exactly matches the remaining empties, they are all forced.
	# Only report this as Rank-3 when propagation actually happened (otherwise
	# _quota_completion would have already caught this at Rank-1).
	if first_step == null and propagated_count > 0:
		var remaining_empties := 0
		for e in empties:
			var idx := line * size + e if is_row else e * size + line
			if working[idx] == EMPTY:
				remaining_empties += 1
		if remaining_empties > 0:
			var plus_needed  := half - w_plus
			var minus_needed := half - w_minus
			if plus_needed == remaining_empties:
				for e in empties:
					var idx := line * size + e if is_row else e * size + line
					if working[idx] == EMPTY:
						var af: Array[int] = [idx]
						var ltype := "row" if is_row else "col"
						first_step = SolverStep.new(
							"Rank-3 %s %d: cascade quota forces position %d to PLUS" % [ltype, line, e],
							af, PLUS, RANK_3)
						break
			elif minus_needed == remaining_empties:
				for e in empties:
					var idx := line * size + e if is_row else e * size + line
					if working[idx] == EMPTY:
						var af: Array[int] = [idx]
						var ltype := "row" if is_row else "col"
						first_step = SolverStep.new(
							"Rank-3 %s %d: cascade quota forces position %d to MINUS" % [ltype, line, e],
							af, MINUS, RANK_3)
						break

	return first_step


## Return true if placing val at position pos in the line would immediately create
## three consecutive identical values given the current (working) line state.
## Does NOT place any value — inspects neighbours directly.
static func _is_no_three_blocked_in_line(
		cells: Array[int], size: int, line: int, is_row: bool, pos: int, val: int) -> bool:
	var p1: int
	var p2: int
	var n1: int
	var n2: int
	if is_row:
		p1 = cells[line * size + (pos - 1)] if pos - 1 >= 0     else EMPTY
		p2 = cells[line * size + (pos - 2)] if pos - 2 >= 0     else EMPTY
		n1 = cells[line * size + (pos + 1)] if pos + 1 < size   else EMPTY
		n2 = cells[line * size + (pos + 2)] if pos + 2 < size   else EMPTY
	else:
		p1 = cells[(pos - 1) * size + line] if pos - 1 >= 0     else EMPTY
		p2 = cells[(pos - 2) * size + line] if pos - 2 >= 0     else EMPTY
		n1 = cells[(pos + 1) * size + line] if pos + 1 < size   else EMPTY
		n2 = cells[(pos + 2) * size + line] if pos + 2 < size   else EMPTY
	return (p1 == val and p2 == val) or (p1 == val and n1 == val) or (n1 == val and n2 == val)


## Return true if placing val at position pos in the line would violate a relation
## constraint with an immediately adjacent placed cell.
## Does NOT place any value — inspects neighbours directly.
static func _is_relation_blocked_in_line(
		cells: Array[int], size: int, line: int, is_row: bool, pos: int, val: int,
		h_relations: Dictionary, v_relations: Dictionary) -> bool:
	if is_row:
		var r := line
		var c := pos
		if c + 1 < size:
			var rel_pos := Vector2i(c, r)
			if h_relations.has(rel_pos):
				var rv: int = cells[r * size + (c + 1)]
				if rv != EMPTY:
					var rel: int = h_relations[rel_pos]
					if (rel == EQ and val != rv) or (rel == NEQ and val == rv):
						return true
		if c > 0:
			var rel_pos := Vector2i(c - 1, r)
			if h_relations.has(rel_pos):
				var lv: int = cells[r * size + (c - 1)]
				if lv != EMPTY:
					var rel: int = h_relations[rel_pos]
					if (rel == EQ and val != lv) or (rel == NEQ and val == lv):
						return true
	else:
		var col := line
		var r := pos
		if r + 1 < size:
			var rel_pos := Vector2i(col, r)
			if v_relations.has(rel_pos):
				var bv: int = cells[(r + 1) * size + col]
				if bv != EMPTY:
					var rel: int = v_relations[rel_pos]
					if (rel == EQ and val != bv) or (rel == NEQ and val == bv):
						return true
		if r > 0:
			var rel_pos := Vector2i(col, r - 1)
			if v_relations.has(rel_pos):
				var tv: int = cells[(r - 1) * size + col]
				if tv != EMPTY:
					var rel: int = v_relations[rel_pos]
					if (rel == EQ and val != tv) or (rel == NEQ and val == tv):
						return true
	return false


# ---------------------------------------------------------------------------
# Rank 4 techniques
# ---------------------------------------------------------------------------

## Single-step contradiction chain: for each empty cell, try each candidate
## value in a scratch copy, propagate all forced Rank-1 consequences until
## stable, then test the resulting board for consistency.  If one candidate
## leads to an immediate contradiction the other value is forced.
##
## This is non-recursive and bounded (one hypothesis per cell, one pass of
## Rank-1 propagation per hypothesis).  It finds deductions that are invisible
## to individual-line analysis because the contradiction spans multiple lines.
static func _global_quota_chain(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary) -> SolverStep:
	for r in size:
		for c in size:
			var idx := r * size + c
			if cells[idx] != EMPTY:
				continue
			for val in [PLUS, MINUS]:
				var trial: Array[int] = cells.duplicate()
				trial[idx] = val
				# Propagate all Rank-1 through Rank-3 forced moves until stable.
				# Using only Rank-1 here is insufficient: by the time Rank-4 runs,
				# Rank-1 is already globally exhausted so trial propagation would
				# advance zero steps.  Rank-2 and Rank-3 propagation is needed to
				# expose the contradictions that Expert-level puzzles require.
				var progress := true
				while progress:
					progress = false
					var s: SolverStep = _quota_completion(size, trial)
					if s == null:
						s = _adjacent_pair_prevention(size, trial)
					if s == null:
						s = _sandwich_rule(size, trial)
					if s == null:
						s = _direct_relation(size, trial, h_relations, v_relations)
					if s == null:
						s = _combined_local(size, trial, h_relations, v_relations)
					if s == null:
						s = _relation_propagation_rank2(size, trial, h_relations, v_relations)
					if s == null:
						s = _relation_chain_rank3(size, trial, h_relations, v_relations)
					if s != null:
						trial[s.affected_cells[0]] = s.result_value
						progress = true
				# If the fully-propagated trial violates any constraint, the
				# opposite value is forced.
				if not is_consistent(size, trial, h_relations, v_relations):
					var forced := MINUS if val == PLUS else PLUS
					var af: Array[int] = [idx]
					var forced_str := "+" if forced == PLUS else "-"
					var tried_str  := "+" if val   == PLUS else "-"
					return SolverStep.new(
						"Rank-4 chain (%d,%d): placing %s leads to contradiction, forced %s" % [c, r, tried_str, forced_str],
						af, forced, RANK_4)
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
