extends GutTest

## Unit tests for NumberPathSolver

func _make_checkpoints(cells: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(cells.size()):
		result.append({"x": cells[i][0], "y": cells[i][1], "n": i + 1})
	return result


func test_solve_simple_1x4() -> void:
	# 1×4 straight path, checkpoints at both ends
	var cps := _make_checkpoints([[0, 0], [3, 0]])
	var result := NumberPathSolver.solve(4, 1, cps, [])
	assert_true(result.get("solved", false))
	assert_eq(result.get("path", []).size(), 4)


func test_solve_2x2() -> void:
	# 2×2 with checkpoints at (0,0) start and (1,0) end.
	# Only path: (0,0)→(0,1)→(1,1)→(1,0) — ends at (1,0) ✓
	var cps := _make_checkpoints([[0, 0], [1, 0]])
	var result := NumberPathSolver.solve(2, 2, cps, [])
	assert_true(result.get("solved", false))
	var path: Array = result.get("path", [])
	assert_eq(path.size(), 4)
	assert_eq(path[0], Vector2i(0, 0))
	assert_eq(path[path.size() - 1], Vector2i(1, 0))


func test_count_solutions_unique_1x4() -> void:
	var cps := _make_checkpoints([[0, 0], [3, 0]])
	var count := NumberPathSolver.count_solutions(4, 1, cps, [], 2)
	assert_eq(count, 1)


func test_count_solutions_zero_when_no_hamiltonian_to_endpoint() -> void:
	# 2×2 grid with checkpoints at diagonally opposite corners (0,0) and (1,1).
	# No Hamiltonian path from (0,0) covering all 4 cells ends at (1,1) — they
	# both end at the other corner. So count should be 0.
	var cps := _make_checkpoints([[0, 0], [1, 1]])
	var count := NumberPathSolver.count_solutions(2, 2, cps, [], 2)
	assert_eq(count, 0)


func test_count_solutions_unique_with_middle_checkpoint() -> void:
	# 2×2 with checkpoints at (0,0) start, (1,0) middle, (0,1) end.
	# Only one path can satisfy: (0,0)→(1,0)→(1,1)→(0,1)
	var cps := _make_checkpoints([[0, 0], [1, 0], [0, 1]])
	var count := NumberPathSolver.count_solutions(2, 2, cps, [], 2)
	assert_eq(count, 1)


func test_count_solutions_cancelled() -> void:
	var cps := _make_checkpoints([[0, 0], [3, 3]])
	var count := NumberPathSolver.count_solutions(4, 4, cps, [], 2,
			func() -> bool: return true)  # immediately cancel
	assert_eq(count, -1)


func test_solver_steps_have_rank() -> void:
	var cps := _make_checkpoints([[0, 0], [3, 0]])
	var result := NumberPathSolver.solve(4, 1, cps, [])
	if result.get("solved", false):
		var steps: Array = result.get("steps", [])
		for step in steps:
			assert_true(step.has("rank"))
			assert_true(int(step["rank"]) >= 1)


func test_barrier_blocks_path() -> void:
	# 1×4 with barrier on right edge of (1,0) — forces detour (impossible in 1×4)
	var cps := _make_checkpoints([[0, 0], [3, 0]])
	var barriers: Array[Dictionary] = [{"r": 0, "c": 1, "dir": NumberPathLogic.DIR_RIGHT}]
	var count := NumberPathSolver.count_solutions(4, 1, cps, barriers, 2)
	assert_eq(count, 0)


func test_barrier_on_grid_with_path_around() -> void:
	# 2×2 with barrier between (0,0) and (1,0), only path is (0,0)→(0,1)→(1,1)→(1,0)
	var cps := _make_checkpoints([[0, 0], [1, 0]])
	var barriers: Array[Dictionary] = [{"r": 0, "c": 0, "dir": NumberPathLogic.DIR_RIGHT}]
	var count := NumberPathSolver.count_solutions(2, 2, cps, barriers, 2)
	assert_eq(count, 1)


func test_solve_returns_path_starting_at_checkpoint_1() -> void:
	var cps := _make_checkpoints([[2, 2], [0, 0]])
	var result := NumberPathSolver.solve(3, 3, cps, [])
	if result.get("solved", false):
		var path: Array = result.get("path", [])
		assert_false(path.is_empty())
		assert_eq(path[0], Vector2i(2, 2))


# --- Regression: rank-4 can_complete_from off-by-one (fix 1) ---

func test_rank4_global_deduction_succeeds_on_3x3() -> void:
	# 3×3 grid, checkpoints at (0,0) start and (0,1) last.
	# From (0,0), candidate (0,1) is the last checkpoint; with 8 cells still
	# remaining it is too early to visit — rank-4 rejects it and deduces (1,0).
	# This directly exercises the can_complete_from last-CP-early guard.
	var cps := _make_checkpoints([[0, 0], [0, 1]])
	var result := NumberPathSolver.solve(3, 3, cps, [])
	assert_true(result.get("max_rank", 0) >= NumberPathSolver.RANK_GLOBAL,
		"Rank-4 must fire to eliminate the too-early last-checkpoint candidate")
	assert_true(result.get("path", []).size() >= 2,
		"Solver must extend the path at least one step past CP1")


func test_can_complete_from_accepts_fully_connected_state() -> void:
	# Verify that count_solutions works correctly for a puzzle where rank-4
	# deduction is required (previously the off-by-one caused false zero counts).
	var cps := _make_checkpoints([[0, 0], [2, 2]])
	var count := NumberPathSolver.count_solutions(3, 3, cps, [], 2)
	assert_true(count >= 1, "3×3 with diagonal checkpoints must have at least one solution")
