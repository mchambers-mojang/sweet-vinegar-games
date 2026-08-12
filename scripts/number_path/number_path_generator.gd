class_name NumberPathGenerator
extends RefCounted

## Generates Number Path puzzles for each tier.
## Returns deterministic results given the same tier + seed.
## Generation flow:
##   1. Build a randomized Hamiltonian path by construction.
##   2. Place barriers (Hard/Expert) that are consistent with the path.
##   3. Minimize checkpoints while the puzzle stays solvable at exactly the
##      tier's required reasoning rank (sound deductions also prove uniqueness).
##   4. Confirm the solver reaches the solution using exactly that rank.
##   5. Return the puzzle data or {} on failure/cancellation.

## Tier → board size
const TIER_SIZES := {
	NumberPathLogic.TIER_EASY: 5,
	NumberPathLogic.TIER_MEDIUM: 6,
	NumberPathLogic.TIER_HARD: 7,
	NumberPathLogic.TIER_EXPERT: 8,
}

## Tier → minimum checkpoints (including start and end)
const TIER_CHECKPOINT_COUNT := {
	NumberPathLogic.TIER_EASY: 6,
	NumberPathLogic.TIER_MEDIUM: 7,
	NumberPathLogic.TIER_HARD: 7,
	NumberPathLogic.TIER_EXPERT: 8,
}

## Tier → barrier count
const TIER_BARRIER_COUNT := {
	NumberPathLogic.TIER_EASY: 0,
	NumberPathLogic.TIER_MEDIUM: 0,
	NumberPathLogic.TIER_HARD: 8,
	NumberPathLogic.TIER_EXPERT: 8,
}

## Tier → the exact maximum solver reasoning rank the puzzle must require
const TIER_REQUIRED_RANK := {
	NumberPathLogic.TIER_EASY: NumberPathSolver.RANK_FORCED,
	NumberPathLogic.TIER_MEDIUM: NumberPathSolver.RANK_LOCAL,
	NumberPathLogic.TIER_HARD: NumberPathSolver.RANK_REGION,
	NumberPathLogic.TIER_EXPERT: NumberPathSolver.RANK_GLOBAL,
}

const MAX_GENERATION_ATTEMPTS := 50

## Depth cap for the forced-only look-ahead the solver uses to grade Rank-4
## deductions (only Expert requires Rank 4). A real human resolves a Rank-4
## branch by following a short non-branching chain, not an unbounded one, so a
## small cap both matches how the puzzles are meant to be solved and keeps the
## per-solve cost — and therefore generation time — down. Empirically this value
## still yields exact Rank-4 puzzles for every tier seed with no loss of yield.
const RANK4_ROLLOUT_DEPTH := 4


## Generate a puzzle for the given tier and seed.
## cancel_check: Callable() -> bool  (return true to abort)
## Returns {width, height, tier, seed, checkpoints, barriers, solution_path,
##          solver_steps, solver_max_rank} or {} on failure/cancellation.
static func generate(tier: int, seed: int, cancel_check: Callable = Callable()) -> Dictionary:
	var size: int = TIER_SIZES.get(tier, 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	for attempt in range(MAX_GENERATION_ATTEMPTS):
		if cancel_check.is_valid() and cancel_check.call():
			return {}

		var attempt_seed := int(rng.randi())
		var result := _try_generate(size, tier, attempt_seed, cancel_check)
		if not result.is_empty():
			result["seed"] = seed
			result["tier"] = tier
			return result

	return {}


static func _try_generate(size: int, tier: int, attempt_seed: int, cancel_check: Callable) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = attempt_seed

	# Step 1: Build a Hamiltonian path
	var path := _build_hamiltonian_path(size, rng, cancel_check)
	if path.is_empty():
		return {}
	if cancel_check.is_valid() and cancel_check.call():
		return {}

	# Step 2: Place barriers (Hard/Expert only)
	var barriers: Array[Dictionary] = []
	var barrier_count: int = TIER_BARRIER_COUNT.get(tier, 0)
	if barrier_count > 0:
		barriers = _place_barriers(size, path, barrier_count, rng, cancel_check)
		if cancel_check.is_valid() and cancel_check.call():
			return {}

	# Step 3: Begin with the complete path as checkpoints, then remove clues
	# while preserving the unique human solution. Randomly selecting only the
	# target clue count almost never describes a unique Hamiltonian path.
	var required_rank: int = TIER_REQUIRED_RANK.get(tier, NumberPathSolver.RANK_FORCED)
	var target_count: int = TIER_CHECKPOINT_COUNT.get(tier, 4)
	var checkpoints := _minimize_checkpoints(
			size, path, barriers, target_count, required_rank, rng, cancel_check)
	if checkpoints.is_empty():
		return {}

	# Step 4: Confirm the minimized puzzle is solved by human deductions and that
	# its hardest required deduction is *exactly* this tier's rank — not below and
	# not above. Because every solver elimination is a sound necessary condition,
	# completing the solve also proves the solution is unique, so no separate
	# (and potentially multi-second) exhaustive count is needed.
	var solver_result := NumberPathSolver.solve(
			size, size, checkpoints, barriers, required_rank, RANK4_ROLLOUT_DEPTH)
	if not solver_result.get("solved", false):
		return {}
	var max_rank: int = solver_result.get("max_rank", 0)
	if max_rank != required_rank:
		return {}

	return {
		"width": size,
		"height": size,
		"checkpoints": checkpoints,
		"barriers": barriers,
		"solution_path": _path_to_array(path),
		"solver_steps": solver_result.get("steps", []),
		"solver_max_rank": max_rank,
	}


# --- Hamiltonian path construction ---

static func _build_hamiltonian_path(
		size: int,
		rng: RandomNumberGenerator,
		cancel_check: Callable) -> Array[Vector2i]:
	if cancel_check.is_valid() and cancel_check.call():
		return []

	# A transformed serpentine path is Hamiltonian by construction. Clue
	# minimization and barriers provide the puzzle variation; using DFS here
	# made larger tiers spend unbounded time rediscovering a path we can build
	# directly.
	var vertical := rng.randi_range(0, 1) == 1
	var flip_x := rng.randi_range(0, 1) == 1
	var flip_y := rng.randi_range(0, 1) == 1
	var path: Array[Vector2i] = []
	for row in range(size):
		for offset in range(size):
			var col := offset if row % 2 == 0 else size - 1 - offset
			var cell := Vector2i(col, row)
			if flip_x:
				cell.x = size - 1 - cell.x
			if flip_y:
				cell.y = size - 1 - cell.y
			if vertical:
				cell = Vector2i(cell.y, cell.x)
			path.append(cell)
	return _randomize_hamiltonian_path(size, path, rng, cancel_check)


static func _randomize_hamiltonian_path(
		size: int,
		initial_path: Array[Vector2i],
		rng: RandomNumberGenerator,
		cancel_check: Callable) -> Array[Vector2i]:
	var path := initial_path.duplicate()
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP,
	]
	for iteration in range(size * size * 8):
		if iteration % 32 == 0 and cancel_check.is_valid() and cancel_check.call():
			return []
		var use_head := rng.randi_range(0, 1) == 0
		var endpoint: Vector2i = path[0] if use_head else path[path.size() - 1]
		var candidate_indices: Array[int] = []
		for direction in directions:
			var neighbor := endpoint + direction
			if neighbor.x < 0 or neighbor.y < 0 \
					or neighbor.x >= size or neighbor.y >= size:
				continue
			var index := path.find(neighbor)
			if use_head and index > 1:
				candidate_indices.append(index)
			elif not use_head and index >= 0 and index < path.size() - 2:
				candidate_indices.append(index)
		if candidate_indices.is_empty():
			continue
		var pivot: int = candidate_indices[rng.randi_range(0, candidate_indices.size() - 1)]
		var rerouted: Array[Vector2i] = []
		if use_head:
			for i in range(pivot - 1, -1, -1):
				rerouted.append(path[i])
			for i in range(pivot, path.size()):
				rerouted.append(path[i])
		else:
			for i in range(pivot + 1):
				rerouted.append(path[i])
			for i in range(path.size() - 1, pivot, -1):
				rerouted.append(path[i])
		path = rerouted
	return path


static func _minimize_checkpoints(
		size: int,
		path: Array[Vector2i],
		barriers: Array[Dictionary],
		target_count: int,
		required_rank: int,
		rng: RandomNumberGenerator,
		cancel_check: Callable) -> Array[Dictionary]:
	var checkpoints: Array[Dictionary] = []
	for i in range(path.size()):
		checkpoints.append({"x": path[i].x, "y": path[i].y, "n": i + 1})

	var candidates: Array[Vector2i] = []
	for i in range(1, path.size() - 1):
		candidates.append(path[i])
	_shuffle_array(candidates, rng)

	# Bound the forced-only look-ahead used to grade Rank-4 deductions to a short
	# human-scale chain; see RANK4_ROLLOUT_DEPTH. This is the depth a human would
	# actually trace, and it keeps Expert generation from spending unbounded time
	# on deep sparse-board solves.
	var budget := RANK4_ROLLOUT_DEPTH

	for cell in candidates:
		if cancel_check.is_valid() and cancel_check.call():
			return []
		var remove_index := _find_checkpoint(checkpoints, cell)
		if remove_index < 0:
			continue
		var removed: Dictionary = checkpoints.pop_at(remove_index)
		_reindex_checkpoints(checkpoints)

		# Lazy escalation: while the puzzle is still solvable *below* this tier's
		# required rank, keep thinning clues using only the cheap shallow solve —
		# we never pay for the deeper (required-rank) look-ahead until a removal
		# actually pushes the puzzle up to the required rank.
		if required_rank > NumberPathSolver.RANK_FORCED:
			var easy := NumberPathSolver.solve(
					size, size, checkpoints, barriers, required_rank - 1, budget)
			if easy.get("solved", false):
				continue

		# The puzzle now needs at least the required rank (or the tier is Rank 1).
		# Accept the removal only if it is still fully solvable at the required
		# rank; otherwise the clue is load-bearing (removing it would exceed the
		# rank ceiling or break the unique human solution) and must stay.
		var exact := NumberPathSolver.solve(
				size, size, checkpoints, barriers, required_rank, budget)
		if not exact.get("solved", false):
			checkpoints.insert(remove_index, removed)
			_reindex_checkpoints(checkpoints)
			continue

		# Solvable at exactly the required rank. Stop once the clue count reaches
		# the tier target; otherwise keep thinning toward it.
		if checkpoints.size() <= target_count:
			return checkpoints

	# Removable clues were exhausted before reaching the target. Accept the
	# sparsest puzzle found only if it genuinely requires this tier's rank.
	var final_result := NumberPathSolver.solve(
			size, size, checkpoints, barriers, required_rank, budget)
	if final_result.get("solved", false) \
			and int(final_result.get("max_rank", 0)) == required_rank:
		return checkpoints
	return []


static func _find_checkpoint(
		checkpoints: Array[Dictionary],
		cell: Vector2i) -> int:
	for i in range(checkpoints.size()):
		var checkpoint: Dictionary = checkpoints[i]
		if int(checkpoint.get("x", -1)) == cell.x \
				and int(checkpoint.get("y", -1)) == cell.y:
			return i
	return -1


static func _reindex_checkpoints(checkpoints: Array[Dictionary]) -> void:
	for i in range(checkpoints.size()):
		checkpoints[i]["n"] = i + 1


# --- Barrier placement ---

static func _place_barriers(
		size: int,
		path: Array[Vector2i],
		count: int,
		rng: RandomNumberGenerator,
		cancel_check: Callable) -> Array[Dictionary]:
	# Collect all edges NOT on the solution path
	var all_edges: Array[Dictionary] = []
	var path_edges: Dictionary = {}

	# Build set of solution path edges
	for i in range(path.size() - 1):
		var a: Vector2i = path[i]
		var b: Vector2i = path[i + 1]
		var key := _edge_key(a, b)
		path_edges[key] = true

	# All interior edges of the grid
	for r in range(size):
		for c in range(size):
			# Right edge
			if c + 1 < size:
				var key := _edge_key(Vector2i(c, r), Vector2i(c + 1, r))
				if not path_edges.has(key):
					all_edges.append({"r": r, "c": c, "dir": NumberPathLogic.DIR_RIGHT})
			# Down edge
			if r + 1 < size:
				var key := _edge_key(Vector2i(c, r), Vector2i(c, r + 1))
				if not path_edges.has(key):
					all_edges.append({"r": r, "c": c, "dir": NumberPathLogic.DIR_DOWN})

	# Shuffle and pick up to count barriers
	_shuffle_array(all_edges, rng)

	var selected: Array[Dictionary] = []
	for edge in all_edges:
		if cancel_check.is_valid() and cancel_check.call():
			return selected
		if selected.size() >= count:
			break
		selected.append(edge)

	return selected


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x == b.x:
		var top := a if a.y < b.y else b
		return "d%d,%d" % [top.x, top.y]
	else:
		var left := a if a.x < b.x else b
		return "r%d,%d" % [left.x, left.y]


static func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _path_to_array(path: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in path:
		result.append({"x": cell.x, "y": cell.y})
	return result
