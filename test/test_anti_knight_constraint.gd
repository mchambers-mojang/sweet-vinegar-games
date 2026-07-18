extends GutTest

## Unit tests for AntiKnightConstraint and constraint-aware solver/generator integration.

const AntiKnightScript := preload("res://scripts/sudoku/anti_knight_constraint.gd")
const ConstraintScript := preload("res://scripts/sudoku/sudoku_constraint.gd")


# ---------------------------------------------------------------------------
# AntiKnightConstraint.get_id
# ---------------------------------------------------------------------------

func test_get_id_returns_anti_knight() -> void:
	var c := AntiKnightScript.new()
	assert_eq(c.get_id(), "anti_knight")


# ---------------------------------------------------------------------------
# AntiKnightConstraint.get_affected_indices — known positions
# ---------------------------------------------------------------------------

func test_affected_indices_centre_has_eight() -> void:
	var c := AntiKnightScript.new()
	# Cell 40 = row 4, col 4: every knight offset stays inside the grid.
	var indices := c.get_affected_indices(40)
	assert_eq(indices.size(), 8, "Centre cell should have 8 knight-reachable cells")


func test_affected_indices_corner_a1_has_two() -> void:
	var c := AntiKnightScript.new()
	# Cell 0 = row 0, col 0: only (1,2) and (2,1) are in range.
	var indices := c.get_affected_indices(0)
	assert_eq(indices.size(), 2, "Top-left corner should have 2 knight-reachable cells")
	# (0,0) + (1,2) = (1,2) → index 1*9+2 = 11
	# (0,0) + (2,1) = (2,1) → index 2*9+1 = 19
	assert_true(11 in indices, "Index 11 (row1,col2) reachable from corner")
	assert_true(19 in indices, "Index 19 (row2,col1) reachable from corner")


func test_affected_indices_no_duplicates() -> void:
	var c := AntiKnightScript.new()
	for i in 81:
		var indices := c.get_affected_indices(i)
		var seen: Dictionary = {}
		for idx in indices:
			assert_false(seen.has(idx), "No duplicate in get_affected_indices(%d)" % i)
			seen[idx] = true


func test_affected_indices_all_in_bounds() -> void:
	var c := AntiKnightScript.new()
	for i in 81:
		for idx in c.get_affected_indices(i):
			assert_true(idx >= 0 and idx < 81,
				"Affected index %d out of bounds for cell %d" % [idx, i])


func test_affected_indices_symmetric() -> void:
	# If B is reachable from A, then A is reachable from B.
	var c := AntiKnightScript.new()
	for i in 81:
		for j in c.get_affected_indices(i):
			assert_true(i in c.get_affected_indices(j),
				"Symmetry: %d reachable from %d but not vice versa" % [j, i])


# ---------------------------------------------------------------------------
# AntiKnightConstraint.is_valid — conflict detection
# ---------------------------------------------------------------------------

func test_is_valid_empty_grid_always_true() -> void:
	var c := AntiKnightScript.new()
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	for i in 81:
		for v in range(1, 10):
			assert_true(c.is_valid(grid, i, v), "Empty grid: any placement should be valid")


func test_is_valid_detects_knight_conflict() -> void:
	var c := AntiKnightScript.new()
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	# Place 5 at cell 40 (row4,col4).  Cell 21 = row2,col3 is a knight move away
	# from cell 40: (-2,-1) → row2, col3.
	grid[40] = 5
	# Knight offsets from 21 (row2,col3): check if 40 is reachable
	# +2,+1 → row4,col4 = 40 ✓
	assert_false(c.is_valid(grid, 21, 5),
		"Placing 5 at a knight-reachable cell from another 5 must be invalid")


func test_is_valid_no_conflict_different_value() -> void:
	var c := AntiKnightScript.new()
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	grid[40] = 5
	# Cell 21 is knight-reachable but we're placing 6, not 5 — should be ok.
	assert_true(c.is_valid(grid, 21, 6), "Different value at knight distance must be valid")


func test_is_valid_no_conflict_non_knight_cell() -> void:
	var c := AntiKnightScript.new()
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	grid[40] = 5
	# Cell 41 = row4, col5 — only one step to the right, NOT a knight move.
	assert_true(c.is_valid(grid, 41, 5), "Adjacent (non-knight) cell must not trigger conflict")


# ---------------------------------------------------------------------------
# SudokuConstraint base class
# ---------------------------------------------------------------------------

func test_base_constraint_is_always_valid() -> void:
	var c := ConstraintScript.new()
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	assert_true(c.is_valid(grid, 0, 5), "Base constraint should always return true")


func test_base_constraint_empty_affected() -> void:
	var c := ConstraintScript.new()
	assert_eq(c.get_affected_indices(0).size(), 0)


func test_base_constraint_empty_id() -> void:
	var c := ConstraintScript.new()
	assert_eq(c.get_id(), "")


# ---------------------------------------------------------------------------
# SudokuSolver — constraint-aware brute-force (standard result unchanged)
# ---------------------------------------------------------------------------

func test_solver_constrained_standard_puzzle_still_unique() -> void:
	# A standard puzzle solution should also be unique under standard (no-constraint) rules.
	var grid: Array[int] = [
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
	var typed_grid: Array[int] = []
	typed_grid.assign(grid)
	var solutions := SudokuSolver.solve_brute_force(typed_grid, 2, [])
	assert_eq(solutions.size(), 1, "Well-known puzzle should have one solution without constraints")


func test_solver_constrained_empty_constraints_matches_standard() -> void:
	# solve_brute_force with empty constraints should give the same result as without.
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	var s1 := SudokuSolver.solve_brute_force(grid, 2)
	var s2 := SudokuSolver.solve_brute_force(grid, 2, [])
	assert_eq(s1.size(), s2.size(), "Empty constraints should not change solution count")


# ---------------------------------------------------------------------------
# SudokuLogic — constraints array and PlaceResult.constraint_conflicts
# ---------------------------------------------------------------------------

func test_logic_default_constraints_empty() -> void:
	var logic := SudokuLogic.new()
	assert_eq(logic.constraints.size(), 0, "Default SudokuLogic should have no constraints")


func test_logic_accepts_constraint() -> void:
	var c := AntiKnightScript.new()
	var logic := SudokuLogic.new()
	logic.constraints = [c]
	assert_eq(logic.constraints.size(), 1, "Logic should store the provided constraint")
	assert_eq(logic.constraints[0].get_id(), "anti_knight")


func test_place_result_has_constraint_conflicts_field() -> void:
	var r := SudokuLogic.PlaceResult.new()
	assert_true(r.constraint_conflicts is Array, "PlaceResult must have constraint_conflicts Array")
	assert_true(r.constraint_conflicts.is_empty(), "Defaults to empty")


func test_no_conflict_reported_in_strict_mode() -> void:
	# In strict mode, wrong placements get a strike and don't go through the constraint path.
	var puzzle: Array[int] = []
	puzzle.resize(81)
	puzzle.fill(0)
	var solution: Array[int] = []
	solution.assign(SudokuGenerator.SEED_GRID)
	var c := AntiKnightScript.new()
	var logic := SudokuLogic.new(true)
	logic.constraints = [c]
	logic._setup_from_arrays(0, puzzle, solution)
	# Place the correct value at index 0 (no conflict possible in strict mode path).
	var r := logic.place_number(0, solution[0])
	assert_true(r.placed or r.strikes_added > 0)
	# In strict mode a correct placement doesn't go through the constraint conflict path.
	if r.placed:
		assert_true(r.constraint_conflicts.is_empty(),
			"Strict mode correct placement should not report constraint conflicts")


# ---------------------------------------------------------------------------
# SudokuSaveAdapter — get_rule_set
# ---------------------------------------------------------------------------

func test_save_adapter_get_rule_set_default_zero() -> void:
	var adapter := SudokuSaveAdapter.new()
	assert_eq(adapter.get_rule_set(), 0)


func test_save_adapter_get_rule_set_roundtrip() -> void:
	var adapter := SudokuSaveAdapter.new()
	var puzzle: Array[int] = []
	puzzle.resize(81)
	puzzle.fill(1)
	var solution: Array[int] = []
	solution.resize(81)
	solution.fill(5)
	adapter.save({
		"puzzle": puzzle,
		"solution": solution,
		"current_grid": puzzle.duplicate(),
		"rule_set": 1,
	})
	assert_eq(adapter.get_rule_set(), 1)
	adapter.clear()


# ---------------------------------------------------------------------------
# LaunchParams — rule_set field
# ---------------------------------------------------------------------------

func test_launch_params_default_rule_set_is_zero() -> void:
	var p := LaunchParams.new()
	assert_eq(p.rule_set, 0)


func test_launch_params_stores_rule_set() -> void:
	var p := LaunchParams.new()
	p.rule_set = 1
	assert_eq(p.rule_set, 1)
