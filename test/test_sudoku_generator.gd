extends GutTest

## Unit tests for SudokuGenerator — puzzle generation, difficulty, solution uniqueness.


func test_generate_returns_puzzle_and_solution() -> void:
	var gen := SudokuGenerator.new()
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 42)
	assert_true(result.has("puzzle"))
	assert_true(result.has("solution"))
	assert_eq(result["puzzle"].size(), 81)
	assert_eq(result["solution"].size(), 81)


func test_generate_puzzle_has_zeros() -> void:
	var gen := SudokuGenerator.new()
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 42)
	var puzzle: Array = result["puzzle"]
	var zeros := 0
	for v in puzzle:
		if v == 0:
			zeros += 1
	assert_true(zeros > 0, "Puzzle should have empty cells")


func test_generate_solution_is_complete() -> void:
	var gen := SudokuGenerator.new()
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 42)
	var solution: Array = result["solution"]
	for i in 81:
		assert_true(solution[i] >= 1 and solution[i] <= 9,
			"Solution cell %d has invalid value %d" % [i, solution[i]])


func test_generate_solution_is_valid() -> void:
	var gen := SudokuGenerator.new()
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.MEDIUM, 123)
	var solution: Array[int] = []
	solution.assign(result["solution"])
	for i in 81:
		var val: int = solution[i]
		solution[i] = 0
		assert_true(SudokuSolver.is_valid_placement(solution, i, val),
			"Solution conflict at cell %d" % i)
		solution[i] = val


func test_generate_puzzle_matches_solution() -> void:
	var gen := SudokuGenerator.new()
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 99)
	var puzzle: Array = result["puzzle"]
	var solution: Array = result["solution"]
	for i in 81:
		if puzzle[i] != 0:
			assert_eq(puzzle[i], solution[i],
				"Clue at %d doesn't match solution" % i)


func test_generate_same_seed_same_result() -> void:
	var gen := SudokuGenerator.new()
	var r1: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 777)
	var r2: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 777)
	assert_eq(r1["puzzle"], r2["puzzle"])
	assert_eq(r1["solution"], r2["solution"])


func test_generate_different_seeds_different_puzzles() -> void:
	var gen := SudokuGenerator.new()
	var r1: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 1)
	var r2: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 2)
	assert_ne(r1["puzzle"], r2["puzzle"])


func test_generate_easy_has_more_clues_than_hard() -> void:
	var gen := SudokuGenerator.new()
	var easy: Dictionary = gen.generate(SudokuSolver.Difficulty.EASY, 50)
	var hard: Dictionary = gen.generate(SudokuSolver.Difficulty.HARD, 50)
	var easy_clues := 0
	var hard_clues := 0
	for v in easy["puzzle"]:
		if v != 0:
			easy_clues += 1
	for v in hard["puzzle"]:
		if v != 0:
			hard_clues += 1
	assert_true(easy_clues > hard_clues,
		"Easy (%d clues) should have more clues than Hard (%d)" % [easy_clues, hard_clues])


func test_generate_puzzle_has_unique_solution() -> void:
	var gen := SudokuGenerator.new()
	var result: Dictionary = gen.generate(SudokuSolver.Difficulty.HARD, 42)
	var puzzle: Array[int] = []
	puzzle.assign(result["puzzle"])
	var solutions: Array[Array] = SudokuSolver.solve_brute_force(puzzle, 2)
	assert_eq(solutions.size(), 1, "Puzzle should have exactly one solution")
