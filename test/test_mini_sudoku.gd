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
	var res := logic.place_number(empty_idx, correct_val)
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
		"rule_set": 4,
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


# ---------------------------------------------------------------------------
# 6. Regression: save adapter rejects malformed current_grid / solution
# ---------------------------------------------------------------------------

func test_save_adapter_rejects_mismatched_current_grid_size() -> void:
	## Regression for: malformed Mini saves can crash resume.
	## current_grid with wrong size must be treated as corrupted.
	var adapter := SudokuSaveAdapter.new()
	var data := {
		"puzzle": _make_array(36, 0),
		"solution": _make_array(36, 1),
		"current_grid": _make_array(9, 0),   # Wrong: 9 instead of 36
		"grid_spec_id": "mini_6x6",
		"rule_set": 4,
		"difficulty": 0,
	}
	data["puzzle"][0] = 1
	GameSaveManager.save_game("sudoku", data)
	var can_resume: bool = adapter.can_resume()
	assert_false(can_resume, "Adapter must reject a save whose current_grid size does not match spec")


func test_save_adapter_rejects_mismatched_solution_size() -> void:
	## Regression for: malformed Mini saves can crash resume.
	## solution with wrong size must be treated as corrupted.
	var adapter := SudokuSaveAdapter.new()
	var data := {
		"puzzle": _make_array(36, 0),
		"solution": _make_array(81, 1),   # Wrong: 81 instead of 36
		"current_grid": _make_array(36, 0),
		"grid_spec_id": "mini_6x6",
		"rule_set": 4,
		"difficulty": 0,
	}
	data["puzzle"][0] = 1
	data["current_grid"][0] = 1
	GameSaveManager.save_game("sudoku", data)
	var can_resume: bool = adapter.can_resume()
	assert_false(can_resume, "Adapter must reject a save whose solution size does not match spec")


func test_save_adapter_rejects_null_current_grid() -> void:
	## Regression for: malformed Mini saves can crash resume.
	## Missing current_grid key must be treated as corrupted.
	var adapter := SudokuSaveAdapter.new()
	var data := {
		"puzzle": _make_array(36, 0),
		"solution": _make_array(36, 1),
		# current_grid intentionally absent
		"grid_spec_id": "mini_6x6",
		"rule_set": 4,
		"difficulty": 0,
	}
	data["puzzle"][0] = 1
	GameSaveManager.save_game("sudoku", data)
	var can_resume: bool = adapter.can_resume()
	assert_false(can_resume, "Adapter must reject a save with no current_grid key")


# ---------------------------------------------------------------------------
# 7. Regression: Mini generator produces uniquely-solvable puzzles
# ---------------------------------------------------------------------------

func test_generator_6x6_puzzle_is_unique() -> void:
	## Regression for: human-logic solvability not enforced.
	## The generator must now run uniqueness analysis for Mini and only
	## accept puzzles with exactly one solution.
	var gen := SudokuGenerator.new()
	var spec := SudokuGridSpec.MINI_6X6
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 42, [], spec)
	assert_true(result.has("puzzle"), "Result must contain puzzle")
	var puzzle: Array = result["puzzle"]
	var solver := SudokuSolver.new()
	solver.analyze(puzzle, [], spec)
	assert_true(solver.is_unique, "Generated Mini puzzle must have a unique solution")


func test_generator_6x6_unique_across_seeds() -> void:
	## Additional uniqueness regression: verify several seeds all produce unique puzzles.
	var gen := SudokuGenerator.new()
	var spec := SudokuGridSpec.MINI_6X6
	for seed_val in [1, 7, 13, 99, 200]:
		var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, seed_val, [], spec)
		assert_true(result.has("puzzle"), "Seed %d: result must contain puzzle" % seed_val)
		var puzzle: Array = result["puzzle"]
		var solver := SudokuSolver.new()
		solver.analyze(puzzle, [], spec)
		assert_true(solver.is_unique, "Seed %d: Mini puzzle must have a unique solution" % seed_val)


# ---------------------------------------------------------------------------
# 8. Regression: SudokuLogic.is_solved() public API
# ---------------------------------------------------------------------------

func test_logic_is_solved_returns_false_when_incomplete() -> void:
	## Regression for: test_mini_sudoku called nonexistent is_solved().
	## The method must exist and return false on a partial board.
	var logic := LogicScript.new(false, true)
	logic.spec = SudokuGridSpec.MINI_6X6
	logic._setup_from_arrays(0, TEST_PUZZLE_6X6, TEST_SOLUTION_6X6)
	assert_false(logic.is_solved(), "is_solved() must return false when board is incomplete")


func test_logic_is_solved_returns_true_when_complete() -> void:
	## Regression: is_solved() must reflect grid==solution without requiring place_number.
	var logic := LogicScript.new(false, true)
	logic.spec = SudokuGridSpec.MINI_6X6
	logic._setup_from_arrays(0, TEST_PUZZLE_6X6, TEST_SOLUTION_6X6)
	for i in 36:
		logic.current_grid[i] = logic.solution[i]
	assert_true(logic.is_solved(), "is_solved() must return true when all cells match solution")


func test_logic_place_number_api_exists() -> void:
	## Regression for: tests called nonexistent place() instead of place_number().
	## Verify place_number() exists and returns a PlaceResult with expected fields.
	var logic := LogicScript.new(false, true)
	logic.spec = SudokuGridSpec.MINI_6X6
	logic._setup_from_arrays(0, TEST_PUZZLE_6X6, TEST_SOLUTION_6X6)
	var empty_idx := -1
	for i in 36:
		if logic.puzzle[i] == 0:
			empty_idx = i
			break
	assert_true(empty_idx >= 0, "Test puzzle must have at least one empty cell")
	var result := logic.place_number(empty_idx, logic.solution[empty_idx])
	assert_true(result.valid, "place_number() result must have valid field")
	assert_true(result.placed, "place_number() of correct value must be placed")
	assert_eq(result.cell_index, empty_idx, "place_number() result must carry cell_index")


# ---------------------------------------------------------------------------
# 9. Regression: SudokuSolver.is_logic_solvable via analyze()
# ---------------------------------------------------------------------------

func test_solver_analyze_sets_is_logic_solvable_for_mini_puzzle() -> void:
	## Regression for: SudokuSolver.analyze() must expose whether solve_logic()
	## completed the puzzle. is_logic_solvable must be true for the known 6×6 fixture.
	var spec := SudokuGridSpec.MINI_6X6
	var puzzle: Array[int] = TEST_PUZZLE_6X6.duplicate()
	var solver := SudokuSolver.new()
	solver.analyze(puzzle, [], spec)
	assert_true(solver.is_unique, "Known test puzzle must be unique")
	assert_true(solver.is_logic_solvable, "Known 6×6 puzzle must be solvable by logic alone")


func test_solver_analyze_is_logic_solvable_false_for_incomplete() -> void:
	## is_logic_solvable must be false when a puzzle still has empty cells after
	## the logic solver runs (i.e. requires guessing). A nearly-empty 6×6 grid
	## that cannot be finished by naked/hidden singles must return false.
	var spec := SudokuGridSpec.MINI_6X6
	# An almost-empty 6×6 grid — logic alone cannot determine unique placements.
	var near_empty: Array[int] = [
		1, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0,
	]
	var solver := SudokuSolver.new()
	solver.analyze(near_empty, [], spec)
	assert_false(solver.is_logic_solvable, "Near-empty puzzle must not be logic-solvable")


func test_generator_6x6_is_logic_solvable() -> void:
	## Regression for: Mini generation must enforce human-logic solvability.
	## The generator must only return puzzles that can be solved by logic alone.
	var gen := SudokuGenerator.new()
	var spec := SudokuGridSpec.MINI_6X6
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 42, [], spec)
	assert_true(result.has("puzzle"), "Generator must return a puzzle")
	var puzzle: Array = result["puzzle"]
	var p6: Array[int] = []
	p6.assign(puzzle)
	var solver := SudokuSolver.new()
	solver.analyze(p6, [], spec)
	assert_true(solver.is_unique, "Generated Mini puzzle must have a unique solution")
	assert_true(solver.is_logic_solvable, "Generated Mini puzzle must be solvable by logic alone")


# ---------------------------------------------------------------------------
# 10. Regression: save adapter validates rule_set and symbol ranges
# ---------------------------------------------------------------------------

func test_save_adapter_rejects_mini_with_wrong_rule_set() -> void:
	## Regression for: Mini save without Mini rule_set resumes as Standard and
	## can corrupt Standard Easy statistics. rule_set=0 must be rejected.
	var adapter := SudokuSaveAdapter.new()
	var data := {
		"puzzle": _make_array(36, 0),
		"solution": _make_array(36, 1),
		"current_grid": _make_array(36, 0),
		"grid_spec_id": "mini_6x6",
		"rule_set": 0,  # Standard — incompatible with mini_6x6 spec
		"difficulty": 0,
	}
	data["puzzle"][0] = 1
	data["current_grid"][0] = 1
	GameSaveManager.save_game("sudoku", data)
	var can_resume: bool = adapter.can_resume()
	assert_false(can_resume, "Adapter must reject a Mini-spec save with rule_set=0 (Standard)")


func test_save_adapter_rejects_mini_with_missing_rule_set() -> void:
	## Regression: a 36-cell save whose rule_set key is absent must be rejected.
	## Missing rule_set defaults to 0 (Standard) which would corrupt Standard stats.
	var adapter := SudokuSaveAdapter.new()
	var data := {
		"puzzle": _make_array(36, 0),
		"solution": _make_array(36, 1),
		"current_grid": _make_array(36, 0),
		"grid_spec_id": "mini_6x6",
		# rule_set intentionally absent
		"difficulty": 0,
	}
	data["puzzle"][0] = 1
	data["current_grid"][0] = 1
	GameSaveManager.save_game("sudoku", data)
	var can_resume: bool = adapter.can_resume()
	assert_false(can_resume, "Adapter must reject a Mini-spec save with no rule_set key")


func test_save_adapter_rejects_mini_with_is_killer() -> void:
	## Mini saves with is_killer=true must be rejected — Killer is incompatible with Mini.
	var adapter := SudokuSaveAdapter.new()
	var data := {
		"puzzle": _make_array(36, 0),
		"solution": _make_array(36, 1),
		"current_grid": _make_array(36, 0),
		"grid_spec_id": "mini_6x6",
		"rule_set": 4,
		"is_killer": true,
		"difficulty": 0,
	}
	data["puzzle"][0] = 1
	data["current_grid"][0] = 1
	GameSaveManager.save_game("sudoku", data)
	var can_resume: bool = adapter.can_resume()
	assert_false(can_resume, "Adapter must reject a Mini save that also claims is_killer=true")


func test_save_adapter_rejects_out_of_range_symbols() -> void:
	## Regression: symbol values outside [sym_min, sym_max] must be rejected.
	## A Mini puzzle containing a '9' (valid in 9×9 but not in 6×6) must be rejected.
	var adapter := SudokuSaveAdapter.new()
	var data := {
		"puzzle": _make_array(36, 0),
		"solution": _make_array(36, 1),
		"current_grid": _make_array(36, 0),
		"grid_spec_id": "mini_6x6",
		"rule_set": 4,
		"difficulty": 0,
	}
	data["puzzle"][0] = 9  # Out of range — 6×6 only allows 1–6
	data["current_grid"][0] = 9
	GameSaveManager.save_game("sudoku", data)
	var can_resume: bool = adapter.can_resume()
	assert_false(can_resume, "Adapter must reject a Mini save with symbol 9 (out of 1–6 range)")


# ---------------------------------------------------------------------------
# 11. Regression: completion effect cell indices call production code
# ---------------------------------------------------------------------------
# These tests call SudokuLogic.place_number() (which invokes _get_completed_units)
# and verify that the units_completed entries carry the correct cell indices for a
# 6×6 grid — not the hardcoded 9×9 values that existed before generalization.

func _make_near_complete_logic_except(skip_cell: int) -> LogicScript:
	## Return a 6×6 SudokuLogic where every cell except skip_cell has the
	## correct solution value already placed.  The caller may then place
	## skip_cell via place_number() to trigger unit-completion reporting.
	var logic := LogicScript.new(false, true)
	logic.spec = SudokuGridSpec.MINI_6X6
	logic._setup_from_arrays(0, TEST_PUZZLE_6X6, TEST_SOLUTION_6X6)
	for i in 36:
		if i != skip_cell:
			logic.current_grid[i] = logic.solution[i]
	logic.current_grid[skip_cell] = 0
	return logic


func test_completion_effect_row_cells_via_place_number_6x6() -> void:
	## Regression: completion effects used hardcoded 9×9 row span (0–8).
	## Placing the last cell in row 0 of a 6×6 grid must report cells 0–5 only.
	# Cell 1 is editable (puzzle[1]=0) and belongs to row 0.
	var logic := _make_near_complete_logic_except(1)
	var result := logic.place_number(1, logic.solution[1])
	assert_true(result.placed, "Placement must succeed")
	var row_unit: Dictionary = {}
	for u: Dictionary in result.units_completed:
		if u["type"] == "row" and u["unit_index"] == 0:
			row_unit = u
			break
	assert_false(row_unit.is_empty(), "Row 0 must appear in units_completed")
	var cells: Array = row_unit["cells"]
	assert_eq(cells.size(), 6, "Row 0 in 6×6 must have 6 cells (not 9)")
	assert_eq(cells[0], 0, "Row 0 first cell = 0")
	assert_eq(cells[5], 5, "Row 0 last cell = 5 (not 8 as in 9×9)")


func test_completion_effect_col_cells_via_place_number_6x6() -> void:
	## Regression: completion effects used hardcoded col span ending at cell 72.
	## Col 1 cells in 6×6 are 1, 7, 13, 19, 25, 31 — the last is 31, not 73.
	# Cell 1 is editable (puzzle[1]=0) and belongs to col 1.
	var logic := _make_near_complete_logic_except(1)
	var result := logic.place_number(1, logic.solution[1])
	assert_true(result.placed, "Placement must succeed")
	var col_unit: Dictionary = {}
	for u: Dictionary in result.units_completed:
		if u["type"] == "col" and u["unit_index"] == 1:
			col_unit = u
			break
	assert_false(col_unit.is_empty(), "Col 1 must appear in units_completed")
	var cells: Array = col_unit["cells"]
	assert_eq(cells.size(), 6, "Col 1 in 6×6 must have 6 cells (not 9)")
	assert_eq(cells[0], 1, "Col 1 first cell = 1")
	assert_eq(cells[5], 31, "Col 1 last cell = 31 (not 73 as in 9×9)")


func test_completion_effect_box_cells_via_place_number_6x6() -> void:
	## Regression: completion effects used hardcoded 3×3 box span.
	## Box 0 in 6×6 (rows 0–1 × cols 0–2) has 6 cells; last is index 8, not 20.
	# Cell 1 (row 0, col 1) is in box 0 and is editable (puzzle[1]=0).
	var logic := _make_near_complete_logic_except(1)
	var result := logic.place_number(1, logic.solution[1])
	assert_true(result.placed, "Placement must succeed")
	var box_unit: Dictionary = {}
	for u: Dictionary in result.units_completed:
		if u["type"] == "box" and u["unit_index"] == 0:
			box_unit = u
			break
	assert_false(box_unit.is_empty(), "Box 0 must appear in units_completed")
	var cells: Array = box_unit["cells"]
	assert_eq(cells.size(), 6, "Box 0 in 6×6 must have 6 cells (not 9)")
	assert_eq(cells[0], 0, "Box 0 first cell = 0")
	assert_eq(cells[5], 8, "Box 0 last cell = 8 (rows 0–1 × cols 0–2)")


# ---------------------------------------------------------------------------
# 12. Regression: Mini completion does not corrupt Standard statistics
# ---------------------------------------------------------------------------
# These tests inject a lightweight MockStats into a SudokuGameScreen subclass
# (without a scene tree) and call _record_sudoku_completion() directly to
# prove that Mini rule_set guards work as intended.

class MockStatsMini:
	var counters: Dictionary = {}
	var records: Array = []

	func record(_game_id: String, entry: Dictionary) -> void:
		records.append(entry)

	func increment_counter(game_id: String, key: String, _amount: int = 1) -> void:
		var full_key := game_id + "." + key
		counters[full_key] = counters.get(full_key, 0) + _amount

	func set_counter(game_id: String, key: String, value: int) -> void:
		counters[game_id + "." + key] = value

	func get_counter(game_id: String, key: String) -> int:
		return counters.get(game_id + "." + key, 0)


class TestSudokuScreen extends "res://scripts/sudoku/sudoku_game_screen.gd":
	pass  # Inherits GameScreen._init(…) which accepts p_stats injection.


func test_mini_completion_does_not_update_standard_easy_counters() -> void:
	## Regression: Mini completion must not increment completed_d0 / won_d0 / lost_d0.
	## A strict Mini win must increment completed_mini (not the Standard Easy counters).
	var stats := MockStatsMini.new()
	# Pass stats as the 7th positional arg (p_stats); all others default to autoloads.
	var screen := TestSudokuScreen.new(null, null, null, null, null, null, stats)
	screen.rule_set = 4  # RULE_SET_MINI
	screen._record_sudoku_completion(0, 60.0, true, true)  # strict win, difficulty=0
	assert_eq(stats.counters.get("sudoku.completed_d0", 0), 0,
		"Mini must not increment Standard Easy completed_d0")
	assert_eq(stats.counters.get("sudoku.won_d0", 0), 0,
		"Mini must not increment Standard Easy won_d0")
	assert_eq(stats.counters.get("sudoku.lost_d0", 0), 0,
		"Mini must not increment Standard Easy lost_d0")
	assert_eq(stats.counters.get("sudoku.completed_mini", 0), 1,
		"Mini must increment completed_mini")
	screen.free()


func test_mini_loss_does_not_update_standard_easy_lost_counter() -> void:
	## Regression: a strict Mini loss must not increment lost_d0.
	var stats := MockStatsMini.new()
	var screen := TestSudokuScreen.new(null, null, null, null, null, null, stats)
	screen.rule_set = 4  # RULE_SET_MINI
	screen._record_sudoku_completion(0, 60.0, true, false)  # strict loss
	assert_eq(stats.counters.get("sudoku.lost_d0", 0), 0,
		"Mini loss must not increment Standard Easy lost_d0")
	assert_eq(stats.counters.get("sudoku.won_d0", 0), 0,
		"Mini loss must not increment Standard Easy won_d0")
	screen.free()


func test_standard_easy_win_does_update_d0_counters() -> void:
	## Positive control: Standard Easy must still update completed_d0 and won_d0.
	var stats := MockStatsMini.new()
	var screen := TestSudokuScreen.new(null, null, null, null, null, null, stats)
	screen.rule_set = 0  # RULE_SET_STANDARD
	screen._record_sudoku_completion(0, 120.0, true, true)  # strict win, diff 0
	assert_eq(stats.counters.get("sudoku.completed_d0", 0), 1,
		"Standard Easy must increment completed_d0")
	assert_eq(stats.counters.get("sudoku.won_d0", 0), 1,
		"Standard Easy must increment won_d0")
	assert_eq(stats.counters.get("sudoku.completed_mini", 0), 0,
		"Standard Easy must not touch completed_mini")
	screen.free()


# ---------------------------------------------------------------------------
# 13. Regression: generator fallback enforces logic-solvability for Mini
# ---------------------------------------------------------------------------

func test_generator_6x6_logic_solvable_across_seeds() -> void:
	## Regression: both normal path and fallback path must return logic-solvable
	## puzzles. Verifying multiple seeds covers a broader range of generation paths.
	var gen := SudokuGenerator.new()
	var spec := SudokuGridSpec.MINI_6X6
	for seed_val in [1, 7, 13, 42, 99, 200]:
		var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, seed_val, [], spec)
		assert_true(result.has("puzzle"),
			"Seed %d: result must contain puzzle" % seed_val)
		var puzzle: Array = result["puzzle"]
		var p6: Array[int] = []
		p6.assign(puzzle)
		var solver := SudokuSolver.new()
		solver.analyze(p6, [], spec)
		assert_true(solver.is_logic_solvable,
			"Seed %d: Mini puzzle must be solvable by logic alone (not just unique)" % seed_val)


# ---------------------------------------------------------------------------
# 14. Regression: save adapter rejects Mini saves with incompatible difficulty
# ---------------------------------------------------------------------------

func test_save_adapter_rejects_mini_with_nonzero_difficulty() -> void:
	## Mini is a single quick-play difficulty (Easy = 0). A save with difficulty=1
	## indicates data corruption or rule-set mismatch and must be rejected.
	var adapter := SudokuSaveAdapter.new()
	var data := {
		"puzzle": _make_array(36, 0),
		"solution": _make_array(36, 1),
		"current_grid": _make_array(36, 0),
		"grid_spec_id": "mini_6x6",
		"rule_set": 4,
		"difficulty": 1,  # invalid for Mini
	}
	data["puzzle"][0] = 1
	data["current_grid"][0] = 1
	GameSaveManager.save_game("sudoku", data)
	var can_resume: bool = adapter.can_resume()
	assert_false(can_resume, "Adapter must reject a Mini save with difficulty=1")


func test_save_adapter_accepts_mini_with_difficulty_zero() -> void:
	## Positive control: a valid Mini save with difficulty=0 must be accepted.
	var adapter := SudokuSaveAdapter.new()
	var data := {
		"puzzle": _make_array(36, 0),
		"solution": _make_array(36, 1),
		"current_grid": _make_array(36, 0),
		"grid_spec_id": "mini_6x6",
		"rule_set": 4,
		"difficulty": 0,
	}
	data["puzzle"][0] = 1
	data["current_grid"][0] = 1
	GameSaveManager.save_game("sudoku", data)
	var can_resume: bool = adapter.can_resume()
	assert_true(can_resume, "Valid Mini save with difficulty=0 must be accepted")
