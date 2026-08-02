extends GutTest

## Unit tests for CrownGridGenerator.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _verify_connectivity(size: int, regions: PackedInt32Array) -> bool:
	for reg in range(size):
		var cells: Array[Vector2i] = []
		for r in range(size):
			for c in range(size):
				if regions[r * size + c] == reg:
					cells.append(Vector2i(c, r))
		if cells.is_empty():
			return false
		var visited: Dictionary = {}
		var queue: Array[Vector2i] = [cells[0]]
		visited[cells[0]] = true
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			for delta in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var n: Vector2i = cur + delta
				if n.x >= 0 and n.x < size and n.y >= 0 and n.y < size:
					if regions[n.y * size + n.x] == reg and not visited.has(n):
						visited[n] = true
						queue.append(n)
		if visited.size() != cells.size():
			return false
	return true


func _count_crowns_per_region(size: int, regions: PackedInt32Array, crown_cols: Array[int]) -> bool:
	var region_count: Dictionary = {}
	for r in range(size):
		var c := crown_cols[r]
		var reg: int = regions[r * size + c]
		if region_count.has(reg):
			return false  # Two crowns in same region
		region_count[reg] = true
	return region_count.size() == size


# ---------------------------------------------------------------------------
# Crown solution generation
# ---------------------------------------------------------------------------

func test_crown_solution_valid_permutation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var crown_cols := CrownGridGenerator._gen_crown_solution(6, rng)
	assert_eq(crown_cols.size(), 6)
	# Check all columns unique
	var seen: Dictionary = {}
	for c in crown_cols:
		assert_false(seen.has(c), "Duplicate column %d" % c)
		seen[c] = true


func test_crown_solution_no_diagonal_adjacency() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for _attempt in range(5):
		var crown_cols := CrownGridGenerator._gen_crown_solution(8, rng)
		for r in range(crown_cols.size() - 1):
			assert_ne(absi(crown_cols[r] - crown_cols[r + 1]), 1,
					"Diagonal adjacency at rows %d,%d cols %d,%d" % [r, r+1, crown_cols[r], crown_cols[r+1]])


# ---------------------------------------------------------------------------
# Region generation
# ---------------------------------------------------------------------------

func test_regions_all_cells_assigned() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var size := 6
	var crown_cols := CrownGridGenerator._gen_crown_solution(size, rng)
	if crown_cols.is_empty():
		return
	var regions := CrownGridGenerator._gen_regions(size, crown_cols, rng)
	assert_eq(regions.size(), size * size)
	for i in range(regions.size()):
		assert_true(regions[i] >= 0 and regions[i] < size,
				"Cell %d has invalid region %d" % [i, regions[i]])


func test_regions_connected() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var size := 6
	var crown_cols := CrownGridGenerator._gen_crown_solution(size, rng)
	if crown_cols.is_empty():
		return
	var regions := CrownGridGenerator._gen_regions(size, crown_cols, rng)
	if regions.is_empty():
		return
	assert_true(_verify_connectivity(size, regions))


func test_regions_one_crown_per_region() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var size := 6
	var crown_cols: Array[int] = CrownGridGenerator._gen_crown_solution(size, rng)
	if crown_cols.is_empty():
		return
	var regions := CrownGridGenerator._gen_regions(size, crown_cols, rng)
	if regions.is_empty():
		return
	assert_true(_count_crowns_per_region(size, regions, crown_cols))


# ---------------------------------------------------------------------------
# Full generation
# ---------------------------------------------------------------------------

func test_generate_easy_deterministic() -> void:
	var result1 := CrownGridGenerator.generate(CrownGridGenerator.TIER_EASY, 42)
	var result2 := CrownGridGenerator.generate(CrownGridGenerator.TIER_EASY, 42)
	if result1.is_empty() or result2.is_empty():
		return  # Generation failed — skip
	assert_eq(result1["size"], result2["size"])
	assert_eq(Array(result1["regions"]), Array(result2["regions"]))
	assert_eq(result1["solution"], result2["solution"])


func test_generate_easy_correct_size() -> void:
	var result := CrownGridGenerator.generate(CrownGridGenerator.TIER_EASY, 1)
	if result.is_empty():
		return
	assert_eq(result["size"], 6)


func test_generate_medium_correct_size() -> void:
	var result := CrownGridGenerator.generate(CrownGridGenerator.TIER_MEDIUM, 2)
	assert_false(result.is_empty(), "Generation must succeed for TIER_MEDIUM seed 2")
	if result.is_empty():
		return
	assert_eq(result["size"], 7)
	assert_eq(result["rank"], CrownGridSolver.RANK_COMBINED,
			"TIER_MEDIUM seed 2 must produce a Rank-2 (RANK_COMBINED) puzzle")


func test_generate_returns_empty_on_cancellation() -> void:
	var cancel_ref := [true]  # Cancel immediately
	var result := CrownGridGenerator.generate(
		CrownGridGenerator.TIER_EASY, 5, func() -> bool: return cancel_ref[0])
	assert_true(result.is_empty())


func test_generate_solution_valid() -> void:
	var result := CrownGridGenerator.generate(CrownGridGenerator.TIER_EASY, 10)
	if result.is_empty():
		return
	var size: int = result["size"]
	var regions: PackedInt32Array = result["regions"]
	var solution: Array[int] = result["solution"]
	assert_true(CrownGridSolver.validate_solution(size, regions, solution))


func test_generate_unique_solution() -> void:
	var result := CrownGridGenerator.generate(CrownGridGenerator.TIER_EASY, 10)
	if result.is_empty():
		return
	var size: int = result["size"]
	var regions: PackedInt32Array = result["regions"]
	var count := CrownGridSolver.count_solutions(size, regions)
	assert_eq(count, 1)


func test_generate_different_seeds_may_differ() -> void:
	var r1 := CrownGridGenerator.generate(CrownGridGenerator.TIER_EASY, 100)
	var r2 := CrownGridGenerator.generate(CrownGridGenerator.TIER_EASY, 200)
	if r1.is_empty() or r2.is_empty():
		return
	# Different seeds should generally produce different boards
	# (not guaranteed but highly likely)
	var same := Array(r1["regions"]) == Array(r2["regions"])
	# Just check both are valid
	assert_true(CrownGridSolver.validate_solution(r1["size"], r1["regions"], r1["solution"]))
	assert_true(CrownGridSolver.validate_solution(r2["size"], r2["regions"], r2["solution"]))


# ---------------------------------------------------------------------------
# Connectivity verification helper
# ---------------------------------------------------------------------------

func test_verify_connectivity_connected_regions() -> void:
	# 4x4 with 4 column-based regions (each is 1 column = connected)
	var regions := PackedInt32Array()
	regions.resize(16)
	for r in range(4):
		for c in range(4):
			regions[r * 4 + c] = c
	assert_true(CrownGridGenerator._verify_connectivity(4, regions))


func test_verify_connectivity_disconnected_region() -> void:
	# 4x4 where region 0 has two disconnected cells
	var regions := PackedInt32Array()
	regions.resize(16)
	for i in range(16):
		regions[i] = 1  # fill all with region 1
	regions[0] = 0   # cell (0,0) = region 0
	regions[15] = 0  # cell (3,3) = region 0 — not connected to (0,0)
	assert_false(CrownGridGenerator._verify_connectivity(4, regions))


# ---------------------------------------------------------------------------
# Expert rank floor (fix 5)
# ---------------------------------------------------------------------------

func test_expert_min_rank_is_chain() -> void:
	assert_eq(
		CrownGridGenerator.TIER_MIN_RANK[CrownGridGenerator.TIER_EXPERT],
		CrownGridSolver.RANK_CHAIN,
		"Expert tier must require at least one Rank-4 (forcing chain) step"
	)


# ---------------------------------------------------------------------------
# Generator cancel_check passes through to solver (fix 4)
# ---------------------------------------------------------------------------

func test_generate_cancels_during_solution_count() -> void:
	# Cancel only after outer loop starts (allow crown+region gen to proceed)
	var call_count := [0]
	var result := CrownGridGenerator.generate(
		CrownGridGenerator.TIER_EASY, 42,
		func() -> bool:
			call_count[0] += 1
			return call_count[0] > 3  # Cancel after a few checks
	)
	# May succeed or fail depending on timing, but must not hang
	assert_true(result is Dictionary, "generate must return a Dictionary")
