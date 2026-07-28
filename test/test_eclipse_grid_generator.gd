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
	# It is extremely unlikely that two different seeds produce the same puzzle
	var a_givens: Array = a.get("givens", [])
	var b_givens: Array = b.get("givens", [])
	var same: bool = a_givens == b_givens
	# We just log — not assert — since technically it's possible but extremely rare
	if same:
		push_warning("test_different_seeds_usually_differ: seeds 1 and 2 produced the same puzzle (extremely unlikely)")


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
