extends GutTest

const FULL_GRID: Array[int] = SudokuGenerator.SEED_GRID
const KillerCagePartitionerScript := preload("res://scripts/sudoku/killer_cage_partitioner.gd")


func test_partition_covers_grid_with_contiguous_easy_cages() -> void:
	var cages := KillerCagePartitionerScript.partition(FULL_GRID, SudokuSolver.Difficulty.EASY, 123)
	assert_eq(_covered_cell_count(cages), 81)
	assert_true(_all_cells_unique(cages))
	for cage in cages:
		var cells: Array = cage["cells"]
		assert_true(cells.size() >= 2 and cells.size() <= 3)
		assert_true(_is_contiguous(cells))
		assert_eq(_sum_for_cells(cells), cage["sum"])


func test_partition_size_ranges_expand_with_difficulty() -> void:
	var easy := KillerCagePartitionerScript.partition(FULL_GRID, SudokuSolver.Difficulty.EASY, 10)
	var medium := KillerCagePartitionerScript.partition(FULL_GRID, SudokuSolver.Difficulty.MEDIUM, 10)
	var expert := KillerCagePartitionerScript.partition(FULL_GRID, SudokuSolver.Difficulty.EXPERT, 10)
	assert_eq(_max_cage_size(easy), 3)
	assert_true(_max_cage_size(medium) <= 4)
	assert_true(_max_cage_size(expert) <= 5)
	assert_true(_count_large_cages(expert, 4) > _count_large_cages(easy, 4))


func test_partition_rejects_cages_with_duplicate_source_digits() -> void:
	var cages := KillerCagePartitionerScript.partition(FULL_GRID, SudokuSolver.Difficulty.EASY, 21)
	for cage in cages:
		assert_true(_cage_digits_are_unique(cage["cells"]))


func _covered_cell_count(cages: Array) -> int:
	var total := 0
	for cage in cages:
		total += (cage["cells"] as Array).size()
	return total


func _all_cells_unique(cages: Array) -> bool:
	var seen := {}
	for cage in cages:
		for cell in cage["cells"]:
			if seen.has(cell):
				return false
			seen[cell] = true
	return seen.size() == 81


func _is_contiguous(cells: Array) -> bool:
	if cells.is_empty():
		return false
	var cell_set := {}
	for cell in cells:
		cell_set[int(cell)] = true
	var visited := {}
	var stack: Array[int] = [int(cells[0])]
	visited[int(cells[0])] = true
	while not stack.is_empty():
		var current := int(stack.pop_back())
		for neighbor in _neighbors(current):
			if cell_set.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				stack.append(neighbor)
	return visited.size() == cells.size()


func _neighbors(index: int) -> Array[int]:
	var row := index / 9
	var col := index % 9
	var neighbors: Array[int] = []
	if row > 0:
		neighbors.append(index - 9)
	if row < 8:
		neighbors.append(index + 9)
	if col > 0:
		neighbors.append(index - 1)
	if col < 8:
		neighbors.append(index + 1)
	return neighbors


func _sum_for_cells(cells: Array) -> int:
	var total := 0
	for cell in cells:
		total += FULL_GRID[int(cell)]
	return total


func _max_cage_size(cages: Array) -> int:
	var max_size := 0
	for cage in cages:
		max_size = maxi(max_size, (cage["cells"] as Array).size())
	return max_size


func _count_large_cages(cages: Array, size_threshold: int) -> int:
	var count := 0
	for cage in cages:
		if (cage["cells"] as Array).size() >= size_threshold:
			count += 1
	return count


func _cage_digits_are_unique(cells: Array) -> bool:
	var seen := {}
	for cell in cells:
		var digit := FULL_GRID[int(cell)]
		if seen.has(digit):
			return false
		seen[digit] = true
	return true
