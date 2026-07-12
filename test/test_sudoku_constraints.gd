extends GutTest

## Tests for the SudokuConstraint base class and its integration with
## SudokuSolver, SudokuLogic, and SudokuGenerator.

const LogicScript := preload("res://scripts/sudoku/sudoku_logic.gd")

# ---------------------------------------------------------------------------
# Shared puzzle/solution used by the logic tests
# ---------------------------------------------------------------------------

const TEST_PUZZLE: Array[int] = [
	5, 3, 0, 0, 7, 0, 0, 0, 0,
	6, 0, 0, 1, 9, 5, 0, 0, 0,
	0, 9, 8, 0, 0, 0, 0, 6, 0,
	8, 0, 0, 0, 6, 0, 0, 0, 3,
	4, 0, 0, 8, 0, 3, 0, 0, 1,
	7, 0, 0, 0, 2, 0, 0, 0, 6,
	0, 6, 0, 0, 0, 0, 2, 8, 0,
	0, 0, 0, 4, 1, 9, 0, 0, 5,
	0, 0, 0, 0, 8, 0, 0, 7, 9,
]
const TEST_SOLUTION: Array[int] = [
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
# Helper constraint: blocks a specific (index, value) pair
# ---------------------------------------------------------------------------

class BlockValueConstraint extends SudokuConstraint:
	var blocked_index: int
	var blocked_value: int

	func _init(idx: int, val: int) -> void:
		blocked_index = idx
		blocked_value = val

	func is_valid(grid: Array[int], index: int, value: int) -> bool:
		return not (index == blocked_index and value == blocked_value)

	func get_affected_indices(index: int) -> Array[int]:
		if index == blocked_index:
			return [blocked_index]
		return []

	func get_id() -> String:
		return "block_value_%d_%d" % [blocked_index, blocked_value]


# ---------------------------------------------------------------------------
# 1. SudokuConstraint base-class default implementations
# ---------------------------------------------------------------------------

func test_base_is_valid_always_true() -> void:
	var c := SudokuConstraint.new()
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	assert_true(c.is_valid(grid, 0, 5))


func test_base_get_affected_indices_empty() -> void:
	var c := SudokuConstraint.new()
	assert_eq(c.get_affected_indices(0).size(), 0)


func test_base_get_id_empty_string() -> void:
	var c := SudokuConstraint.new()
	assert_eq(c.get_id(), "")


# ---------------------------------------------------------------------------
# 2. SudokuSolver.is_valid_placement respects constraints
# ---------------------------------------------------------------------------

func test_solver_valid_placement_no_constraints() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	assert_true(SudokuSolver.is_valid_placement(grid, 0, 5, []))


func test_solver_constraint_blocks_value() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	var c := BlockValueConstraint.new(0, 5)
	assert_false(SudokuSolver.is_valid_placement(grid, 0, 5, [c]))


func test_solver_constraint_allows_other_values() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	var c := BlockValueConstraint.new(0, 5)
	assert_true(SudokuSolver.is_valid_placement(grid, 0, 6, [c]))


func test_solver_constraint_does_not_affect_other_indices() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	var c := BlockValueConstraint.new(0, 5)
	# Blocking value 5 at index 0 does not block value 5 at index 1
	assert_true(SudokuSolver.is_valid_placement(grid, 1, 5, [c]))


# ---------------------------------------------------------------------------
# 3. SudokuSolver.get_candidates respects constraints
# ---------------------------------------------------------------------------

func test_get_candidates_excludes_constraint_blocked_value() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	# Block values 1-8 at index 0 via standard row conflicts
	for i in range(1, 9):
		grid[i] = i  # fills row 0 cols 1-8 with 1-8
	# Without constraint, only 9 should be a candidate
	var base_cands := SudokuSolver.get_candidates(grid, 0, [])
	assert_eq(base_cands, [9])
	# Block 9 via constraint → no candidates
	var c := BlockValueConstraint.new(0, 9)
	var constrained_cands := SudokuSolver.get_candidates(grid, 0, [c])
	assert_eq(constrained_cands.size(), 0)


# ---------------------------------------------------------------------------
# 4. SudokuLogic.constraints property
# ---------------------------------------------------------------------------

func test_logic_constraints_default_empty() -> void:
	var logic := SudokuLogic.new()
	assert_eq(logic.constraints.size(), 0)


func test_logic_constraints_assignable() -> void:
	var logic := SudokuLogic.new()
	var c := BlockValueConstraint.new(0, 5)
	logic.constraints = [c]
	assert_eq(logic.constraints.size(), 1)


# ---------------------------------------------------------------------------
# 5. SudokuLogic strict mode — constraint violation adds a strike
# ---------------------------------------------------------------------------

func test_logic_strict_constraint_violation_adds_strike() -> void:
	var logic := SudokuLogic.new(true)  # strict mode
	logic._setup_from_arrays(0, TEST_PUZZLE, TEST_SOLUTION)
	# Cell 2 is empty in the puzzle; solution[2] == 4
	# Add a constraint that blocks placing 4 at index 2
	var c := BlockValueConstraint.new(2, 4)
	logic.constraints = [c]
	var result := logic.place_number(2, 4)
	# Even though 4 is the correct solution value, the constraint blocks it
	assert_true(result.valid, "attempt on editable cell should be valid")
	assert_false(result.placed, "should not be placed — constraint blocks it")
	assert_eq(result.strikes_added, 1, "constraint violation should add a strike")


func test_logic_strict_no_constraint_violation_places_correctly() -> void:
	var logic := SudokuLogic.new(true)
	logic._setup_from_arrays(0, TEST_PUZZLE, TEST_SOLUTION)
	# No constraints — correct answer should place
	var result := logic.place_number(2, 4)
	assert_true(result.placed)
	assert_eq(result.strikes_added, 0)


# ---------------------------------------------------------------------------
# 6. SudokuLogic free mode — constraint violation still places (free behaviour)
# ---------------------------------------------------------------------------

func test_logic_free_mode_constraint_violation_still_places() -> void:
	var logic := SudokuLogic.new(false)  # free (non-strict) mode
	logic._setup_from_arrays(0, TEST_PUZZLE, TEST_SOLUTION)
	# Block correct answer at cell 2 with a constraint
	var c := BlockValueConstraint.new(2, 4)
	logic.constraints = [c]
	# In free mode the number should still be placed (no enforcement)
	var result := logic.place_number(2, 4)
	assert_true(result.placed, "free mode should still place even with constraint")
	assert_eq(result.strikes_added, 0)


# ---------------------------------------------------------------------------
# 7. Standard Sudoku unchanged with empty constraints (regression guard)
# ---------------------------------------------------------------------------

func test_standard_sudoku_place_correct_no_regression() -> void:
	var logic := SudokuLogic.new(true)
	logic._setup_from_arrays(0, TEST_PUZZLE, TEST_SOLUTION)
	var result := logic.place_number(2, 4)
	assert_true(result.valid)
	assert_true(result.placed)
	assert_eq(result.strikes_added, 0)


func test_standard_sudoku_place_wrong_adds_strike() -> void:
	var logic := SudokuLogic.new(true)
	logic._setup_from_arrays(0, TEST_PUZZLE, TEST_SOLUTION)
	var result := logic.place_number(2, 9)  # wrong: solution[2] == 4
	assert_true(result.valid)
	assert_false(result.placed)
	assert_eq(result.strikes_added, 1)


func test_solver_is_valid_placement_no_regression() -> void:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	grid[3] = 7  # row conflict
	assert_false(SudokuSolver.is_valid_placement(grid, 0, 7))
