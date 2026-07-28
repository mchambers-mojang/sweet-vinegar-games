extends GutTest

## Parameterized tests for Mini Sudoku 6×6 mode.
## Covers: SudokuGridSpec, SudokuGenerator (6×6), SudokuSolver (6×6),
## SudokuLogic (Mini), SudokuSaveAdapter (36-cell), legacy save fallback.

const LogicScript := preload("res://scripts/sudoku/sudoku_logic.gd")

# A known valid 6×6 puzzle and solution (symbols 1–6, 2×3 regions).
# Region layout: rows 0-1 × cols 0-2 / rows 0-1 × cols 3-5
#                rows 2-3 × cols 0-2 / rows 2-3 × cols 3-5
#                rows 4-5 × cols 0-2 / rows 4-5 × cols 3-5
# Puzzle has exactly one solution (verified programmatically).
const TEST_PUZZLE_6X6: Array[int] = [
	1, 0, 3, 0, 0, 0,
	0, 5, 0, 0, 0, 0,
	0, 1, 4, 0, 0, 5,
	0, 0, 0, 2, 0, 0,
	0, 0, 0, 0, 0, 2,
	0, 0, 0, 5, 3, 0,
]
const TEST_SOLUTION_6X6: Array[int] = [
	1, 2, 3, 4, 5, 6,
	4, 5, 6, 1, 2, 3,
	2, 1, 4, 3, 6, 5,
	3, 6, 5, 2, 1, 4,
	5, 3, 1, 6, 4, 2,
	6, 4, 2, 5, 3, 1,
]


# ---------------------------------------------------------------------------
# 1. SudokuGridSpec
# ---------------------------------------------------------------------------

func test_standard_spec_properties() -> void:
	var spec := SudokuGridSpec.STANDARD_9X9
	assert_eq(spec.id, "standard_9x9")
	assert_eq(spec.size, 9)
	assert_eq(spec.region_w, 3)
	assert_eq(spec.region_h, 3)
	assert_eq(spec.sym_min, 1)
	assert_eq(spec.sym_max, 9)
	assert_eq(spec.cell_count, 81)


func test_mini_spec_properties() -> void:
	var spec := SudokuGridSpec.MINI_6X6
	assert_eq(spec.id, "mini_6x6")
	assert_eq(spec.size, 6)
	assert_eq(spec.region_w, 3)
	assert_eq(spec.region_h, 2)
	assert_eq(spec.sym_min, 1)
	assert_eq(spec.sym_max, 6)
	assert_eq(spec.cell_count, 36)


func test_from_id_standard() -> void:
	var spec := SudokuGridSpec.from_id("standard_9x9")
	assert_not_null(spec)
	assert_eq(spec.id, "standard_9x9")


func test_from_id_mini() -> void:
	var spec := SudokuGridSpec.from_id("mini_6x6")
	assert_not_null(spec)
	assert_eq(spec.id, "mini_6x6")


func test_from_id_unknown_returns_null() -> void:
	var spec := SudokuGridSpec.from_id("nonexistent_spec")
	assert_null(spec, "Unknown id should return null")


# ---------------------------------------------------------------------------
# 2. SudokuSolver — 6×6
# ---------------------------------------------------------------------------

func test_solver_valid_placement_6x6_empty_grid() -> void:
	var spec := SudokuGridSpec.MINI_6X6
	var grid: Array[int] = []
	grid.resize(36)
	grid.fill(0)
	assert_true(SudokuSolver.is_valid_placement(grid, 0, 3, [], spec))


func test_solver_invalid_placement_6x6_row_conflict() -> void:
	var spec := SudokuGridSpec.MINI_6X6
	var grid: Array[int] = []
	grid.resize(36)
	grid.fill(0)
	grid[2] = 4  # Same row as index 0, col 2
	assert_false(SudokuSolver.is_valid_placement(grid, 0, 4, [], spec))


func test_solver_invalid_placement_6x6_col_conflict() -> void:
	var spec := SudokuGridSpec.MINI_6X6
	var grid: Array[int] = []
	grid.resize(36)
	grid.fill(0)
	grid[12] = 5  # row 2, col 0 — same column as index 0
	assert_false(SudokuSolver.is_valid_placement(grid, 0, 5, [], spec))


func test_solver_invalid_placement_6x6_box_conflict() -> void:
	var spec := SudokuGridSpec.MINI_6X6
	var grid: Array[int] = []
	grid.resize(36)
	grid.fill(0)
	grid[7] = 2  # row 1, col 1 — same 2×3 region as index 0
	assert_false(SudokuSolver.is_valid_placement(grid, 0, 2, [], spec))


func test_solver_solves_6x6_puzzle() -> void:
	var spec := SudokuGridSpec.MINI_6X6
	var puzzle: Array[int] = TEST_PUZZLE_6X6.duplicate()
	var solutions := SudokuSolver.solve_brute_force(puzzle, 2, [], Callable(), spec)
	assert_true(solutions.size() > 0, "Solver should find at least one solution")
	var result: Array = solutions[0]
	assert_eq(result.size(), 36)
	for i in 36:
		assert_true(result[i] >= 1 and result[i] <= 6,
			"Cell %d has out-of-range value %d" % [i, result[i]])


func test_solver_6x6_solution_matches_known_solution() -> void:
	var spec := SudokuGridSpec.MINI_6X6
	var puzzle: Array[int] = TEST_PUZZLE_6X6.duplicate()
	var solutions := SudokuSolver.solve_brute_force(puzzle, 2, [], Callable(), spec)
	assert_eq(solutions.size(), 1, "Puzzle should have exactly one solution")
	assert_eq(solutions[0], TEST_SOLUTION_6X6, "Solver should find the known unique solution")


func test_solver_get_candidates_6x6() -> void:
	var spec := SudokuGridSpec.MINI_6X6
	var grid: Array[int] = []
	grid.resize(36)
	grid.fill(0)
	var candidates := SudokuSolver.get_candidates(grid, 0, [], spec)
	assert_eq(candidates.size(), 6, "Empty 6×6 grid should have 6 candidates at any cell")


# ---------------------------------------------------------------------------
# 3. SudokuGenerator — 6×6
# ---------------------------------------------------------------------------

func test_generator_6x6_returns_correct_sizes() -> void:
	var gen := SudokuGenerator.new()
	var spec := SudokuGridSpec.MINI_6X6
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 42, [], spec)
	assert_true(result.has("puzzle"), "Result must have 'puzzle'")
	assert_true(result.has("solution"), "Result must have 'solution'")
	assert_eq(result["puzzle"].size(), 36, "Puzzle must have 36 cells")
	assert_eq(result["solution"].size(), 36, "Solution must have 36 cells")


func test_generator_6x6_puzzle_has_zeros() -> void:
	var gen := SudokuGenerator.new()
	var spec := SudokuGridSpec.MINI_6X6
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 42, [], spec)
	var zeros := 0
	for v in result["puzzle"]:
		if v == 0:
			zeros += 1
	assert_true(zeros > 0, "Mini puzzle should have empty cells")


func test_generator_6x6_solution_complete() -> void:
	var gen := SudokuGenerator.new()
	var spec := SudokuGridSpec.MINI_6X6
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 99, [], spec)
	var solution: Array = result["solution"]
	for i in 36:
		assert_true(solution[i] >= 1 and solution[i] <= 6,
			"Solution cell %d has invalid value %d" % [i, solution[i]])


func test_generator_6x6_solution_valid() -> void:
	var gen := SudokuGenerator.new()
	var spec := SudokuGridSpec.MINI_6X6
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 77, [], spec)
	var solution: Array[int] = []
	solution.assign(result["solution"])
	for i in 36:
		var val: int = solution[i]
		solution[i] = 0
		assert_true(SudokuSolver.is_valid_placement(solution, i, val, [], spec),
			"Solution conflict at cell %d" % i)
		solution[i] = val


func test_generator_6x6_puzzle_matches_solution() -> void:
	var gen := SudokuGenerator.new()
	var spec := SudokuGridSpec.MINI_6X6
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 55, [], spec)
	var puzzle: Array = result["puzzle"]
	var solution: Array = result["solution"]
	for i in 36:
		if puzzle[i] != 0:
			assert_eq(puzzle[i], solution[i],
				"Clue at cell %d doesn't match solution" % i)


func test_generator_6x6_deterministic() -> void:
	var gen := SudokuGenerator.new()
	var spec := SudokuGridSpec.MINI_6X6
	var r1: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 123, [], spec)
	var r2: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 123, [], spec)
	assert_eq(r1["puzzle"], r2["puzzle"], "Same seed should give same puzzle")
	assert_eq(r1["solution"], r2["solution"], "Same seed should give same solution")


func test_generator_6x6_different_seeds_differ() -> void:
	var gen := SudokuGenerator.new()
	var spec := SudokuGridSpec.MINI_6X6
	var r1: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 1, [], spec)
	var r2: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 2, [], spec)
	assert_ne(r1["puzzle"], r2["puzzle"], "Different seeds should give different puzzles")


# ---------------------------------------------------------------------------
# 4. SudokuLogic — Mini
# ---------------------------------------------------------------------------

func test_logic_mini_spec_cell_count() -> void:
	var logic := LogicScript.new(false, true)
	logic.spec = SudokuGridSpec.MINI_6X6
	logic._setup_from_arrays(0, TEST_PUZZLE_6X6, TEST_SOLUTION_6X6)
	assert_eq(logic.grid_cells, 36)
	assert_eq(logic.puzzle.size(), 36)
	assert_eq(logic.current_grid.size(), 36)
	assert_eq(logic.pencil_marks.size(), 36)


func test_logic_mini_init_new_game() -> void:
	var logic := LogicScript.new(false, true)
	logic.spec = SudokuGridSpec.MINI_6X6
	var ok := logic.init_new_game(SudokuSolver.Difficulty.EASY, 42)
	assert_true(ok, "Mini init_new_game should succeed")
	assert_eq(logic.puzzle.size(), 36)
	assert_eq(logic.solution.size(), 36)
	assert_eq(logic.grid_cells, 36)


func test_logic_mini_place_digit() -> void:
	var logic := LogicScript.new(false, true)
	logic.spec = SudokuGridSpec.MINI_6X6
	logic._setup_from_arrays(0, TEST_PUZZLE_6X6, TEST_SOLUTION_6X6)
	# Find first empty cell
	var empty_idx := -1
	for i in 36:
		if logic.puzzle[i] == 0:
			empty_idx = i
			break
	assert_true(empty_idx >= 0, "Puzzle should have empty cells")
	var correct_val := logic.solution[empty_idx]
	var res := logic.place(empty_idx, correct_val)
	assert_eq(res.cell_index, empty_idx)
	assert_eq(logic.current_grid[empty_idx], correct_val)


func test_logic_mini_is_solved_when_complete() -> void:
	var logic := LogicScript.new(false, true)
	logic.spec = SudokuGridSpec.MINI_6X6
	logic._setup_from_arrays(0, TEST_PUZZLE_6X6, TEST_SOLUTION_6X6)
	# Fill all empties with correct answers
	for i in 36:
		if logic.puzzle[i] == 0:
			logic.current_grid[i] = logic.solution[i]
	assert_true(logic.is_solved())


func test_logic_mini_serialize_includes_spec_id() -> void:
	var logic := LogicScript.new(false, true)
	logic.spec = SudokuGridSpec.MINI_6X6
	logic._setup_from_arrays(0, TEST_PUZZLE_6X6, TEST_SOLUTION_6X6)
	var data: Dictionary = logic.serialize()
	assert_true(data.has("grid_spec_id"), "Serialized data must include grid_spec_id")
	assert_eq(data["grid_spec_id"], "mini_6x6")


func test_logic_mini_round_trip_save() -> void:
	var logic := LogicScript.new(false, true)
	logic.spec = SudokuGridSpec.MINI_6X6
	logic._setup_from_arrays(0, TEST_PUZZLE_6X6, TEST_SOLUTION_6X6)
	# Place a digit to create non-trivial state
	for i in 36:
		if logic.puzzle[i] == 0:
			logic.current_grid[i] = logic.solution[i]
			break
	var data: Dictionary = logic.serialize()

	var logic2 := LogicScript.new(false, true)
	logic2.init_from_save(data)
	assert_eq(logic2.spec.id, "mini_6x6", "Restored spec should be mini_6x6")
	assert_eq(logic2.grid_cells, 36)
	assert_eq(logic2.current_grid, logic.current_grid)


func test_logic_standard_spec_unchanged() -> void:
	var logic := LogicScript.new(false, true)
	# Default spec should be standard 9×9
	assert_eq(logic.spec.id, "standard_9x9")
	var ok := logic.init_new_game(SudokuSolver.Difficulty.EASY, 42)
	assert_true(ok)
	assert_eq(logic.grid_cells, 81)


# ---------------------------------------------------------------------------
# 5. SudokuSaveAdapter — 36-cell and legacy compatibility
# ---------------------------------------------------------------------------

func test_save_adapter_accepts_36_cell_puzzle() -> void:
	var adapter := SudokuSaveAdapter.new()
	var data := {
		"puzzle": _make_array(36, 0),
		"solution": _make_array(36, 1),
		"current_grid": _make_array(36, 0),
		"grid_spec_id": "mini_6x6",
		"difficulty": 0,
	}
	data["puzzle"][0] = 1
	data["current_grid"][0] = 1
	GameSaveManager.save_game("sudoku", data)
	var can_resume: bool = adapter.can_resume()
	assert_true(can_resume, "Adapter should accept a 36-cell Mini save")


func test_save_adapter_rejects_invalid_size() -> void:
	var adapter := SudokuSaveAdapter.new()
	var data := {
		"puzzle": _make_array(25, 1),
		"solution": _make_array(25, 1),
		"current_grid": _make_array(25, 0),
		"difficulty": 0,
	}
	GameSaveManager.save_game("sudoku", data)
	var can_resume: bool = adapter.can_resume()
	assert_false(can_resume, "Adapter should reject a 25-cell puzzle (unsupported size)")


func test_save_adapter_legacy_81_cell_still_valid() -> void:
	var adapter := SudokuSaveAdapter.new()
	var data := {
		"puzzle": _make_array(81, 0),
		"solution": _make_array(81, 1),
		"current_grid": _make_array(81, 0),
		"difficulty": 1,
	}
	data["puzzle"][0] = 3
	data["current_grid"][0] = 3
	GameSaveManager.save_game("sudoku", data)
	var can_resume: bool = adapter.can_resume()
	assert_true(can_resume, "Adapter must still accept legacy 81-cell saves")


func test_save_adapter_legacy_no_spec_id_defaults_to_standard() -> void:
	var adapter := SudokuSaveAdapter.new()
	# Save without grid_spec_id (legacy format)
	var data := {
		"puzzle": _make_array(81, 0),
		"solution": _make_array(81, 1),
		"current_grid": _make_array(81, 0),
		"difficulty": 0,
	}
	data["puzzle"][5] = 7
	data["current_grid"][5] = 7
	GameSaveManager.save_game("sudoku", data)
	# Legacy saves with no grid_spec_id should still be resumable (treated as standard_9x9)
	var can_resume: bool = adapter.can_resume()
	assert_true(can_resume, "Legacy 81-cell save without grid_spec_id must be resumable")
	# The caller reads grid_spec_id with a "standard_9x9" default, so from_id is safe
	var loaded := GameSaveManager.load_game("sudoku")
	var spec_id: String = str(loaded.get("grid_spec_id", "standard_9x9"))
	var spec := SudokuGridSpec.from_id(spec_id)
	assert_not_null(spec)
	assert_eq(spec.id, "standard_9x9", "Missing grid_spec_id must default to standard_9x9")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_array(size: int, value: int) -> Array:
	var arr := []
	arr.resize(size)
	arr.fill(value)
	return arr
