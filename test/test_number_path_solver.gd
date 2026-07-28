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
