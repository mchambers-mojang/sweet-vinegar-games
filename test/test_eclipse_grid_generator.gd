extends GutTest

## Unit tests for EclipseGridGenerator — determinism, correctness, all sizes, cancellation.

const EMPTY := 0
const PLUS  := 1
const MINUS := 2


# ---------------------------------------------------------------------------
# All four sizes
# ---------------------------------------------------------------------------

func test_generate_size_4() -> void:
	var result: Dictionary = EclipseGridGenerator.generate(4, 42)
	_assert_valid_result(result, 4)


func test_generate_size_6() -> void:
	var result: Dictionary = EclipseGridGenerator.generate(6, 100)
	_assert_valid_result(result, 6)


func test_generate_size_8() -> void:
	var result: Dictionary = EclipseGridGenerator.generate(8, 200)
	_assert_valid_result(result, 8)


func test_generate_size_10() -> void:
	var result: Dictionary = EclipseGridGenerator.generate(10, 300)
	_assert_valid_result(result, 10)


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------

func test_same_seed_produces_same_puzzle_size_4() -> void:
	var a: Dictionary = EclipseGridGenerator.generate(4, 999)
	var b: Dictionary = EclipseGridGenerator.generate(4, 999)
	assert_eq(a.get("givens", []), b.get("givens", []),
			"Same seed must produce identical givens")


func test_same_seed_produces_same_puzzle_size_6() -> void:
	var a: Dictionary = EclipseGridGenerator.generate(6, 777)
	var b: Dictionary = EclipseGridGenerator.generate(6, 777)
	assert_eq(a.get("givens", []), b.get("givens", []))


func test_different_seeds_usually_differ() -> void:
	var a: Dictionary = EclipseGridGenerator.generate(4, 1)
	var b: Dictionary = EclipseGridGenerator.generate(4, 2)
	assert_false(a.is_empty(), "Seed 1 must generate a puzzle")
	assert_false(b.is_empty(), "Seed 2 must generate a puzzle")
	var a_givens: Array = a.get("givens", [])
	var b_givens: Array = b.get("givens", [])
	assert_ne(a_givens, b_givens,
			"Different deterministic seeds must produce different regression fixtures")


# ---------------------------------------------------------------------------
# Rule correctness
# ---------------------------------------------------------------------------

func test_solution_validates() -> void:
	var result: Dictionary = EclipseGridGenerator.generate(4, 55)
	assert_false(result.is_empty())
	var size: int = result.get("size", 0)
	var solution: Array = result.get("solution", [])
	var sol: Array[int] = []
	sol.assign(solution)
	var hr: Dictionary = result.get("h_relations", {})
	var vr: Dictionary = result.get("v_relations", {})
	assert_true(EclipseGridSolver.validate(size, sol, hr, vr),
			"Generated solution must satisfy all rules")


func test_unique_solution() -> void:
	var result: Dictionary = EclipseGridGenerator.generate(4, 42)
	assert_false(result.is_empty())
	var size: int = result.get("size", 0)
	var givens: Array = result.get("givens", [])
	var gv: Array[int] = []
	gv.assign(givens)
	var hr: Dictionary = result.get("h_relations", {})
	var vr: Dictionary = result.get("v_relations", {})
	var count: int = EclipseGridSolver.count_solutions(size, gv, hr, vr, 2)
	assert_eq(count, 1, "Generated puzzle must have exactly one solution")


func test_no_line_uniqueness_rule() -> void:
	# Verify the solver accepts identical rows (no line-uniqueness rule)
	var cells: Array[int] = [PLUS, PLUS, MINUS, MINUS,
							 PLUS, PLUS, MINUS, MINUS,
							 MINUS, MINUS, PLUS, PLUS,
							 MINUS, MINUS, PLUS, PLUS]
	assert_true(EclipseGridSolver.validate(4, cells, {}, {}))


func test_relation_clues_present_in_some_puzzles() -> void:
	# Most puzzles will have at least some relation clues
	var found_rel := false
	for seed in [1, 2, 3, 4, 5]:
		var result: Dictionary = EclipseGridGenerator.generate(6, seed)
		if not result.is_empty():
			var hr: Dictionary = result.get("h_relations", {})
			var vr: Dictionary = result.get("v_relations", {})
			if hr.size() > 0 or vr.size() > 0:
				found_rel = true
				break
	assert_true(found_rel, "At least one puzzle across seeds 1–5 should have relation clues")


# ---------------------------------------------------------------------------
# Cancellation
# ---------------------------------------------------------------------------

func test_generate_returns_empty_when_cancelled_immediately() -> void:
	var result: Dictionary = EclipseGridGenerator.generate(4, 42,
			func() -> bool: return true)
	assert_true(result.is_empty(),
			"generate() must return {} when cancel_check fires immediately")


func test_generate_returns_empty_when_cancelled_after_first_poll() -> void:
	# Let the first loop-guard poll pass; cancel on subsequent polls
	var state := [0]
	var cancel := func() -> bool:
		state[0] += 1
		return state[0] > 1

	var result: Dictionary = EclipseGridGenerator.generate(4, 42, cancel)
	assert_true(result.is_empty(),
			"generate() must return {} when cancelled during processing")
	assert_gt(state[0], 1,
			"cancel_check must be invoked more than once (confirming it is polled inside the loop)")


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

func _assert_valid_result(result: Dictionary, expected_size: int) -> void:
	assert_false(result.is_empty(), "generate() must return a non-empty dict for size %d" % expected_size)
	assert_eq(result.get("size", 0), expected_size)

	var givens_arr: Array = result.get("givens", [])
	var solution_arr: Array = result.get("solution", [])
	assert_eq(givens_arr.size(), expected_size * expected_size,
			"givens must have size×size entries")
	assert_eq(solution_arr.size(), expected_size * expected_size,
			"solution must have size×size entries")

	var givens: Array[int] = []
	givens.assign(givens_arr)
	var solution: Array[int] = []
	solution.assign(solution_arr)

	var hr: Dictionary = result.get("h_relations", {})
	var vr: Dictionary = result.get("v_relations", {})

	# Solution validates
	assert_true(EclipseGridSolver.validate(expected_size, solution, hr, vr),
			"Solution must satisfy all Eclipse Grid rules")

	# Givens are a subset of the solution
	for i in givens.size():
		if givens[i] != EMPTY:
			assert_eq(givens[i], solution[i],
					"Given at index %d must match solution" % i)

	# Unique solution
	var count: int = EclipseGridSolver.count_solutions(expected_size, givens, hr, vr, 2)
	assert_eq(count, 1, "Puzzle must have exactly one solution")


# ---------------------------------------------------------------------------
# Difficulty rank enforcement (regression for unenforced max_rank)
# ---------------------------------------------------------------------------

func test_size_4_puzzle_max_rank_1() -> void:
	## 4×4 is labelled "Easy" — the generated puzzle must require exactly Rank-1 techniques.
	for seed in [1, 7, 42, 100]:
		var result: Dictionary = EclipseGridGenerator.generate(4, seed)
		if result.is_empty():
			continue
		var max_rank: int = result.get("max_rank", 0)
		assert_eq(max_rank, EclipseGridSolver.RANK_1,
			"4×4 puzzle (seed %d) must be exactly Rank 1; got %d" % [seed, max_rank])


func test_size_6_puzzle_max_rank_2() -> void:
	## 6×6 is labelled "Medium" — the generated puzzle must require exactly Rank-2 techniques.
	for seed in [1, 7, 42, 100]:
		var result: Dictionary = EclipseGridGenerator.generate(6, seed)
		if result.is_empty():
			continue
		var max_rank: int = result.get("max_rank", 0)
		assert_eq(max_rank, EclipseGridSolver.RANK_2,
			"6×6 puzzle (seed %d) must be exactly Rank 2; got %d" % [seed, max_rank])


# ---------------------------------------------------------------------------
# Cancellation in board construction (regression for unpolled _place_rows)
# ---------------------------------------------------------------------------

func test_board_construction_respects_cancellation() -> void:
	## cancel_check fires on the very first poll inside generate() — the outer attempt
	## loop guard — so {} is returned before any work starts.  A separate state that
	## cancels on the second poll reaches _build_complete_board and exercises the
	## cancel_check path inside _place_rows.
	var state2 := [0]
	var cancel2 := func() -> bool:
		state2[0] += 1
		return state2[0] >= 2
	var result2: Dictionary = EclipseGridGenerator.generate(6, 99, cancel2)
	assert_true(result2.is_empty(),
		"generate() must return {} when cancelled during board construction")


# ---------------------------------------------------------------------------
# Relation minimization (regression for un-minimized relation clues)
# ---------------------------------------------------------------------------

func test_relation_clues_are_minimized() -> void:
	## After minimization, each remaining relation clue must be necessary:
	## removing any one of them must make the puzzle unsolvable by the human solver.
	var result: Dictionary = EclipseGridGenerator.generate(4, 42)
	if result.is_empty():
		return
	var size: int = result["size"]
	var givens: Array[int] = []
	givens.assign(result["givens"])
	var hr: Dictionary = result["h_relations"].duplicate()
	var vr: Dictionary = result["v_relations"].duplicate()
	for key in hr.keys():
		var saved: int = hr[key]
		hr.erase(key)
		var a: EclipseGridSolver.Analysis = EclipseGridSolver.analyze(size, givens, hr, vr)
		assert_false(a.is_unique,
			"h_relation %s must be necessary after minimization" % str(key))
		hr[key] = saved
	for key in vr.keys():
		var saved: int = vr[key]
		vr.erase(key)
		var a: EclipseGridSolver.Analysis = EclipseGridSolver.analyze(size, givens, hr, vr)
		assert_false(a.is_unique,
			"v_relation %s must be necessary after minimization" % str(key))
		vr[key] = saved


# ---------------------------------------------------------------------------
# is_unique requirement (regression for missing analysis.is_unique check)
# ---------------------------------------------------------------------------

func test_generated_puzzle_is_human_solver_unique() -> void:
	## The generator must require analysis.is_unique=true before accepting a puzzle.
	## Verify that every accepted puzzle can be uniquely completed by the human solver,
	## not merely by exhaustive search.
	for seed in [1, 7, 42, 100]:
		var result: Dictionary = EclipseGridGenerator.generate(4, seed)
		if result.is_empty():
			continue
		var givens: Array[int] = []
		givens.assign(result["givens"])
		var hr: Dictionary = result.get("h_relations", {})
		var vr: Dictionary = result.get("v_relations", {})
		var analysis: EclipseGridSolver.Analysis = EclipseGridSolver.analyze(
			result["size"], givens, hr, vr)
		assert_true(analysis.is_unique,
			"Generated 4×4 puzzle (seed %d) must be uniquely solvable by the human solver" % seed)
