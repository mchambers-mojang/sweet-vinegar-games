extends GutTest

## Unit tests for KillerCageGenerator

const SAMPLE_SOLUTION: Array[int] = [
	5, 3, 4, 6, 7, 8, 9, 1, 2,
	6, 7, 2, 1, 9, 5, 3, 4, 8,
	1, 9, 8, 3, 4, 2, 5, 6, 7,
	8, 5, 9, 7, 6, 1, 4, 2, 3,
	4, 2, 6, 8, 5, 3, 7, 9, 1,
	7, 1, 3, 9, 2, 4, 8, 5, 6,
	9, 6, 1, 5, 3, 7, 2, 8, 4,
	2, 8, 7, 4, 1, 9, 6, 3, 5,
	3, 4, 5, 2, 8, 6, 1, 7, 9,
]


# ---------------------------------------------------------------------------
# Coverage
# ---------------------------------------------------------------------------

func test_cages_cover_all_81_cells() -> void:
	var cages := KillerCageGenerator.generate(SAMPLE_SOLUTION, 42)
	var covered: Dictionary = {}
	for cage in cages:
		for c in cage["cells"]:
			covered[c] = true
	assert_eq(covered.size(), 81, "all 81 cells must be covered")


func test_no_cell_in_two_cages() -> void:
	var cages := KillerCageGenerator.generate(SAMPLE_SOLUTION, 99)
	var seen: Dictionary = {}
	for i in cages.size():
		for c in cages[i]["cells"]:
			assert_false(seen.has(c), "cell %d appears in multiple cages" % c)
			seen[c] = i


# ---------------------------------------------------------------------------
# Cage size
# ---------------------------------------------------------------------------

func test_cage_sizes_within_bounds() -> void:
	var cages := KillerCageGenerator.generate(SAMPLE_SOLUTION, 7)
	for cage in cages:
		var sz: int = (cage["cells"] as Array).size()
		assert_true(sz >= 1 and sz <= KillerCageGenerator.MAX_CAGE_SIZE,
				"cage size %d is out of bounds" % sz)


# ---------------------------------------------------------------------------
# No duplicate digits per cage
# ---------------------------------------------------------------------------

func test_no_duplicate_digits_in_any_cage() -> void:
	var cages := KillerCageGenerator.generate(SAMPLE_SOLUTION, 123)
	for cage in cages:
		var seen_vals: Dictionary = {}
		for c in cage["cells"]:
			var v: int = SAMPLE_SOLUTION[c]
			assert_false(seen_vals.has(v), "duplicate digit %d in cage" % v)
			seen_vals[v] = true


# ---------------------------------------------------------------------------
# Correct sums
# ---------------------------------------------------------------------------

func test_cage_sums_match_solution() -> void:
	var cages := KillerCageGenerator.generate(SAMPLE_SOLUTION, 55)
	for cage in cages:
		var expected := 0
		for c in cage["cells"]:
			expected += SAMPLE_SOLUTION[c]
		assert_eq(int(cage["sum"]), expected, "cage sum mismatch")


# ---------------------------------------------------------------------------
# Anchor cell
# ---------------------------------------------------------------------------

func test_anchor_is_topmost_leftmost_cell() -> void:
	var cages := KillerCageGenerator.generate(SAMPLE_SOLUTION, 13)
	for cage in cages:
		var anchor: int = int(cage["anchor"])
		for c in cage["cells"]:
			assert_true(c >= anchor, "anchor %d is not the smallest cell index" % anchor)


# ---------------------------------------------------------------------------
# Deterministic with same seed
# ---------------------------------------------------------------------------

func test_same_seed_gives_same_cages() -> void:
	var cages_a := KillerCageGenerator.generate(SAMPLE_SOLUTION, 77)
	var cages_b := KillerCageGenerator.generate(SAMPLE_SOLUTION, 77)
	assert_eq(cages_a.size(), cages_b.size(), "cage count must match with same seed")
	for i in cages_a.size():
		var cells_a: Array = cages_a[i]["cells"]
		var cells_b: Array = cages_b[i]["cells"]
		assert_eq(cells_a.size(), cells_b.size())


# ---------------------------------------------------------------------------
# Contiguity
# ---------------------------------------------------------------------------

func test_all_cages_are_contiguous() -> void:
	var cages := KillerCageGenerator.generate(SAMPLE_SOLUTION, 31)
	for cage in cages:
		var cells: Array = cage["cells"]
		if cells.size() <= 1:
			continue
		# BFS from the first cell — all cells must be reachable
		var visited: Dictionary = {cells[0]: true}
		var queue: Array = [cells[0]]
		while not queue.is_empty():
			var current: int = queue.pop_front()
			var r := current / 9
			var c := current % 9
			var neighbors := []
			if r > 0: neighbors.append((r - 1) * 9 + c)
			if r < 8: neighbors.append((r + 1) * 9 + c)
			if c > 0: neighbors.append(r * 9 + c - 1)
			if c < 8: neighbors.append(r * 9 + c + 1)
			for nb in neighbors:
				if nb in cells and not visited.has(nb):
					visited[nb] = true
					queue.append(nb)
		assert_eq(visited.size(), cells.size(), "cage is not contiguous: %s" % str(cells))
