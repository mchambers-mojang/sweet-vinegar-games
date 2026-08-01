class_name NumberPathGenerator
extends RefCounted

## Generates Number Path puzzles for each tier.
## Returns deterministic results given the same tier + seed.
## Generation flow:
##   1. Build a random Hamiltonian path via DFS with backtracking.
##   2. Place checkpoints along the path at tier-appropriate intervals.
##   3. Place barriers (Hard/Expert) that are consistent with the path.
##   4. Verify uniqueness via NumberPathSolver.count_solutions().
##   5. Verify human-solvability via NumberPathSolver.solve() reaching the required rank.
##   6. Return the puzzle data or {} on failure/cancellation.

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
	NumberPathLogic.TIER_EXPERT: 14,
}

## Tier → required maximum solver rank
const TIER_REQUIRED_RANK := {
	NumberPathLogic.TIER_EASY: NumberPathSolver.RANK_FORCED,
	NumberPathLogic.TIER_MEDIUM: NumberPathSolver.RANK_LOCAL,
	NumberPathLogic.TIER_HARD: NumberPathSolver.RANK_REGION,
	NumberPathLogic.TIER_EXPERT: NumberPathSolver.RANK_GLOBAL,
}

const MAX_GENERATION_ATTEMPTS := 50


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

	# Step 2: Place checkpoints
	var cp_count: int = TIER_CHECKPOINT_COUNT.get(tier, 4)
	var checkpoints := _place_checkpoints(path, cp_count, rng)
	if checkpoints.is_empty():
		return {}

	# Step 3: Place barriers (Hard/Expert only)
	var barriers: Array[Dictionary] = []
	var barrier_count: int = TIER_BARRIER_COUNT.get(tier, 0)
	if barrier_count > 0:
		barriers = _place_barriers(size, path, barrier_count, rng, cancel_check)
		if cancel_check.is_valid() and cancel_check.call():
			return {}

	# Step 4: Verify exactly one solution
	var sol_count := NumberPathSolver.count_solutions(
			size, size, checkpoints, barriers, 2, cancel_check)
	if sol_count != 1:
		return {}
	if cancel_check.is_valid() and cancel_check.call():
		return {}

	# Step 5: Verify human-solvability at exactly the required rank.
	# max_rank must equal required_rank: the puzzle must need the tier's deduction
	# techniques (lower → too easy, higher → out of scope for that tier).
	var solver_result := NumberPathSolver.solve(size, size, checkpoints, barriers)
	if not solver_result.get("solved", false):
		return {}
	var max_rank: int = solver_result.get("max_rank", 0)
	var required_rank: int = TIER_REQUIRED_RANK.get(tier, 1)
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
	# Try several random starting cells for diversity
	var starts: Array[Vector2i] = []
	for _ in range(5):
		starts.append(Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1)))

	for start in starts:
		if cancel_check.is_valid() and cancel_check.call():
			return []
		var path := _dfs_hamiltonian(size, start, rng, cancel_check)
		if not path.is_empty():
			return path
	return []


static func _dfs_hamiltonian(
		size: int,
		start: Vector2i,
		rng: RandomNumberGenerator,
		cancel_check: Callable) -> Array[Vector2i]:
	var total := size * size
	var visited := PackedByteArray()
	visited.resize(total)
	visited.fill(0)

	var path: Array[Vector2i] = [start]
	visited[start.y * size + start.x] = 1

	# Warnsdorff-guided DFS with random tiebreaking
	var call_count := [0]
	if _ham_dfs(size, path, visited, total, rng, cancel_check, call_count):
		return path
	return []


static func _ham_dfs(
		size: int,
		path: Array[Vector2i],
		visited: PackedByteArray,
		total: int,
		rng: RandomNumberGenerator,
		cancel_check: Callable,
		call_count: Array) -> bool:
	call_count[0] += 1
	if call_count[0] % 500 == 0 and cancel_check.is_valid() and cancel_check.call():
		return false

	if path.size() == total:
		return true

	var head: Vector2i = path[path.size() - 1]
	var neighbors := _get_free_neighbors(size, head, visited)

	# Warnsdorff: sort by fewest onward neighbors, random tiebreak
	neighbors.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := _get_free_neighbor_count(size, a, visited)
		var db := _get_free_neighbor_count(size, b, visited)
		if da == db:
			return rng.randi_range(0, 1) == 0
		return da < db
	)

	for nb in neighbors:
		var idx := nb.y * size + nb.x
		path.append(nb)
		visited[idx] = 1
		if _ham_dfs(size, path, visited, total, rng, cancel_check, call_count):
			return true
		path.pop_back()
		visited[idx] = 0

	return false


static func _get_free_neighbors(size: int, cell: Vector2i, visited: PackedByteArray) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		var nb := cell + d
		if nb.x >= 0 and nb.y >= 0 and nb.x < size and nb.y < size:
			if visited[nb.y * size + nb.x] == 0:
				result.append(nb)
	return result


static func _get_free_neighbor_count(size: int, cell: Vector2i, visited: PackedByteArray) -> int:
	return _get_free_neighbors(size, cell, visited).size()


# --- Checkpoint placement ---

static func _place_checkpoints(
		path: Array[Vector2i],
		count: int,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	if path.size() < count:
		return []

	# Always include start (index 0) and end (last index)
	var result: Array[Dictionary] = []

	# Pick count-2 intermediate indices, spaced roughly evenly with jitter
	var indices: Array[int] = [0]
	var segment := float(path.size() - 1) / float(count - 1)
	for i in range(1, count - 1):
		var base := int(i * segment)
		var jitter := int(segment * 0.3)
		var lo := maxi(indices[indices.size() - 1] + 2, base - jitter)
		var hi := mini(path.size() - 2, base + jitter)
		if lo > hi:
			lo = base
			hi = base
		lo = clampi(lo, indices[indices.size() - 1] + 2, path.size() - 2)
		hi = clampi(hi, lo, path.size() - 2)
		if lo > hi:
			return []
		indices.append(rng.randi_range(lo, hi))
	indices.append(path.size() - 1)

	for i in range(indices.size()):
		var cell: Vector2i = path[indices[i]]
		result.append({"x": cell.x, "y": cell.y, "n": i + 1})

	return result


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
