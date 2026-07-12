class_name KillerSudokuGenerator
extends RefCounted

## Killer generation can take around 1-3 seconds. Callers should run this off the
## main thread so UI can show a loading spinner while the puzzle is prepared.

const MAX_ATTEMPTS := 16
const KillerCagePartitionerScript := preload("res://scripts/sudoku/killer_cage_partitioner.gd")
const KillerConstraintScript := preload("res://scripts/sudoku/killer_constraint.gd")
const KillerSudokuSolverScript := preload("res://scripts/sudoku/killer_sudoku_solver.gd")


func generate(difficulty: int, seed: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()

	for _attempt in MAX_ATTEMPTS:
		var full_grid := SudokuGenerator.new()._generate_full_grid(rng)
		var cages := KillerCagePartitionerScript.partition_with_rng(full_grid, difficulty, rng)
		if cages.is_empty():
			continue

		var constraint = KillerConstraintScript.new(cages)
		var puzzle := _create_puzzle_with_minimal_givens(full_grid, constraint, difficulty, rng)
		if puzzle.is_empty():
			continue

		var solver = KillerSudokuSolverScript.new(constraint)
		solver.analyze(puzzle)
		if solver.is_unique and solver.solve_logic(puzzle.duplicate()):
			return {
				"puzzle": puzzle,
				"solution": full_grid,
				"cages": constraint.get_cages(),
				"difficulty": solver.difficulty,
			}
	return {}


func _create_puzzle_with_minimal_givens(full_grid: Array[int], constraint, difficulty: int, rng: RandomNumberGenerator) -> Array[int]:
	var pure_killer: Array[int] = []
	pure_killer.resize(81)
	pure_killer.fill(0)
	if _is_acceptable_puzzle(pure_killer, constraint):
		return pure_killer

	var seeded_puzzle := SudokuGenerator.new()._remove_cells(full_grid, difficulty, rng, [constraint])
	if seeded_puzzle.is_empty():
		return []
	return _minimize_givens(seeded_puzzle, constraint, rng)


func _minimize_from_full_grid(full_grid: Array[int], constraint, rng: RandomNumberGenerator) -> Array[int]:
	var puzzle: Array[int] = []
	puzzle.resize(81)
	puzzle.fill(0)

	if _is_acceptable_puzzle(puzzle, constraint):
		return puzzle

	puzzle.assign(full_grid.duplicate())
	return _minimize_givens(puzzle, constraint, rng)


func _minimize_givens(puzzle: Array[int], constraint, rng: RandomNumberGenerator) -> Array[int]:
	var minimized: Array[int] = []
	minimized.assign(puzzle.duplicate())
	var indices := range(81)
	_shuffle_array(indices, rng)
	var removed_any := true
	while removed_any:
		removed_any = false
		for index in indices:
			if minimized[index] == 0:
				continue
			var backup := int(minimized[index])
			minimized[index] = 0
			if not _is_acceptable_puzzle(minimized, constraint):
				minimized[index] = backup
				continue
			removed_any = true
	return minimized


func _is_acceptable_puzzle(puzzle: Array[int], constraint) -> bool:
	var logic_solver = KillerSudokuSolverScript.new(constraint)
	if not logic_solver.solve_logic(puzzle.duplicate()):
		return false
	var solutions := SudokuSolver.solve_brute_force(puzzle, 2, [constraint])
	return solutions.size() == 1


func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
