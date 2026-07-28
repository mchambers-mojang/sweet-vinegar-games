extends GutTest

## Unit tests for NumberPathGenerator

func test_generate_easy_deterministic() -> void:
	var r1 := NumberPathGenerator.generate(NumberPathLogic.TIER_EASY, 42)
	var r2 := NumberPathGenerator.generate(NumberPathLogic.TIER_EASY, 42)
	assert_false(r1.is_empty(), "Easy generation should succeed")
	if not r1.is_empty() and not r2.is_empty():
		assert_eq(r1.get("width"), r2.get("width"))
		assert_eq(r1.get("checkpoints"), r2.get("checkpoints"))
		assert_eq(r1.get("solution_path"), r2.get("solution_path"))
		assert_eq(r1.get("barriers"), r2.get("barriers"))


func test_generate_easy_board_size() -> void:
	var result := NumberPathGenerator.generate(NumberPathLogic.TIER_EASY, 1)
	if not result.is_empty():
		assert_eq(result.get("width"), 5)
		assert_eq(result.get("height"), 5)


func test_generate_medium_board_size() -> void:
	var result := NumberPathGenerator.generate(NumberPathLogic.TIER_MEDIUM, 1)
	if not result.is_empty():
		assert_eq(result.get("width"), 6)
		assert_eq(result.get("height"), 6)


func test_generate_hard_board_size() -> void:
	var result := NumberPathGenerator.generate(NumberPathLogic.TIER_HARD, 1)
	if not result.is_empty():
		assert_eq(result.get("width"), 7)
		assert_eq(result.get("height"), 7)


func test_generate_expert_board_size() -> void:
	var result := NumberPathGenerator.generate(NumberPathLogic.TIER_EXPERT, 1)
	if not result.is_empty():
		assert_eq(result.get("width"), 8)
		assert_eq(result.get("height"), 8)


func test_generate_easy_has_no_barriers() -> void:
	var result := NumberPathGenerator.generate(NumberPathLogic.TIER_EASY, 1)
	if not result.is_empty():
		var barriers: Array = result.get("barriers", [])
		assert_eq(barriers.size(), 0)


func test_generate_medium_has_no_barriers() -> void:
	var result := NumberPathGenerator.generate(NumberPathLogic.TIER_MEDIUM, 1)
	if not result.is_empty():
		var barriers: Array = result.get("barriers", [])
		assert_eq(barriers.size(), 0)


func test_generate_solution_path_covers_all_cells() -> void:
	var result := NumberPathGenerator.generate(NumberPathLogic.TIER_EASY, 5)
	if not result.is_empty():
		var w: int = result.get("width", 0)
		var h: int = result.get("height", 0)
		var path: Array = result.get("solution_path", [])
		assert_eq(path.size(), w * h)


func test_generate_solution_path_starts_at_checkpoint_1() -> void:
	var result := NumberPathGenerator.generate(NumberPathLogic.TIER_EASY, 7)
	if not result.is_empty():
		var cps: Array = result.get("checkpoints", [])
		var path: Array = result.get("solution_path", [])
		if not cps.is_empty() and not path.is_empty():
			var cp1: Dictionary = cps[0]
			var p0: Dictionary = path[0]
			assert_eq(int(p0.get("x")), int(cp1.get("x")))
			assert_eq(int(p0.get("y")), int(cp1.get("y")))


func test_generate_solution_path_ends_at_last_checkpoint() -> void:
	var result := NumberPathGenerator.generate(NumberPathLogic.TIER_EASY, 9)
	if not result.is_empty():
		var cps: Array = result.get("checkpoints", [])
		var path: Array = result.get("solution_path", [])
		if not cps.is_empty() and not path.is_empty():
			var last_cp: Dictionary = cps[cps.size() - 1]
			var last_p: Dictionary = path[path.size() - 1]
			assert_eq(int(last_p.get("x")), int(last_cp.get("x")))
			assert_eq(int(last_p.get("y")), int(last_cp.get("y")))


func test_generate_checkpoints_in_order_along_path() -> void:
	var result := NumberPathGenerator.generate(NumberPathLogic.TIER_EASY, 3)
	if not result.is_empty():
		var cps: Array = result.get("checkpoints", [])
		var path: Array = result.get("solution_path", [])
		if cps.is_empty() or path.is_empty():
			return
		# Find each checkpoint's index in path and verify they are increasing
		var last_idx := -1
		for cp in cps:
			var cp_cell := Vector2i(int(cp.get("x")), int(cp.get("y")))
			var found := false
			for i in range(path.size()):
				var p: Dictionary = path[i]
				if int(p.get("x")) == cp_cell.x and int(p.get("y")) == cp_cell.y:
					assert_true(i > last_idx, "Checkpoints must appear in order along path")
					last_idx = i
					found = true
					break
			assert_true(found, "Checkpoint must be in path")


func test_generate_cancelled() -> void:
	var result := NumberPathGenerator.generate(
			NumberPathLogic.TIER_EASY, 1,
			func() -> bool: return true)  # immediate cancel
	assert_true(result.is_empty())


func test_generate_unique_solution() -> void:
	# Verify the generated puzzle has exactly one solution
	var result := NumberPathGenerator.generate(NumberPathLogic.TIER_EASY, 11)
	if not result.is_empty():
		var w: int = result.get("width", 5)
		var h: int = result.get("height", 5)
		var cps_raw: Array = result.get("checkpoints", [])
		var bs_raw: Array = result.get("barriers", [])
		var cps: Array[Dictionary] = []
		for cp in cps_raw:
			if cp is Dictionary:
				cps.append(cp)
		var bs: Array[Dictionary] = []
		for b in bs_raw:
			if b is Dictionary:
				bs.append(b)
		var count := NumberPathSolver.count_solutions(w, h, cps, bs, 2)
		assert_eq(count, 1, "Generated puzzle must have exactly one solution")
