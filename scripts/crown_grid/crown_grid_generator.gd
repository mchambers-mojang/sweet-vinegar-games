class_name CrownGridGenerator
extends RefCounted

## Deterministic generator for Crown Grid puzzles.
##
## generate(tier, seed, cancel_check) → Dictionary or {} on failure.
##
## Returned dict:
##   size: int
##   regions: PackedInt32Array (flat, regions[r*size+c] = region_id 0..N-1)
##   solution: Array[int] (crown_cols[row] = col)
##   seed: int
##   rank: int (max reasoning rank needed to solve)
##
## Tier → size map:
##   TIER_EASY   → 6×6
##   TIER_MEDIUM → 7×7
##   TIER_HARD   → 8×8
##   TIER_EXPERT → 9×9

const TIER_EASY := 0
const TIER_MEDIUM := 1
const TIER_HARD := 2
const TIER_EXPERT := 3

const TIER_SIZES := {
	TIER_EASY: 6,
	TIER_MEDIUM: 7,
	TIER_HARD: 8,
	TIER_EXPERT: 9,
}

# Required minimum rank per tier
const TIER_MIN_RANK := {
	TIER_EASY: CrownGridSolver.RANK_SINGLE,
	TIER_MEDIUM: CrownGridSolver.RANK_COMBINED,
	TIER_HARD: CrownGridSolver.RANK_LOCKED,
	TIER_EXPERT: CrownGridSolver.RANK_LOCKED,  # 9×9 with locked-candidate logic
}

# Max rank allowed per tier
const TIER_MAX_RANK := {
	TIER_EASY: CrownGridSolver.RANK_SINGLE,
	TIER_MEDIUM: CrownGridSolver.RANK_COMBINED,
	TIER_HARD: CrownGridSolver.RANK_LOCKED,
	TIER_EXPERT: CrownGridSolver.RANK_CHAIN,  # chain steps are valid on 9×9
}

const MAX_OUTER_ATTEMPTS := 500
const MAX_REGION_ATTEMPTS := 50


## Generate a puzzle for the given tier and seed.
## cancel_check: Callable() -> bool, return true to abort.
## Returns {} on cancellation or exhaustion.
static func generate(tier: int, seed: int, cancel_check: Callable = Callable()) -> Dictionary:
	var size: int = TIER_SIZES.get(tier, 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	for attempt in range(MAX_OUTER_ATTEMPTS):
		if cancel_check.is_valid() and cancel_check.call():
			return {}

		# 1. Generate a valid crown solution (no diagonal adjacency conflicts)
		var crown_cols := _gen_crown_solution(size, rng)
		if crown_cols.is_empty():
			continue

		# 2. Build regions around each crown
		var regions := _gen_regions(size, crown_cols, rng)
		if regions.is_empty():
			continue

		# 3. Verify unique solution
		if cancel_check.is_valid() and cancel_check.call():
			return {}
		var solution_count := CrownGridSolver.count_solutions(size, regions)
		if solution_count != 1:
			continue

		# 4. Analyze difficulty rank
		if cancel_check.is_valid() and cancel_check.call():
			return {}
		var rank := CrownGridSolver.analyze_difficulty(size, regions)
		if rank == CrownGridSolver.RANK_NONE:
			continue

		# 5. Check tier rank constraints
		var min_rank: int = TIER_MIN_RANK.get(tier, CrownGridSolver.RANK_SINGLE)
		var max_rank: int = TIER_MAX_RANK.get(tier, CrownGridSolver.RANK_CHAIN)
		if rank < min_rank or rank > max_rank:
			continue

		return {
			"size": size,
			"regions": regions,
			"solution": crown_cols,
			"seed": seed,
			"rank": rank,
		}

	return {}


## Generate a valid crown solution: one crown per row and column,
## no two crowns diagonally adjacent (|row_diff|==1 AND |col_diff|==1).
static func _gen_crown_solution(size: int, rng: RandomNumberGenerator) -> Array[int]:
	# Build a random permutation and backtrack if diagonal adjacency found
	var cols: Array[int] = []
	cols.resize(size)
	# Initialize with identity permutation
	var available: Array[int] = []
	for i in range(size):
		available.append(i)

	if _solve_crowns(size, 0, cols, available, rng):
		return cols
	return []


static func _solve_crowns(size: int, row: int, cols: Array[int], available: Array[int], rng: RandomNumberGenerator) -> bool:
	if row >= size:
		return true

	# Shuffle available columns for randomness
	var shuffled := available.duplicate()
	_shuffle_array(shuffled, rng)

	for col in shuffled:
		# Check diagonal adjacency with previous row
		if row > 0 and absi(cols[row - 1] - col) == 1:
			continue
		cols[row] = col
		var next_available := available.duplicate()
		next_available.erase(col)
		if _solve_crowns(size, row + 1, cols, next_available, rng):
			return true

	return false


## Generate N connected regions, each containing exactly one crown.
## Returns empty PackedInt32Array on failure.
static func _gen_regions(size: int, crown_cols: Array[int], rng: RandomNumberGenerator) -> PackedInt32Array:
	for _attempt in range(MAX_REGION_ATTEMPTS):
		var result := _try_gen_regions(size, crown_cols, rng)
		if not result.is_empty():
			return result
	return PackedInt32Array()


static func _try_gen_regions(size: int, crown_cols: Array[int], rng: RandomNumberGenerator) -> PackedInt32Array:
	var total := size * size
	var region_map := PackedInt32Array()
	region_map.resize(total)
	region_map.fill(-1)

	# Seed each region from its crown cell
	for r in range(size):
		var c := crown_cols[r]
		region_map[r * size + c] = r

	# BFS frontier expansion (randomised Voronoi growth)
	# Build a list of frontier cells: cells adjacent to an assigned cell
	# that are themselves unassigned.
	var frontier: Array[Vector2i] = []
	for r in range(size):
		var c := crown_cols[r]
		_add_unassigned_neighbors(Vector2i(c, r), size, region_map, frontier)

	while not frontier.is_empty():
		# Pick a random frontier cell
		var idx := rng.randi_range(0, frontier.size() - 1)
		var cell: Vector2i = frontier[idx]
		frontier.remove_at(idx)

		# Skip if already assigned (could have been reached by multiple paths)
		if region_map[cell.y * size + cell.x] >= 0:
			continue

		# Find which regions are adjacent to this cell
		var neighbor_regions: Array[int] = _adjacent_regions(cell, size, region_map)
		if neighbor_regions.is_empty():
			continue

		# Assign to a random adjacent region
		var chosen_reg: int = neighbor_regions[rng.randi_range(0, neighbor_regions.size() - 1)]
		region_map[cell.y * size + cell.x] = chosen_reg

		# Add new unassigned neighbors to frontier
		_add_unassigned_neighbors(cell, size, region_map, frontier)

	# Verify all cells assigned and all regions connected
	for i in range(total):
		if region_map[i] < 0:
			return PackedInt32Array()

	if not _verify_connectivity(size, region_map):
		return PackedInt32Array()

	return region_map


static func _add_unassigned_neighbors(cell: Vector2i, size: int, region_map: PackedInt32Array, frontier: Array[Vector2i]) -> void:
	for delta in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var n := cell + delta
		if n.x >= 0 and n.x < size and n.y >= 0 and n.y < size:
			if region_map[n.y * size + n.x] < 0:
				frontier.append(n)


static func _adjacent_regions(cell: Vector2i, size: int, region_map: PackedInt32Array) -> Array[int]:
	var seen: Dictionary = {}
	for delta in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var n := cell + delta
		if n.x >= 0 and n.x < size and n.y >= 0 and n.y < size:
			var reg: int = region_map[n.y * size + n.x]
			if reg >= 0:
				seen[reg] = true
	var result: Array[int] = []
	for reg in seen:
		result.append(reg)
	return result


static func _verify_connectivity(size: int, region_map: PackedInt32Array) -> bool:
	# For each region, BFS from its crown cell and check all cells of that region are reachable
	for reg in range(size):
		var cells_in_reg: Array[Vector2i] = []
		for r in range(size):
			for c in range(size):
				if region_map[r * size + c] == reg:
					cells_in_reg.append(Vector2i(c, r))
		if cells_in_reg.is_empty():
			return false
		# BFS from first cell
		var visited: Dictionary = {}
		var queue: Array[Vector2i] = [cells_in_reg[0]]
		visited[cells_in_reg[0]] = true
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			for delta in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var n := cur + delta
				if n.x >= 0 and n.x < size and n.y >= 0 and n.y < size:
					if region_map[n.y * size + n.x] == reg and not visited.has(n):
						visited[n] = true
						queue.append(n)
		if visited.size() != cells_in_reg.size():
			return false
	return true


static func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
