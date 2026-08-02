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


func test_count_solutions_immediate_cancel_small_grid() -> void:
	# Even a tiny grid must return -1 when cancellation is set before the first
	# DFS call; previously the periodic check fired only every 500 calls so a
	# small search could complete and return a real count instead of -1.
	var cps := _make_checkpoints([[0, 0], [3, 0]])
	var count := NumberPathSolver.count_solutions(4, 1, cps, [], 2,
			func() -> bool: return true)  # immediately cancel
	assert_eq(count, -1, "Immediate cancellation must return -1 on small grids")


# --- Regression: rank-4 can_complete_from off-by-one (fix 1) ---

func test_rank4_global_deduction_succeeds_on_3x3() -> void:
	# 3×3 with checkpoints at (0,0) start and (1,1) last, and a DIR_DOWN
	# barrier at {r:0,c:0} that blocks (0,0)↔(0,1).
	# Rank-1 forces the first step to (1,0); then rank-4 fires three times
	# by rejecting (1,1) as a too-early last-checkpoint visit:
	#   • from (1,0): deduces (2,0)
	#   • from (2,1): deduces (2,2)
	#   • from (1,2): deduces (0,2)
	# The unique complete solution is:
	#   (0,0)→(1,0)→(2,0)→(2,1)→(2,2)→(1,2)→(0,2)→(0,1)→(1,1)
	var cps := _make_checkpoints([[0, 0], [1, 1]])
	var barriers: Array[Dictionary] = [{"r": 0, "c": 0, "dir": NumberPathLogic.DIR_DOWN}]
	var result := NumberPathSolver.solve(3, 3, cps, barriers)
	assert_true(result.get("solved", false), "Solver must complete the 3×3 puzzle")
	assert_true(result.get("max_rank", 0) >= NumberPathSolver.RANK_GLOBAL,
		"Rank-4 must fire to reject the too-early last-checkpoint candidate")
	var path: Array = result.get("path", [])
	var expected: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1),
		Vector2i(2, 2), Vector2i(1, 2), Vector2i(0, 2), Vector2i(0, 1),
		Vector2i(1, 1),
	]
	assert_eq(path.size(), 9, "Solution must cover all 9 cells")
	for i in range(expected.size()):
		assert_eq(path[i], expected[i], "Path cell %d must match expected" % i)


func test_can_complete_from_accepts_fully_connected_state() -> void:
	# Verify that count_solutions works correctly for a puzzle where rank-4
	# deduction is required (previously the off-by-one caused false zero counts).
	var cps := _make_checkpoints([[0, 0], [2, 2]])
	var count := NumberPathSolver.count_solutions(3, 3, cps, [], 2)
	assert_true(count >= 1, "3×3 with diagonal checkpoints must have at least one solution")


# --- Regression: Rank-1 checkpoint-approach deduction was dead code (fix) ---
# Previously `free_neighbors(next_cp)` excluded visited cells, so head (always
# visited) could never equal reachable[0] and the deduction never fired.
# The fix checks adjacency separately and temporarily blocks next_cp in the
# BFS so we know whether head is truly the sole approach.

func test_rank1_checkpoint_approach_fires() -> void:
	# 3×2 grid (width=3, height=2):
	#   (0,0)[CP1]  (1,0)[CP2]  (2,0)
	#   (0,1)       (1,1)       (2,1)[CP3]
	# Barrier DIR_RIGHT at {r:1, c:0} blocks (0,1)↔(1,1).
	# From the start head=(0,0):
	#   • candidates = [(1,0), (0,1)]  → size=2, "single free neighbor" does NOT fire.
	#   • next_cp = (1,0), directly adjacent to head  ✓
	#   • free_neighbors(1,0) = [(2,0), (1,1)]
	#   • with (1,0) blocked in BFS: from (0,0) → (0,1) → barrier, stuck.
	#     Neither (2,0) nor (1,1) is reachable without going through (1,0).
	#   → "next checkpoint only approach" must fire and deduce move to (1,0).
	var cps := _make_checkpoints([[0, 0], [1, 0], [2, 1]])
	var barriers: Array[Dictionary] = [{"r": 1, "c": 0, "dir": NumberPathLogic.DIR_RIGHT}]
	var result := NumberPathSolver.solve(3, 2, cps, barriers)
	var steps: Array = result.get("steps", [])
	var found := false
	for step in steps:
		if step.get("reason", "") == "next checkpoint only approach":
			found = true
			assert_eq(step.get("result", Vector2i(-1, -1)), Vector2i(1, 0),
					"CP-approach deduction must force move to next checkpoint (1,0)")
			break
	assert_true(found, "Rank-1 'next checkpoint only approach' deduction must fire")
