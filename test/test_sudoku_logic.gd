extends GutTest

## Unit tests for SudokuLogic — pure game-rules module.
## No autoloads, no scene tree, no side effects required.

const LogicScript := preload("res://scripts/sudoku/sudoku_logic.gd")

# A known valid 9x9 Sudoku puzzle and solution for deterministic tests.
const TEST_PUZZLE: Array[int] = [
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
const TEST_SOLUTION: Array[int] = [
	5, 3, 4, 6, 7, 8, 9, 1, 2,
	6, 7, 2, 1, 9, 5, 3, 4, 8,
	1, 9, 8, 3, 4, 2, 5, 6, 7,
	8, 5, 9, 7, 6, 1, 4, 2, 3,
	4, 2, 6, 8, 5, 3, 7, 9, 1,
	7, 1, 3, 9, 2, 4, 8, 5, 6,
	9, 6, 1, 5, 3, 7, 2, 8, 4,
	2, 8, 7, 4, 1, 9, 6, 3, 5,
	3, 4, 5, 2, 8, 6, 1, 7, 9,
]

var logic: SudokuLogic


func before_each() -> void:
	logic = SudokuLogic.new(false, true)  # non-strict, auto-remove enabled
	logic._setup_from_arrays(0, TEST_PUZZLE, TEST_SOLUTION)


# ---------------------------------------------------------------------------
# Helper: fill all cells except the given one with correct answers
# ---------------------------------------------------------------------------

func _fill_all_except(skip_index: int) -> void:
	for i in 81:
		if i != skip_index and logic.puzzle[i] == 0:
			logic.current_grid[i] = logic.solution[i]


# ---------------------------------------------------------------------------
# 1. init_new_game initialises state correctly
# ---------------------------------------------------------------------------

func test_new_game_initializes_state() -> void:
	logic.init_new_game(SudokuSolver.Difficulty.EASY, 42)
	assert_eq(logic.puzzle.size(), 81, "puzzle should have 81 cells")
	assert_eq(logic.solution.size(), 81, "solution should have 81 cells")
	assert_eq(logic.current_grid.size(), 81, "current_grid should have 81 cells")
	assert_eq(logic.pencil_marks.size(), 81, "pencil_marks should have 81 entries")
	assert_eq(logic.strikes, 0)
	assert_false(logic.is_failed)
	assert_false(logic.is_completed)
	assert_eq(logic.hints_used, 0)
	assert_true(logic.undo_stack.is_empty())
	assert_true(logic.redo_stack.is_empty())


# ---------------------------------------------------------------------------
# 2. Correct placement (non-strict): valid=true, placed=true, no strike
# ---------------------------------------------------------------------------

func test_place_correct_number() -> void:
	var empty_index := 2  # puzzle[2] == 0, solution[2] == 4
	var result := logic.place_number(empty_index, 4)
	assert_true(result.valid, "Correct placement should be valid")
	assert_true(result.placed, "Correct placement should be placed")
	assert_eq(result.cell_index, empty_index)
	assert_eq(result.number, 4)
	assert_eq(result.strikes_added, 0)
	assert_false(result.game_failed)
	assert_eq(logic.current_grid[empty_index], 4)
	assert_eq(logic.strikes, 0)


# ---------------------------------------------------------------------------
# 3. Wrong placement in strict mode: adds strike, does not update grid
# ---------------------------------------------------------------------------

func test_place_incorrect_number_strict() -> void:
	logic.strict_mode = true
	var empty_index := 2  # solution[2] == 4
	var result := logic.place_number(empty_index, 9)  # Wrong: 9 != 4
	assert_true(result.valid, "Attempt on an editable cell is valid")
	assert_false(result.placed, "Wrong number in strict mode should NOT be placed")
	assert_eq(result.strikes_added, 1)
	assert_false(result.game_failed)
	assert_eq(logic.strikes, 1)
	assert_eq(logic.current_grid[empty_index], 0, "Grid must not change on wrong strict placement")


# ---------------------------------------------------------------------------
# 4. Fourth strike (4th wrong answer) causes game_failed
# ---------------------------------------------------------------------------

func test_place_number_game_over() -> void:
	logic.strict_mode = true
	logic.strikes = 3  # Already at 3
	var empty_index := 2  # solution[2] == 4
	var result := logic.place_number(empty_index, 9)
	assert_eq(result.strikes_added, 1)
	assert_true(result.game_failed, "4th strike should trigger game_failed")
	assert_true(logic.is_failed)


# ---------------------------------------------------------------------------
# 5. Last correct placement triggers game_won
# ---------------------------------------------------------------------------

func test_place_number_wins_game() -> void:
	# Find first empty cell
	var last_empty := -1
	for i in 81:
		if logic.puzzle[i] == 0:
			last_empty = i
			break
	_fill_all_except(last_empty)
	var result := logic.place_number(last_empty, logic.solution[last_empty])
	assert_true(result.game_won, "Filling the last cell correctly should win the game")
	assert_true(logic.is_completed)


# ---------------------------------------------------------------------------
# 6. Pencil mark toggle: adds then removes
# ---------------------------------------------------------------------------

func test_pencil_mark_toggle() -> void:
	var empty_index := 2
	var pr1 := logic.toggle_pencil_mark(empty_index, 4)
	assert_true(pr1.valid)
	assert_true(pr1.added, "First toggle should add the mark")
	assert_true(4 in logic.pencil_marks[empty_index])

	var pr2 := logic.toggle_pencil_mark(empty_index, 4)
	assert_true(pr2.valid)
	assert_false(pr2.added, "Second toggle should remove the mark")
	assert_false(4 in logic.pencil_marks[empty_index])


# ---------------------------------------------------------------------------
# 7. Auto-remove pencil marks after placement
# ---------------------------------------------------------------------------

func test_auto_remove_pencil_marks() -> void:
	# Cell 2 is (row=0, col=2); set pencil mark 4 in same row (col 3, index 3) and
	# same box (row=1 col=0, index=9) — these should be cleared when we place 4 at index 2.
	logic.pencil_marks[3] = [4, 5]   # row-mate
	logic.pencil_marks[9] = [4, 7]   # box-mate (row=1, col=0 → same top-left box as cell 2)
	logic.auto_remove_pencil_marks = true

	var result := logic.place_number(2, 4)
	assert_true(result.placed)
	assert_true(result.pencil_marks_removed.size() > 0, "Should report removed marks")

	# Mark 4 should be gone from those cells
	assert_false(4 in logic.pencil_marks[3], "Row-mate pencil mark 4 should be removed")
	assert_false(4 in logic.pencil_marks[9], "Box-mate pencil mark 4 should be removed")
	# Other marks should be intact
	assert_true(5 in logic.pencil_marks[3], "Other marks in row-mate should survive")
	assert_true(7 in logic.pencil_marks[9], "Other marks in box-mate should survive")


# ---------------------------------------------------------------------------
# 8. Hint places correct number and increments hints_used
# ---------------------------------------------------------------------------

func test_hint_places_correct_number() -> void:
	var empty_index := 2  # solution[2] == 4
	var result := logic.use_hint(empty_index)
	assert_true(result.success)
	assert_eq(result.cell_index, empty_index)
	assert_eq(result.number, logic.solution[empty_index])
	assert_eq(logic.current_grid[empty_index], logic.solution[empty_index])
	assert_eq(logic.hints_used, 1)


# ---------------------------------------------------------------------------
# 9. Erase clears number and returns old value
# ---------------------------------------------------------------------------

func test_erase_cell() -> void:
	var empty_index := 2
	logic.current_grid[empty_index] = 4  # Place without undo
	logic.pencil_marks[empty_index] = [1, 2]
	var result := logic.erase_cell(empty_index)
	assert_true(result.success)
	assert_eq(result.old_number, 4)
	assert_eq(result.old_pencil_marks, [1, 2])
	assert_eq(logic.current_grid[empty_index], 0)
	assert_true((logic.pencil_marks[empty_index] as Array).is_empty())


# ---------------------------------------------------------------------------
# 10. Undo reverts a placement and restores previous state
# ---------------------------------------------------------------------------

func test_undo_place() -> void:
	var empty_index := 2
	logic.pencil_marks[empty_index] = [3, 4]
	logic.place_number(empty_index, 4)
	assert_eq(logic.current_grid[empty_index], 4)
	assert_true((logic.pencil_marks[empty_index] as Array).is_empty())

	var undo_result := logic.undo()
	assert_true(undo_result.success)
	assert_eq(undo_result.cell_index, empty_index)
	assert_eq(undo_result.restored_value, 0, "Value should revert to 0")
	assert_eq(undo_result.restored_pencil_marks, [3, 4], "Pencil marks should be restored")
	assert_eq(logic.current_grid[empty_index], 0)


# ---------------------------------------------------------------------------
# 11. Redo re-applies an undone action
# ---------------------------------------------------------------------------

func test_redo_after_undo() -> void:
	var empty_index := 2
	logic.place_number(empty_index, 4)
	logic.undo()
	assert_eq(logic.current_grid[empty_index], 0)

	var redo_result := logic.redo()
	assert_true(redo_result.success)
	assert_eq(redo_result.restored_value, 4, "Redo should restore the placed number")
	assert_eq(logic.current_grid[empty_index], 4)


# ---------------------------------------------------------------------------
# 12. Serialize/deserialize round-trip preserves all state
# ---------------------------------------------------------------------------

func test_serialize_deserialize_roundtrip() -> void:
	# Make some moves
	logic.place_number(2, 4)
	logic.pencil_marks[5] = [1, 2, 3]
	logic.colors[10] = Color(1.0, 0.5, 0.0)
	logic.strikes = 2

	var saved: Dictionary = logic.serialize()

	var fresh := SudokuLogic.new(false, true)
	fresh.init_from_save(saved)

	assert_eq(fresh.current_grid[2], logic.current_grid[2])
	assert_eq(fresh.puzzle, logic.puzzle)
	assert_eq(fresh.solution, logic.solution)
	assert_eq(fresh.strikes, logic.strikes)
	assert_eq(fresh.hints_used, logic.hints_used)
	assert_eq(fresh.difficulty, logic.difficulty)
	assert_eq(fresh.pencil_marks[5], logic.pencil_marks[5])
	# Color round-trips through HTML string
	var saved_color: Color = fresh.colors[10]
	assert_almost_eq(saved_color.r, logic.colors[10].r, 0.01)
	assert_almost_eq(saved_color.g, logic.colors[10].g, 0.01)
	assert_almost_eq(saved_color.b, logic.colors[10].b, 0.01)


# ---------------------------------------------------------------------------
# 13. Unit completion detection
# ---------------------------------------------------------------------------

func test_unit_completion_detection() -> void:
	# Fill row 0 with correct answers, leaving index 2 empty (puzzle[2]==0, sol[2]==4)
	for c in 9:
		if c != 2:
			logic.current_grid[c] = logic.solution[c]

	var result := logic.place_number(2, logic.solution[2])
	assert_true(result.placed)

	var row_completed := false
	for unit in result.units_completed:
		if unit["type"] == "row" and unit["unit_index"] == 0:
			row_completed = true
			break
	assert_true(row_completed, "Completing row 0 should be reported in units_completed")


# ---------------------------------------------------------------------------
# 14. can_undo / can_redo
# ---------------------------------------------------------------------------

func test_can_undo_and_redo() -> void:
	assert_false(logic.can_undo(), "No undo available before any action")
	assert_false(logic.can_redo(), "No redo available before any action")

	logic.place_number(2, 4)
	assert_true(logic.can_undo(), "Undo should be available after a placement")
	assert_false(logic.can_redo(), "No redo before any undo")

	logic.undo()
	assert_false(logic.can_undo(), "No undo after reverting the only action")
	assert_true(logic.can_redo(), "Redo should be available after undo")

	logic.redo()
	assert_true(logic.can_undo(), "Undo available after redo")
	assert_false(logic.can_redo(), "No redo after re-applying the only action")


# ---------------------------------------------------------------------------
# 15. count_number_placements
# ---------------------------------------------------------------------------

func test_count_number_placements() -> void:
	# Baseline includes given cells already in current_grid
	var initial_count := logic.count_number_placements(4)
	# Place a 4 in an empty cell (puzzle[2]==0, solution[2]==4)
	logic.place_number(2, 4)
	assert_eq(logic.count_number_placements(4), initial_count + 1,
		"Placing a 4 should increase the count by one")

	logic.erase_cell(2)
	assert_eq(logic.count_number_placements(4), initial_count,
		"Erasing the placed 4 should restore the original count")


# ---------------------------------------------------------------------------
# 16. pick_unsolved_cell
# ---------------------------------------------------------------------------

func test_pick_unsolved_cell_returns_unsolved() -> void:
	var index := logic.pick_unsolved_cell()
	assert_true(index >= 0 and index < 81, "Should return a valid cell index")
	assert_ne(logic.current_grid[index], logic.solution[index],
		"Returned cell must not yet match the solution")


func test_pick_unsolved_cell_returns_minus_one_when_complete() -> void:
	# Fill all cells with correct answers
	for i in 81:
		logic.current_grid[i] = logic.solution[i]
	var index := logic.pick_unsolved_cell()
	assert_eq(index, -1, "Should return -1 when the board is fully solved")


# ---------------------------------------------------------------------------
# 17. use_hint_auto — preferred cell used when unsolved
# ---------------------------------------------------------------------------

func test_use_hint_auto_prefers_selected_cell() -> void:
	var preferred := 2  # puzzle[2]==0, solution[2]==4 — unsolved editable cell
	var result := logic.use_hint_auto(preferred)
	assert_true(result.success, "Hint should succeed when a valid unsolved cell is preferred")
	assert_eq(result.cell_index, preferred, "Preferred unsolved cell should be chosen")
	assert_eq(result.number, logic.solution[preferred])


func test_use_hint_auto_falls_back_when_preferred_already_correct() -> void:
	# Make the preferred cell already correctly placed
	logic.current_grid[2] = logic.solution[2]
	var result := logic.use_hint_auto(2)
	assert_true(result.success, "Hint should succeed by picking another unsolved cell")
	assert_ne(result.cell_index, 2, "Should not choose the already-correct preferred cell")


func test_use_hint_auto_fails_when_no_unsolved_cells() -> void:
	for i in 81:
		logic.current_grid[i] = logic.solution[i]
	var result := logic.use_hint_auto(-1)
	assert_false(result.success, "Should return success=false when nothing left to hint")
