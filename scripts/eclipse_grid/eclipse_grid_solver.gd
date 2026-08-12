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
## known_forced_steps may contain non-branching steps returned by analyze() for
## these exact inputs; they reduce the residual exhaustive search without
## changing its solution set.
static func count_solutions(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		max_count: int = 2,
		cancel_check: Callable = Callable(),
		known_forced_steps: Array = []) -> int:
	if cells.size() != size * size \
			or not is_consistent(size, cells, h_relations, v_relations):
		return 0
	if cancel_check.is_valid() and cancel_check.call():
		return 0
	var working: Array[int] = cells.duplicate()
	for step in known_forced_steps:
		if cancel_check.is_valid() and cancel_check.call():
			return 0
		var idx: int = step.affected_cells[0]
		if working[idx] != EMPTY:
			return 0
		working[idx] = step.result_value
	if not working.has(EMPTY):
		return 1 if validate(
				size, working, h_relations, v_relations) else 0

	var valid_masks: Array[int] = _valid_line_masks(size)
	var row_candidates: Array[Array] = []
	for row in size:
		var candidates: Array[int] = []
		for mask in valid_masks:
			if _mask_matches_row(
					size, working, row, mask, h_relations):
				candidates.append(mask)
		if candidates.is_empty():
			return 0
		row_candidates.append(candidates)

	var vertical_eq: Array[int] = []
	var vertical_neq: Array[int] = []
	vertical_eq.resize(size - 1)
	vertical_eq.fill(0)
	vertical_neq.resize(size - 1)
	vertical_neq.fill(0)
	for pos in v_relations:
		var cell: Vector2i = pos
		if v_relations[pos] == EQ:
			vertical_eq[cell.y] |= 1 << cell.x
		else:
			vertical_neq[cell.y] |= 1 << cell.x

	var plus_counts: Array[int] = []
	plus_counts.resize(size)
	plus_counts.fill(0)
	var count_space := 1
	for _column in size:
		count_space *= size / 2 + 1
	var memo: Dictionary = {}
	var cancelled := [false]
	return _count_row_masks(
			size, row_candidates, vertical_eq, vertical_neq, 0, 0, 0,
			plus_counts, count_space, max_count, memo, cancel_check, cancelled)


## Exhaustively count valid row-mask sequences. Memoization collapses prefixes
## with identical column quotas and trailing rows into the same exact state.
static func _count_row_masks(
		size: int,
		row_candidates: Array[Array],
		vertical_eq: Array[int],
		vertical_neq: Array[int],
		row: int,
		prev2: int,
		prev1: int,
		plus_counts: Array[int],
		count_space: int,
		max_count: int,
		memo: Dictionary,
		cancel_check: Callable,
		cancelled: Array) -> int:
	if cancel_check.is_valid() and cancel_check.call():
		cancelled[0] = true
		return 0
	if row == size:
		return 1

	var counts_code := 0
	var count_base := size / 2 + 1
	for count in plus_counts:
		counts_code = counts_code * count_base + count
	var mask_limit := 1 << size
	var key := (((row * mask_limit + prev2) * mask_limit + prev1) \
			* count_space + counts_code)
	if memo.has(key):
		return memo[key]

	var total := 0
	var full_mask := mask_limit - 1
	var remaining := size - row - 1
	for mask in row_candidates[row]:
		if cancel_check.is_valid() and cancel_check.call():
			cancelled[0] = true
			break
		if row > 0:
			var differences: int = prev1 ^ mask
			if differences & vertical_eq[row - 1]:
				continue
			if ((~differences) & full_mask) & vertical_neq[row - 1]:
				continue
		if row > 1:
			if (prev2 & prev1 & mask) != 0 \
					or ((~(prev2 | prev1 | mask)) & full_mask) != 0:
				continue

		var feasible := true
		for col in size:
			if mask & (1 << col):
				plus_counts[col] += 1
			if plus_counts[col] > size / 2 \
					or plus_counts[col] + remaining < size / 2:
				feasible = false
		if feasible:
			total += _count_row_masks(
					size, row_candidates, vertical_eq, vertical_neq, row + 1,
					prev1, mask, plus_counts, count_space,
					max_count, memo, cancel_check, cancelled)
		for col in size:
			if mask & (1 << col):
				plus_counts[col] -= 1
		if cancelled[0] or total >= max_count:
			total = mini(total, max_count)
			break

	if not cancelled[0]:
		memo[key] = total
	return total


static func _valid_line_masks(size: int) -> Array[int]:
	var masks: Array[int] = []
	for mask in (1 << size):
		if _mask_plus_count(mask, size) != size / 2:
			continue
		var valid := true
		for col in range(size - 2):
			var triple := (mask >> col) & 7
			if triple == 0 or triple == 7:
				valid = false
				break
		if valid:
			masks.append(mask)
	return masks


static func _mask_matches_row(
		size: int,
		cells: Array[int],
		row: int,
		mask: int,
		h_relations: Dictionary) -> bool:
	for col in size:
		var given := cells[row * size + col]
		var value := PLUS if mask & (1 << col) else MINUS
		if given != EMPTY and given != value:
			return false
	for col in range(size - 1):
		var pos := Vector2i(col, row)
		if not h_relations.has(pos):
			continue
		var same := bool(mask & (1 << col)) \
				== bool(mask & (1 << (col + 1)))
		var relation: int = h_relations[pos]
		if (relation == EQ and not same) \
				or (relation == NEQ and same):
			return false
	return true


static func _mask_plus_count(mask: int, size: int) -> int:
	var count := 0
	for col in size:
		if mask & (1 << col):
			count += 1
	return count


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
	var valid_masks := _valid_line_masks(size)

	while true:
		if cancel_check.is_valid() and cancel_check.call():
			return result
		var step: SolverStep = _find_next_step(
				size, cells, h_relations, v_relations, valid_masks)
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


## Return whether deterministic human deductions can refill all target cells.
## Callers may use this when the puzzle before removing one clue is already
## known to solve within max_rank: once the removed clue's endpoints have been
## recovered, the known solution path remains available from a stronger state.
static func can_recover_cells(
		size: int,
		initial_cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		targets: Array[int],
		max_rank: int = RANK_4,
		cancel_check: Callable = Callable(),
		valid_masks: Array[int] = []) -> bool:
	var cells: Array[int] = initial_cells.duplicate()
	if valid_masks.is_empty():
		valid_masks = _valid_line_masks(size)
	while true:
		var recovered := true
		for idx in targets:
			if cells[idx] == EMPTY:
				recovered = false
				break
		if recovered:
			return true
		if cancel_check.is_valid() and cancel_check.call():
			return false
		var step: SolverStep = _find_next_step(
				size, cells, h_relations, v_relations, valid_masks)
		if step == null or step.rank > max_rank:
			return false
		cells[step.affected_cells[0]] = step.result_value
	return false


## Find the next deducible cell using human-logic techniques in rank order.
static func _find_next_step(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		valid_masks: Array[int] = []) -> SolverStep:
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

	# An empty EQ pair contributes glyphs in twos, so a line needing exactly
	# one of a glyph forces the pair to the opposite glyph.
	step = _eq_pair_quota_rank2(size, cells, h_relations, v_relations)
	if step:
		return step

	# Rank 3 techniques
	step = _relation_chain_rank3(size, cells, h_relations, v_relations)
	if step:
		return step

	# Rank 4 techniques
	step = _global_quota_chain(
			size, cells, h_relations, v_relations, valid_masks)
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


static func _eq_pair_quota_rank2(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary) -> SolverStep:
	for r in size:
		var step := _line_eq_pair_quota_rank2(
				size, cells, h_relations, v_relations, r, true)
		if step:
			return step
	for c in size:
		var step := _line_eq_pair_quota_rank2(
				size, cells, h_relations, v_relations, c, false)
		if step:
			return step
	return null


static func _line_eq_pair_quota_rank2(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		line: int,
		is_row: bool) -> SolverStep:
	var plus_count := 0
	var minus_count := 0
	for i in size:
		var idx := line * size + i if is_row else i * size + line
		if cells[idx] == PLUS:
			plus_count += 1
		elif cells[idx] == MINUS:
			minus_count += 1

	var plus_needed := size / 2 - plus_count
	var minus_needed := size / 2 - minus_count
	if plus_needed != 1 and minus_needed != 1:
		return null
	if plus_needed == 1 and minus_needed == 1:
		return null

	var rel_dict := h_relations if is_row else v_relations
	var ltype := "row" if is_row else "col"
	for p in range(size - 1):
		var idx := line * size + p if is_row else p * size + line
		var next_idx := line * size + p + 1 if is_row else (p + 1) * size + line
		var rel_pos := Vector2i(p, line) if is_row else Vector2i(line, p)
		if cells[idx] != EMPTY or cells[next_idx] != EMPTY \
				or rel_dict.get(rel_pos, 0) != EQ:
			continue
		var forced := MINUS if plus_needed == 1 else PLUS
		var af: Array[int] = [idx]
		return SolverStep.new(
				"Rank-2 %s %d: EQ(%d,%d) would overflow quota" % [
					ltype, line, p, p + 1],
				af, forced, RANK_2)
	return null


# ---------------------------------------------------------------------------
# Rank 3 techniques
# ---------------------------------------------------------------------------

static func _relation_chain_rank3(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary) -> SolverStep:
	# For each row and column, apply direct EQ no-three patterns to find cells
	# forced by an EQ clue interacting with a filled neighbour.
	for r in size:
		var step := _line_propagate_rank3(size, cells, h_relations, v_relations, r, true)
		if step:
			return step
	for c in size:
		var step := _line_propagate_rank3(size, cells, h_relations, v_relations, c, false)
		if step:
			return step
	return null


## Rank-3 technique: direct EQ-relation no-three forcing.
##
## Scans each line for adjacent pairs of empty cells that share an EQ clue and
## applies two non-speculative patterns derived directly from the current board
## state — no hypothetical arrays, no enumeration of completions:
##
##   Pattern A — EQ left-neighbour:
##     cells[p-1] = V (filled), EQ(p, p+1), cells[p] = cells[p+1] = EMPTY.
##     Placing V at cells[p] would, via EQ, force cells[p+1] = V, creating the
##     triple (p-1, p, p+1) = V,V,V → no-three violation.  Force cells[p] = ¬V.
##
##   Pattern B — EQ right-neighbour:
##     cells[p+2] = V (filled), EQ(p, p+1), cells[p] = cells[p+1] = EMPTY.
##     Placing V at cells[p+1] would, via EQ, force cells[p] = V, creating the
##     triple (p, p+1, p+2) = V,V,V → no-three violation.  Force cells[p+1] = ¬V.
##
## Does NOT modify cells[].
static func _line_propagate_rank3(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		line: int,
		is_row: bool) -> SolverStep:
	var rel_dict := h_relations if is_row else v_relations
	var ltype := "row" if is_row else "col"

	for p in range(size - 1):
		var idxP  := line * size + p       if is_row else p       * size + line
		var idxP1 := line * size + (p + 1) if is_row else (p + 1) * size + line
		if cells[idxP] != EMPTY or cells[idxP1] != EMPTY:
			continue
		var rel_pos := Vector2i(p, line) if is_row else Vector2i(line, p)
		if not rel_dict.has(rel_pos) or rel_dict[rel_pos] != EQ:
			continue

		# Pattern A: filled left neighbour forces cells[p] = ¬V.
		if p >= 1:
			var idxPrev := line * size + (p - 1) if is_row else (p - 1) * size + line
			if cells[idxPrev] != EMPTY:
				var forced_v: int = _opposite(cells[idxPrev])
				var af: Array[int] = [idxP]
				return SolverStep.new(
					"Rank-3 %s %d: EQ(%d,%d) left-neighbour[%d]=%s forces pos %d=%s" % [
						ltype, line, p, p + 1, p - 1,
						"+" if cells[idxPrev] == PLUS else "-",
						p, "+" if forced_v == PLUS else "-"],
					af, forced_v, RANK_3)

		# Pattern B: filled right neighbour forces cells[p+1] = ¬V.
		if p + 2 < size:
			var idxNext := line * size + (p + 2) if is_row else (p + 2) * size + line
			if cells[idxNext] != EMPTY:
				var forced_v: int = _opposite(cells[idxNext])
				var af: Array[int] = [idxP1]
				return SolverStep.new(
					"Rank-3 %s %d: EQ(%d,%d) right-neighbour[%d]=%s forces pos %d=%s" % [
						ltype, line, p, p + 1, p + 2,
						"+" if cells[idxNext] == PLUS else "-",
						p + 1, "+" if forced_v == PLUS else "-"],
					af, forced_v, RANK_3)

	return null


# ---------------------------------------------------------------------------
# Rank 4 techniques
# ---------------------------------------------------------------------------

## Rank-4 technique: k≥3 cross-line completion forcing.
##
## For each row (or column) that still has 3 or more empty cells after
## Rank-1/2/3 exhaustion, enumerates all complete assignments of those cells
## and filters each candidate by TWO independent constraint sets:
##
##   (a) In-line: the line's own quota, no-three-consecutive, and all EQ/NEQ
##       relation clues within the line.
##
##   (b) Cross-line: each assigned cell is tested against its perpendicular
##       line using _check_perp_feasibility, which includes a quota-cascade
##       step: if the assignment exhausts the perpendicular line's quota,
##       the remaining empties are forced to the opposite type and the
##       resulting state is re-validated for no-three and relation clues.
##       This detects infeasibilities invisible to the immediate per-cell
##       check — for example, a v-relation NEQ between two positions that
##       are both force-filled with the same value when quota is exhausted.
##
## If every valid (in-line + cross-line) assignment places the same value at
## some position, that cell is forced at RANK_4.
##
## Restores every temporary assignment before returning.
static func _global_quota_chain(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		valid_masks: Array[int] = []) -> SolverStep:
	var half := size / 2
	if valid_masks.is_empty():
		valid_masks = _valid_line_masks(size)
	# Row analysis: lines with 3 or more empty cells.
	for r in size:
		var empties: Array[int] = []
		for c in size:
			if cells[r * size + c] == EMPTY:
				empties.append(c)
		if empties.size() < 3:
			continue
		var step := _line_completion_rank4(
				size, cells, h_relations, v_relations, r, empties, true,
				half, valid_masks)
		if step:
			return step
	# Column analysis: lines with 3 or more empty cells.
	for c in size:
		var empties: Array[int] = []
		for r in size:
			if cells[r * size + c] == EMPTY:
				empties.append(r)
		if empties.size() < 3:
			continue
		var step := _line_completion_rank4(
				size, cells, h_relations, v_relations, c, empties, false,
				half, valid_masks)
		if step:
			return step
	return null


## Extended perpendicular-line feasibility check used by _line_completion_rank4.
##
## After one cell has been placed into [param trial] by a primary-line combo,
## this function checks whether the perpendicular line [param perp] remains
## feasible.  It extends the immediate _check_partial_line check with a
## quota-cascade step:
##
##   If the placed value brings the perpendicular line's PLUS (or MINUS) count
##   to exactly half, all remaining empty cells in that line are logically
##   forced to the opposite type.  The resulting fully-determined state is then
##   re-validated for no-three and every in-line relation clue.
##
## This detects infeasibilities that are invisible to _check_partial_line alone
## (which only sees the one newly-placed cell) — for example, a v-relation NEQ
## clue between two positions that are both force-filled with MINUS when the
## PLUS quota is exhausted by the primary-line assignment.  Such a violation is
## only visible after propagating the quota-forced consequences.
##
## Does NOT modify [param trial].
static func _check_perp_feasibility(
		trial: Array[int],
		size: int,
		perp: int,
		is_row: bool,
		h_relations: Dictionary,
		v_relations: Dictionary) -> bool:
	# 1. Immediate quota / no-three / relation check.
	if not _check_partial_line(trial, size, perp, is_row, h_relations, v_relations):
		return false
	var half := size / 2
	# 2. Count quota and collect remaining empties in the perpendicular line.
	var plus := 0
	var minus := 0
	var empty_mask := 0
	for i in size:
		var idx: int = perp * size + i if is_row else i * size + perp
		match trial[idx]:
			PLUS:  plus += 1
			MINUS: minus += 1
			_:     empty_mask |= 1 << i
	if empty_mask == 0:
		return true
	# 3. Determine if quota exhaustion forces all remaining empties.
	var forced := EMPTY
	if plus == half:
		forced = MINUS
	elif minus == half:
		forced = PLUS
	if forced == EMPTY:
		return true  # No cascade possible at this step.
	# 4. Apply forced values in place, then restore the still-empty positions.
	for pos in size:
		if empty_mask & (1 << pos):
			var idx: int = perp * size + pos if is_row else pos * size + perp
			trial[idx] = forced
	var feasible := _check_partial_line(
			trial, size, perp, is_row, h_relations, v_relations)
	for pos in size:
		if empty_mask & (1 << pos):
			var idx: int = perp * size + pos if is_row else pos * size + perp
			trial[idx] = EMPTY
	return feasible


## Enumerate all valid in-line complete assignments for a line's k empty
## cells; return a forced step if all valid assignments agree on one cell.
##
## [param line]    row (is_row=true) or column (is_row=false) index
## [param empties] indices of empty cells within the line, in order
## [param is_row]  direction of enumeration
##
## Validity of a candidate assignment is determined by two checks:
##
##   (a) In-line (_check_partial_line): quota, no-three, and all EQ/NEQ
##       relation clues within the primary line.
##
##   (b) Cross-line (_check_perp_feasibility): each assigned cell is also
##       tested against its perpendicular line, including a quota-cascade
##       step that propagates forced consequences and re-validates relation
##       clues.  This catches infeasibilities invisible to the immediate
##       per-cell check — e.g. a v-rel NEQ between two cells that are both
##       forced to MINUS after the primary assignment exhausts column quota.
##
## Capped at k≤10 (2^10 = 1024 combos) to bound work; returns null for
## wider lines.  Does NOT modify cells[].
static func _line_completion_rank4(
		size: int,
		cells: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		line: int,
		empties: Array[int],
		is_row: bool,
		half: int,
		valid_masks: Array[int]) -> SolverStep:
	var k := empties.size()
	if k > 10:
		return null
	# Count the quota already satisfied by fixed (non-empty) cells.
	var plus_fixed := 0
	var minus_fixed := 0
	for i in size:
		var v: int = cells[line * size + i] if is_row else cells[i * size + line]
		if v == PLUS:
			plus_fixed += 1
		elif v == MINUS:
			minus_fixed += 1
	var plus_needed  := half - plus_fixed
	var minus_needed := half - minus_fixed
	if plus_needed < 0 or minus_needed < 0 or plus_needed + minus_needed != k:
		return null
	# Track which values appear across all valid assignments per position.
	var can_plus:  Array[bool] = []
	var can_minus: Array[bool] = []
	for _i in k:
		can_plus.append(false)
		can_minus.append(false)
	# Candidate values are restored before each iteration completes, so the
	# caller's working board can safely serve as the trial buffer.
	var trial: Array[int] = cells
	# Each primary-line cell belongs to a distinct perpendicular line, so its
	# perpendicular feasibility depends only on that cell's value. Compute the
	# two possibilities once instead of repeating them for every combination.
	var perp_plus: Array[bool] = []
	var perp_minus: Array[bool] = []
	for i in k:
		var idx: int = line * size + empties[i] if is_row else empties[i] * size + line
		var perp := empties[i]
		trial[idx] = PLUS
		perp_plus.append(_check_perp_feasibility(
				trial, size, perp, not is_row, h_relations, v_relations))
		trial[idx] = MINUS
		perp_minus.append(_check_perp_feasibility(
				trial, size, perp, not is_row, h_relations, v_relations))
		trial[idx] = EMPTY
	var combos: Array[int] = []
	if k >= 7:
		for mask in valid_masks:
			var matches := true
			var combo := 0
			for i in size:
				var idx: int = line * size + i if is_row else i * size + line
				var value := PLUS if mask & (1 << i) else MINUS
				if cells[idx] != EMPTY and cells[idx] != value:
					matches = false
					break
			if not matches:
				continue
			for i in k:
				if mask & (1 << empties[i]):
					combo |= 1 << i
			combos.append(combo)
	else:
		for combo in (1 << k):
			if _mask_plus_count(combo, k) == plus_needed:
				combos.append(combo)
	for combo in combos:
		# Place this assignment into the trial copy.
		for i in k:
			var idx: int = line * size + empties[i] if is_row else empties[i] * size + line
			trial[idx] = PLUS if ((combo >> i) & 1) else MINUS
		# In-line validation: quota, no-three, and all in-line relation clues.
		var ok := _check_partial_line(trial, size, line, is_row, h_relations, v_relations)
		# Cross-line validation: each assigned cell must also be consistent
		# with its perpendicular line.  _check_perp_feasibility extends the
		# immediate quota/no-three/relation check with a cascade step: if the
		# new value exhausts the perpendicular line's quota, the remaining
		# empties are forced to the opposite type and the resulting state is
		# re-validated — catching relation violations that only emerge after
		# propagating those forced consequences.
		if ok:
			for i in k:
				var feasible := perp_plus[i] if (combo >> i) & 1 else perp_minus[i]
				if not feasible:
					ok = false
					break
		# Restore trial before using the result.
		for i in k:
			var idx: int = line * size + empties[i] if is_row else empties[i] * size + line
			trial[idx] = EMPTY
		if not ok:
			continue
		# Record which values this valid assignment uses.
		for i in k:
			if (combo >> i) & 1:
				can_plus[i] = true
			else:
				can_minus[i] = true
		var all_unforced := true
		for i in k:
			if not can_plus[i] or not can_minus[i]:
				all_unforced = false
				break
		if all_unforced:
			return null
	# Return the first position forced to a single value.
	var ltype := "row" if is_row else "col"
	for i in k:
		if can_plus[i] and not can_minus[i]:
			var idx: int = line * size + empties[i] if is_row else empties[i] * size + line
			var af: Array[int] = [idx]
			return SolverStep.new(
				"Rank-4 %s %d pos %d: all valid completions force PLUS" % [ltype, line, empties[i]],
				af, PLUS, RANK_4)
		if can_minus[i] and not can_plus[i]:
			var idx: int = line * size + empties[i] if is_row else empties[i] * size + line
			var af: Array[int] = [idx]
			return SolverStep.new(
				"Rank-4 %s %d pos %d: all valid completions force MINUS" % [ltype, line, empties[i]],
				af, MINUS, RANK_4)
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
