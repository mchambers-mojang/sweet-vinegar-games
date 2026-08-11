class_name EclipseGridGenerator
extends RefCounted

## Generates Eclipse Grid puzzles deterministically from a size and seed.
##
## generate(size, seed, cancel_check) → Dictionary with keys:
##   size, seed, givens (Array[int]), h_relations (Dictionary), v_relations (Dictionary),
##   solution (Array[int]), analysis (EclipseGridSolver.Analysis), max_rank (int)
## Returns {} on failure or cancellation.

const EMPTY := EclipseGridSolver.EMPTY
const PLUS  := EclipseGridSolver.PLUS
const MINUS := EclipseGridSolver.MINUS
const EQ    := EclipseGridSolver.EQ
const NEQ   := EclipseGridSolver.NEQ

## Maximum attempts to find an acceptable puzzle per call.
## Expert (10×10) puzzles require Rank-4 reasoning, which occurs less
## frequently; allow more attempts so generation succeeds reliably.
const MAX_ATTEMPTS := 30
const MAX_ATTEMPTS_EXPERT := 100


## Required maximum solver rank for each size.
## Size 4 → rank 1, size 6 → rank 2, size 8 → rank 3, size 10 → rank 4.
static func required_rank(size: int) -> int:
	match size:
		4:  return 1
		6:  return 2
		8:  return 3
		_:  return 4


## Generate a puzzle.
##
## [param cancel_check] callable → bool; return true to abort generation.
## Returns a non-empty Dictionary on success, or {} on failure/cancellation.
static func generate(size: int, seed: int, cancel_check: Callable = Callable()) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	# Precompute valid rows once for this size.
	var valid_rows: Array[Array] = _get_valid_rows(size)

	for _attempt in (MAX_ATTEMPTS_EXPERT if size >= 10 else MAX_ATTEMPTS):
		if cancel_check.is_valid() and cancel_check.call():
			return {}

		# Step 1: Build a complete valid board row-by-row (fast).
		var solution: Array[int] = _build_complete_board(size, valid_rows, rng, cancel_check)
		if solution.is_empty():
			continue

		# Step 2: Select relation clues.
		var h_relations: Dictionary = {}
		var v_relations: Dictionary = {}
		_add_relation_clues(size, solution, h_relations, v_relations, rng)

		if cancel_check.is_valid() and cancel_check.call():
			return {}

		# Step 3: Minimize clues using human-solver as oracle (fast).
		var givens: Array[int] = _minimize_givens(
				size, solution, h_relations, v_relations, rng,
				required_rank(size), cancel_check)
		if givens.is_empty():
			continue

		if cancel_check.is_valid() and cancel_check.call():
			return {}

		# Step 3b: Minimize relation clues with the same oracle.
		_minimize_relations(size, givens, h_relations, v_relations, cancel_check)
		if cancel_check.is_valid() and cancel_check.call():
			return {}

		# Step 4: Analyse difficulty rank before the more expensive exhaustive
		# uniqueness proof, so rejected difficulty tiers do not pay for it.
		var analysis: EclipseGridSolver.Analysis = EclipseGridSolver.analyze(
				size, givens, h_relations, v_relations, cancel_check)
		if cancel_check.is_valid() and cancel_check.call():
			return {}
		# Enforce exact difficulty tier: also require that the human solver can
		# uniquely complete the puzzle (analysis.is_unique) — this ensures hints
		# and auto-complete always work correctly and that the puzzle is not merely
		# unique by exhaustive search but also human-logic-solvable.
		if not analysis.is_unique or analysis.max_rank != required_rank(size):
			continue

		# Step 5: Prove uniqueness exhaustively after applying the already
		# established non-branching deductions.
		var unique := EclipseGridSolver.count_solutions(
				size, givens, h_relations, v_relations, 2, cancel_check,
				analysis.steps) == 1
		if cancel_check.is_valid() and cancel_check.call():
			return {}
		if not unique:
			continue

		return {
			"size": size,
			"seed": seed,
			"givens": givens,
			"h_relations": h_relations,
			"v_relations": v_relations,
			"solution": solution,
			"analysis": analysis,
			"max_rank": analysis.max_rank,
		}

	return {}


# ---------------------------------------------------------------------------
# Valid row enumeration
# ---------------------------------------------------------------------------

## Enumerate all valid row patterns for a given size.
## A valid row has exactly size/2 PLUS and size/2 MINUS with no 3 consecutive.
static func _get_valid_rows(size: int) -> Array[Array]:
	var result: Array[Array] = []
	var current: Array[int] = []
	_enumerate_rows(size, current, 0, 0, result)
	return result


static func _enumerate_rows(
		size: int,
		current: Array[int],
		plus_count: int,
		minus_count: int,
		result: Array[Array]) -> void:
	if current.size() == size:
		if plus_count == size / 2 and minus_count == size / 2:
			result.append(current.duplicate())
		return
	var remaining := size - current.size()
	var half := size / 2
	for val in [PLUS, MINUS]:
		var np := plus_count + (1 if val == PLUS else 0)
		var nm := minus_count + (1 if val == MINUS else 0)
		# Prune: can't meet quota
		if np > half or nm > half:
			continue
		# Prune: remaining cells not enough for quota
		if (half - np) > (remaining - 1) or (half - nm) > (remaining - 1):
			continue
		# No-three check
		var n := current.size()
		if n >= 2 and current[n - 1] == val and current[n - 2] == val:
			continue
		current.append(val)
		_enumerate_rows(size, current, np, nm, result)
		current.pop_back()


# ---------------------------------------------------------------------------
# Board construction (row-by-row)
# ---------------------------------------------------------------------------

static func _build_complete_board(
		size: int,
		valid_rows: Array[Array],
		rng: RandomNumberGenerator,
		cancel_check: Callable = Callable()) -> Array[int]:
	var cells: Array[int] = []
	cells.resize(size * size)
	cells.fill(EMPTY)
	if _place_rows(size, cells, 0, valid_rows, rng, cancel_check):
		return cells
	return []


static func _place_rows(
		size: int,
		cells: Array[int],
		row: int,
		valid_rows: Array[Array],
		rng: RandomNumberGenerator,
		cancel_check: Callable = Callable()) -> bool:
	if cancel_check.is_valid() and cancel_check.call():
		return false
	if row == size:
		return true  # Board complete

	# Shuffle valid rows for randomness
	var shuffled: Array[Array] = valid_rows.duplicate()
	_shuffle_array(shuffled, rng)

	for row_pattern in shuffled:
		if cancel_check.is_valid() and cancel_check.call():
			return false
		# Place the row
		for c in size:
			cells[row * size + c] = row_pattern[c]
		# Check column consistency up to this row
		if _columns_consistent_through_row(size, cells, row):
			if _place_rows(size, cells, row + 1, valid_rows, rng, cancel_check):
				return true
		# Undo
		for c in size:
			cells[row * size + c] = EMPTY

	return false


## Check that all columns are locally consistent through the given row.
static func _columns_consistent_through_row(size: int, cells: Array[int], through_row: int) -> bool:
	var half := size / 2
	for c in size:
		var plus := 0
		var minus := 0
		var run := 0
		var prev := EMPTY
		for r in range(through_row + 1):
			var v: int = cells[r * size + c]
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


# ---------------------------------------------------------------------------
# Relation clue selection
# ---------------------------------------------------------------------------

static func _add_relation_clues(
		size: int,
		solution: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var all_h: Array[Vector2i] = []
	var all_v: Array[Vector2i] = []
	for r in size:
		for c in range(size - 1):
			all_h.append(Vector2i(c, r))
	for r in range(size - 1):
		for c in size:
			all_v.append(Vector2i(c, r))

	_shuffle_array(all_h, rng)
	_shuffle_array(all_v, rng)

	# A sparse relation set gives the minimizers a useful starting point without
	# making them repeatedly re-analyse dozens of clues that will be discarded.
	var min_density := 0.12 if size >= 10 else 0.08
	var max_density := 0.12 if size >= 10 else 0.15
	var num_h := rng.randi_range(
			maxi(1, int(all_h.size() * min_density)),
			maxi(1, int(all_h.size() * max_density)))
	var num_v := rng.randi_range(
			maxi(1, int(all_v.size() * min_density)),
			maxi(1, int(all_v.size() * max_density)))
	num_h = mini(num_h, all_h.size())
	num_v = mini(num_v, all_v.size())

	for i in num_h:
		var pos: Vector2i = all_h[i]
		var lv: int = solution[pos.y * size + pos.x]
		var rv: int = solution[pos.y * size + (pos.x + 1)]
		h_relations[pos] = EQ if lv == rv else NEQ

	for i in num_v:
		var pos: Vector2i = all_v[i]
		var tv: int = solution[pos.y * size + pos.x]
		var bv: int = solution[(pos.y + 1) * size + pos.x]
		v_relations[pos] = EQ if tv == bv else NEQ


# ---------------------------------------------------------------------------
# Clue minimization (human-solver guided)
# ---------------------------------------------------------------------------

## Minimize given cells using the human solver as the primary oracle.
## A cell is kept if removing it makes the human solver unable to finish or
## raises the puzzle above its size's difficulty tier.
static func _minimize_givens(
		size: int,
		solution: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		rng: RandomNumberGenerator,
		max_rank: int,
		cancel_check: Callable) -> Array[int]:
	var givens: Array[int] = solution.duplicate()

	var indices: Array[int] = []
	for i in givens.size():
		indices.append(i)
	_shuffle_array(indices, rng)

	# One greedy pass is sufficient: removing additional clues cannot make a
	# previously necessary given become human-solvable within the rank ceiling.
	for idx in indices:
		if cancel_check.is_valid() and cancel_check.call():
			return []
		var saved: int = givens[idx]
		givens[idx] = EMPTY
		var analysis: EclipseGridSolver.Analysis = EclipseGridSolver.analyze(
				size, givens, h_relations, v_relations, cancel_check)
		if cancel_check.is_valid() and cancel_check.call():
			return []
		if not analysis.is_unique or analysis.max_rank > max_rank:
			givens[idx] = saved

	return givens


## Minimize relation clues using the human solver as oracle.
## A relation is removed only if the human solver can still uniquely determine
## the full solution without it.
static func _minimize_relations(
		size: int,
		givens: Array[int],
		h_relations: Dictionary,
		v_relations: Dictionary,
		cancel_check: Callable) -> void:
	for dict in [h_relations, v_relations]:
		var keys: Array = dict.keys().duplicate()
		for key in keys:
			if cancel_check.is_valid() and cancel_check.call():
				return
			var saved: int = dict[key]
			dict.erase(key)
			var analysis: EclipseGridSolver.Analysis = EclipseGridSolver.analyze(
					size, givens, h_relations, v_relations, cancel_check)
			if cancel_check.is_valid() and cancel_check.call():
				return
			if not analysis.is_unique:
				dict[key] = saved


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

static func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
