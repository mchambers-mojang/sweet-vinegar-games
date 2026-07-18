extends GutTest

## Unit tests for SudokuConstraint, AntiKnightConstraint, and AntiKingConstraint.


# ---------------------------------------------------------------------------
# Helper: build a 9×9 grid from a flat array (0 = empty)
# ---------------------------------------------------------------------------

func _make_grid(values: Array) -> Array[int]:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	for i in min(values.size(), 81):
		grid[i] = int(values[i])
	return grid


func _empty_grid() -> Array[int]:
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	return grid


# ---------------------------------------------------------------------------
# SudokuConstraint base (identity — never blocks)
# ---------------------------------------------------------------------------

func test_base_constraint_is_valid_always_true() -> void:
	var c := SudokuConstraint.new()
	var grid := _empty_grid()
	for i in 81:
		assert_true(c.is_valid(grid, i, 5))


func test_base_constraint_get_affected_indices_empty() -> void:
	var c := SudokuConstraint.new()
	for i in 81:
		assert_eq(c.get_affected_indices(i).size(), 0)


func test_base_constraint_get_id_empty() -> void:
	var c := SudokuConstraint.new()
	assert_eq(c.get_id(), "")


# ---------------------------------------------------------------------------
# AntiKingConstraint — get_id
# ---------------------------------------------------------------------------

func test_anti_king_get_id() -> void:
	var c := AntiKingConstraint.new()
	assert_eq(c.get_id(), "anti_king")


# ---------------------------------------------------------------------------
# AntiKingConstraint — get_affected_indices
# ---------------------------------------------------------------------------

func test_anti_king_corner_has_one_diagonal() -> void:
	# Top-left corner (0,0) → only diagonal is (1,1) = index 10
	var c := AntiKingConstraint.new()
	var affected := c.get_affected_indices(0)
	assert_eq(affected.size(), 1)
	assert_true(10 in affected)


func test_anti_king_top_edge_has_two_diagonals() -> void:
	# Top-middle (0,4) → diagonals are (1,3)=12 and (1,5)=14
	var c := AntiKingConstraint.new()
	var affected := c.get_affected_indices(4)
	assert_eq(affected.size(), 2)
	assert_true(12 in affected)
	assert_true(14 in affected)


func test_anti_king_center_has_four_diagonals() -> void:
	# Center (4,4) = index 40
	var c := AntiKingConstraint.new()
	var affected := c.get_affected_indices(40)
	assert_eq(affected.size(), 4)
	# Diagonals: (3,3)=30, (3,5)=32, (5,3)=48, (5,5)=50
	assert_true(30 in affected)
	assert_true(32 in affected)
	assert_true(48 in affected)
	assert_true(50 in affected)


func test_anti_king_bottom_right_corner_has_one_diagonal() -> void:
	# Bottom-right (8,8) = index 80 → only diagonal is (7,7) = 63
	var c := AntiKingConstraint.new()
	var affected := c.get_affected_indices(80)
	assert_eq(affected.size(), 1)
	assert_true(63 in affected)


# ---------------------------------------------------------------------------
# AntiKingConstraint — is_valid
# ---------------------------------------------------------------------------

func test_anti_king_valid_when_diagonal_empty() -> void:
	var c := AntiKingConstraint.new()
	var grid := _empty_grid()
	# Placing 5 at index 40 with all diagonals empty — should be valid
	assert_true(c.is_valid(grid, 40, 5))


func test_anti_king_invalid_when_diagonal_has_same_value() -> void:
	var c := AntiKingConstraint.new()
	var grid := _empty_grid()
	# Place 5 at (3,3)=30 which is diagonal to (4,4)=40
	grid[30] = 5
	assert_false(c.is_valid(grid, 40, 5))


func test_anti_king_valid_when_diagonal_has_different_value() -> void:
	var c := AntiKingConstraint.new()
	var grid := _empty_grid()
	grid[30] = 7  # Different value
	assert_true(c.is_valid(grid, 40, 5))


func test_anti_king_invalid_each_diagonal_direction() -> void:
	var c := AntiKingConstraint.new()
	# Center is index 40 (row=4, col=4)
	# Diagonals: TL=(3,3)=30, TR=(3,5)=32, BL=(5,3)=48, BR=(5,5)=50
	for diag_idx in [30, 32, 48, 50]:
		var grid := _empty_grid()
		grid[diag_idx] = 3
		assert_false(c.is_valid(grid, 40, 3),
			"Should fail when diagonal at %d has same value" % diag_idx)


func test_anti_king_no_false_positive_orthogonal() -> void:
	# Orthogonal neighbours are NOT covered by AntiKingConstraint alone
	var c := AntiKingConstraint.new()
	var grid := _empty_grid()
	# Place same value in cells directly above/below/left/right of 40
	grid[31] = 5  # (3,4) — above
	grid[49] = 5  # (5,4) — below
	grid[39] = 5  # (4,3) — left
	grid[41] = 5  # (4,5) — right
	# AntiKingConstraint only checks diagonals, so all four should pass individually
	assert_true(c.is_valid(grid, 40, 5))


func test_anti_king_corner_diagonal_constraint() -> void:
	# Bottom-right corner (8,8)=80. Only diagonal is (7,7)=63.
	var c := AntiKingConstraint.new()
	var grid := _empty_grid()
	grid[63] = 9
	assert_false(c.is_valid(grid, 80, 9))
	assert_true(c.is_valid(grid, 80, 1))


# ---------------------------------------------------------------------------
# AntiKnightConstraint — get_id
# ---------------------------------------------------------------------------

func test_anti_knight_get_id() -> void:
	var c := AntiKnightConstraint.new()
	assert_eq(c.get_id(), "anti_knight")


# ---------------------------------------------------------------------------
# AntiKnightConstraint — get_affected_indices
# ---------------------------------------------------------------------------

func test_anti_knight_corner_has_two_moves() -> void:
	# Top-left (0,0): knight moves to (1,2)=11 and (2,1)=19
	var c := AntiKnightConstraint.new()
	var affected := c.get_affected_indices(0)
	assert_eq(affected.size(), 2)
	assert_true(11 in affected)
	assert_true(19 in affected)


func test_anti_knight_center_has_eight_moves() -> void:
	# Center (4,4)=40: all 8 knight moves are on the board
	var c := AntiKnightConstraint.new()
	var affected := c.get_affected_indices(40)
	assert_eq(affected.size(), 8)


func test_anti_knight_edge_has_fewer_moves() -> void:
	# (0,3) — top row, 4th column: moves to (1,1)=10, (1,5)=14, (2,2)=20, (2,4)=22
	var c := AntiKnightConstraint.new()
	var affected := c.get_affected_indices(3)
	assert_eq(affected.size(), 4)


# ---------------------------------------------------------------------------
# AntiKnightConstraint — is_valid
# ---------------------------------------------------------------------------

func test_anti_knight_valid_when_knight_cells_empty() -> void:
	var c := AntiKnightConstraint.new()
	var grid := _empty_grid()
	assert_true(c.is_valid(grid, 40, 5))


func test_anti_knight_invalid_when_knight_cell_has_same_value() -> void:
	# (4,4)=40; knight move (4+2, 4+1)=(6,5)=59
	var c := AntiKnightConstraint.new()
	var grid := _empty_grid()
	grid[59] = 5
	assert_false(c.is_valid(grid, 40, 5))


func test_anti_knight_valid_when_knight_cell_has_different_value() -> void:
	var c := AntiKnightConstraint.new()
	var grid := _empty_grid()
	grid[59] = 7
	assert_true(c.is_valid(grid, 40, 5))


# ---------------------------------------------------------------------------
# SudokuSolver: constraint-aware solve_brute_force
# ---------------------------------------------------------------------------

func test_solver_respects_anti_king_constraint() -> void:
	var c := AntiKingConstraint.new()
	# Build a nearly-complete grid and check the solver can complete it respecting anti-king.
	# Use a known valid anti-king solution seed (just verify uniqueness machinery works).
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	var solutions := SudokuSolver.solve_brute_force(grid, 1, [c])
	# An anti-king solution must exist (they are known to exist)
	assert_eq(solutions.size(), 1, "Exactly one anti-king solution must be found")
	# Verify it satisfies anti-king
	var sol := solutions[0] as Array
	for i in 81:
		var val: int = sol[i]
		sol[i] = 0
		assert_true(c.is_valid(sol, i, val),
			"Solution violates anti-king constraint at cell %d" % i)
		sol[i] = val


func test_solver_respects_anti_knight_constraint() -> void:
	var c := AntiKnightConstraint.new()
	var grid: Array[int] = []
	grid.resize(81)
	grid.fill(0)
	var solutions := SudokuSolver.solve_brute_force(grid, 1, [c])
	assert_eq(solutions.size(), 1, "Exactly one anti-knight solution must be found")
	var sol := solutions[0] as Array
	for i in 81:
		var val: int = sol[i]
		sol[i] = 0
		assert_true(c.is_valid(sol, i, val),
			"Solution violates anti-knight constraint at cell %d" % i)
		sol[i] = val


# ---------------------------------------------------------------------------
# SudokuLogic: constraint integration
# ---------------------------------------------------------------------------

func test_logic_get_constraint_errors_empty_when_no_constraints() -> void:
	var logic := SudokuLogic.new()
	logic.init_new_game(0, 42)
	assert_eq(logic.get_constraint_errors().size(), 0)


func test_logic_get_constraint_errors_detects_anti_king_conflict() -> void:
	var logic := SudokuLogic.new()
	logic.constraints = [AntiKingConstraint.new()]
	logic.init_new_game(0, 42)
	# Manually inject a conflict: set cell 0 and cell 10 (diagonal) to the same non-zero value
	# that differs from the puzzle clues (use 0 cells only)
	var idx_a := -1
	var idx_b := -1
	# Find two diagonal empty cells to inject a conflict
	for i in 81:
		if logic.puzzle[i] != 0:
			continue
		var row := i / 9
		var col := i % 9
		for dr in [-1, 1]:
			for dc in [-1, 1]:
				var nr := row + dr
				var nc := col + dc
				if nr < 0 or nr >= 9 or nc < 0 or nc >= 9:
					continue
				var j := nr * 9 + nc
				if logic.puzzle[j] != 0:
					continue
				idx_a = i
				idx_b = j
				break
			if idx_a >= 0:
				break
		if idx_a >= 0:
			break
	if idx_a < 0:
		# Could not find two diagonal empty cells — skip rather than fail
		pass_test()
		return
	# Place the same value in both diagonal cells
	logic.current_grid[idx_a] = 5
	logic.current_grid[idx_b] = 5
	var errors := logic.get_constraint_errors()
	assert_true(idx_a in errors, "Cell %d should be flagged as a constraint error" % idx_a)
	assert_true(idx_b in errors, "Cell %d should be flagged as a constraint error" % idx_b)
