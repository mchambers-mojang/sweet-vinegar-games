extends GutTest

## Unit tests for SudokuSolver — validation, candidates, brute-force solving.


# --- is_valid_placement ---

func test_valid_placement_empty_grid() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	assert_true(SudokuSolver.is_valid_placement(grid, 0, 5))


func test_invalid_placement_same_row() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	grid[3] = 7
	assert_false(SudokuSolver.is_valid_placement(grid, 0, 7))


func test_invalid_placement_same_col() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	grid[27] = 4  # row 3, col 0
	assert_false(SudokuSolver.is_valid_placement(grid, 0, 4))


func test_invalid_placement_same_box() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	grid[10] = 9  # row 1, col 1
	assert_false(SudokuSolver.is_valid_placement(grid, 0, 9))


func test_valid_placement_number_in_different_box() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	grid[30] = 5  # row 3, col 3 — different box
	assert_true(SudokuSolver.is_valid_placement(grid, 0, 5))


# --- get_candidates ---

func test_candidates_empty_grid() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	var cands: Array[int] = SudokuSolver.get_candidates(grid, 0)
	assert_eq(cands.size(), 9)


func test_candidates_filled_cell() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	grid[0] = 5
	var cands: Array[int] = SudokuSolver.get_candidates(grid, 0)
	assert_eq(cands.size(), 0)


func test_candidates_excludes_row_col_box() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	# Fill row 0 with 1-8 in cols 1-8
	for i in range(1, 9):
		grid[i] = i
	var cands: Array[int] = SudokuSolver.get_candidates(grid, 0)
	assert_eq(cands, [9])


# --- solve_brute_force ---

func test_solve_complete_grid() -> void:
	# A fully solved grid should return 1 solution (itself)
	var grid: Array[int] = []
	grid.assign(SudokuGenerator.SEED_GRID.duplicate())
	var solutions: Array[Array] = SudokuSolver.solve_brute_force(grid, 2)
	assert_eq(solutions.size(), 1)


func test_solve_one_cell_missing() -> void:
	var grid: Array[int] = []
	grid.assign(SudokuGenerator.SEED_GRID.duplicate())
	grid[0] = 0  # Remove one cell
	var solutions: Array[Array] = SudokuSolver.solve_brute_force(grid, 2)
	assert_eq(solutions.size(), 1)
	assert_eq(solutions[0][0], 5)  # Original value


func test_solve_empty_grid_has_multiple_solutions() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	var solutions: Array[Array] = SudokuSolver.solve_brute_force(grid, 2)
	assert_eq(solutions.size(), 2)  # Stops at max_solutions


# --- Validation of SEED_GRID ---

func test_seed_grid_is_valid() -> void:
	var grid: Array[int] = []
	grid.assign(SudokuGenerator.SEED_GRID.duplicate())
	# Every cell should be 1-9
	for i in 81:
		assert_true(grid[i] >= 1 and grid[i] <= 9)
	# No conflicts
	for i in 81:
		var val: int = grid[i]
		grid[i] = 0
		assert_true(SudokuSolver.is_valid_placement(grid, i, val),
			"Conflict at cell %d" % i)
		grid[i] = val
