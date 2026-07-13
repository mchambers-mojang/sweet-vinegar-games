class_name SudokuLogic
extends RefCounted

## Pure game logic for Sudoku — no autoloads, no nodes, no signals, no side effects.
## Takes state + player action and returns a result object.
## The Game Screen is the orchestrator: it feeds actions here, then dispatches
## side effects (sound, haptics, replay, effects, saves) based on the result.

const GRID_CELLS := 81
## Strikes required to fail the game (strict mode: 4th wrong answer loses)
const FAIL_AT_STRIKES := 4

# Config (set at construction, not read from autoloads)
var strict_mode: bool = false
var auto_remove_pencil_marks: bool = true

## Active variant constraints evaluated during placement validation.
## Set before calling init_new_game() to enable variant rules;
## passed automatically to the generator and solver during game setup.
## An empty array (default) reproduces standard Sudoku behaviour exactly.
var constraints: Array[SudokuConstraint] = []

# Game state
var puzzle: Array[int] = []
var solution: Array[int] = []
var current_grid: Array[int] = []
var pencil_marks: Array = []   # Array of Array[int], one per cell
var colors: Array = []         # Array of Color, one per cell
var difficulty: int = 0
var strikes: int = 0
var is_failed: bool = false
var is_completed: bool = false
var hints_used: int = 0

var _undo_stack: UndoStack = UndoStack.new()

var undo_stack: Array[Dictionary]:
	get:
		return _undo_stack.get_undo_entries()

var redo_stack: Array[Dictionary]:
	get:
		return _undo_stack.get_redo_entries()


## Returned by place_number().  Carries everything the orchestrator needs to
## dispatch side effects and update UI — no rule logic belongs there.
class PlaceResult:
	var valid: bool = false         # True if the action was a valid attempt
	var placed: bool = false        # True if the number was stored in the grid
	var cell_index: int = -1
	var number: int = 0
	var strikes_added: int = 0      # 0 or 1
	var game_failed: bool = false
	var game_won: bool = false
	var pencil_marks_removed: Array = []  # Array of {index, number}
	var units_completed: Array = []       # Array of {type, unit_index, cells}


## Returned by toggle_pencil_mark().
class PencilResult:
	var valid: bool = false
	var cell_index: int = -1
	var number: int = 0
	var added: bool = false


## Returned by erase_cell().
class EraseResult:
	var success: bool = false
	var cell_index: int = -1
	var old_number: int = 0
	var old_pencil_marks: Array = []


## Returned by use_hint().
class HintResult:
	var success: bool = false
	var cell_index: int = -1
	var number: int = 0
	var pencil_marks_removed: Array = []  # Array of {index, number}
	var units_completed: Array = []       # Array of {type, unit_index, cells}
	var game_won: bool = false


## Returned by undo() and redo().
class UndoRedoResult:
	var success: bool = false
	var cell_index: int = -1
	var restored_value: int = 0
	var restored_pencil_marks: Array = []
	var restored_color: Color = Color.TRANSPARENT


func _init(p_strict_mode: bool = false, p_auto_remove: bool = true) -> void:
	strict_mode = p_strict_mode
	auto_remove_pencil_marks = p_auto_remove


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Generate a fresh puzzle and initialise all state.
## Returns true on success. Returns false when the generator cannot produce a
## valid puzzle (e.g. unsatisfiable constraints); in that case no game state
## is set up and the caller must handle the failure explicitly.
func init_new_game(diff: int, seed_value: int) -> bool:
	var generator := SudokuGenerator.new()
	var result: Dictionary = generator.generate(diff, seed_value, constraints)
	if result.is_empty():
		return false
	_setup_from_arrays(diff, result["puzzle"], result["solution"])
	return true


## Restore state from a save dictionary (same format as serialize()).
func init_from_save(data: Dictionary) -> void:
	difficulty = data.get("difficulty", 0)
	strikes = data.get("strikes", 0)
	is_failed = data.get("is_failed", false)
	hints_used = data.get("hints_used", 0)
	is_completed = false

	puzzle.clear()
	for v in data.get("puzzle", []):
		puzzle.append(int(v))

	solution.clear()
	for v in data.get("solution", []):
		solution.append(int(v))

	current_grid.clear()
	for v in data.get("current_grid", []):
		current_grid.append(int(v))

	_init_pencil_marks()
	var pm_dict: Dictionary = data.get("pencil_marks", {})
	for key in pm_dict:
		var idx := int(key)
		if idx >= 0 and idx < GRID_CELLS:
			var raw = pm_dict[key]
			if raw is Array:
				var cell_marks: Array[int] = []
				for m in raw:
					cell_marks.append(int(m))
				pencil_marks[idx] = cell_marks

	_init_colors()
	var colors_dict: Dictionary = data.get("cell_colors", {})
	for key in colors_dict:
		var idx := int(key)
		if idx >= 0 and idx < GRID_CELLS:
			colors[idx] = Color.from_string(str(colors_dict[key]), Color.TRANSPARENT)

	_undo_stack.clear()


## Serialise all game-rule state. Caller adds UI fields (elapsed_time, random_seed …).
func serialize() -> Dictionary:
	var pm_dict: Dictionary = {}
	for i in GRID_CELLS:
		var marks: Array = pencil_marks[i]
		if marks.size() > 0:
			pm_dict[str(i)] = marks.duplicate()

	var colors_dict: Dictionary = {}
	for i in GRID_CELLS:
		var c: Color = colors[i]
		if c != Color.TRANSPARENT:
			colors_dict[str(i)] = c.to_html()

	return {
		"puzzle": puzzle.duplicate(),
		"solution": solution.duplicate(),
		"current_grid": current_grid.duplicate(),
		"pencil_marks": pm_dict,
		"cell_colors": colors_dict,
		"difficulty": difficulty,
		"strikes": strikes,
		"is_failed": is_failed,
		"hints_used": hints_used,
	}


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

## Attempt to place number in the given cell.
## Returns PlaceResult describing the outcome — never mutates UI.
func place_number(cell_index: int, number: int) -> PlaceResult:
	var result := PlaceResult.new()
	result.cell_index = cell_index
	result.number = number

	if cell_index < 0 or cell_index >= GRID_CELLS:
		return result
	if puzzle[cell_index] != 0:
		return result  # Given cell — not editable
	if current_grid[cell_index] == number:
		return result  # No-op: same number already there
	# Strict mode: do not allow overwriting a correctly placed cell
	if strict_mode and current_grid[cell_index] != 0 and current_grid[cell_index] == solution[cell_index]:
		return result

	result.valid = true

	# Strict mode: wrong answer or constraint violation adds a strike but does not change the grid
	if strict_mode and (solution[cell_index] != number or not _is_constraint_valid(cell_index, number)):
		strikes += 1
		result.strikes_added = 1
		if strikes >= FAIL_AT_STRIKES and not is_failed:
			is_failed = true
			result.game_failed = true
		return result

	# Valid placement — update state
	_push_undo(cell_index)
	current_grid[cell_index] = number
	pencil_marks[cell_index] = []
	colors[cell_index] = Color.TRANSPARENT
	_undo_stack.clear_redo()
	result.placed = true

	if auto_remove_pencil_marks:
		result.pencil_marks_removed = _remove_pencil_marks_for_number(cell_index, number)

	result.units_completed = _get_completed_units(cell_index)

	if _check_win():
		is_completed = true
		result.game_won = true

	return result


## Toggle a pencil mark for the given cell and number.
func toggle_pencil_mark(cell_index: int, number: int) -> PencilResult:
	var result := PencilResult.new()
	result.cell_index = cell_index
	result.number = number

	if cell_index < 0 or cell_index >= GRID_CELLS:
		return result
	if puzzle[cell_index] != 0:
		return result  # Given cell

	_push_undo(cell_index)
	_undo_stack.clear_redo()
	result.valid = true

	var marks: Array = pencil_marks[cell_index]
	if number in marks:
		marks.erase(number)
		result.added = false
	else:
		marks.append(number)
		marks.sort()
		result.added = true

	return result


## Erase the value (or pencil marks) from the given cell.
func erase_cell(cell_index: int) -> EraseResult:
	var result := EraseResult.new()
	result.cell_index = cell_index

	if cell_index < 0 or cell_index >= GRID_CELLS:
		return result
	if puzzle[cell_index] != 0:
		return result  # Given cell
	# Strict mode: cannot erase correctly placed cells
	if strict_mode and current_grid[cell_index] != 0 and current_grid[cell_index] == solution[cell_index]:
		return result

	result.old_number = current_grid[cell_index]
	var marks: Array = pencil_marks[cell_index]
	result.old_pencil_marks = marks.duplicate()

	_push_undo(cell_index)
	current_grid[cell_index] = 0
	pencil_marks[cell_index] = []
	_undo_stack.clear_redo()
	result.success = true

	return result


## Fill the given cell from the solution (hint). Caller must pick the cell index.
func use_hint(cell_index: int) -> HintResult:
	var result := HintResult.new()
	result.cell_index = cell_index

	if cell_index < 0 or cell_index >= GRID_CELLS:
		return result

	result.number = solution[cell_index]

	_push_undo(cell_index)
	current_grid[cell_index] = solution[cell_index]
	pencil_marks[cell_index] = []
	colors[cell_index] = Color.TRANSPARENT
	hints_used += 1
	_undo_stack.clear_redo()
	result.success = true

	if auto_remove_pencil_marks:
		result.pencil_marks_removed = _remove_pencil_marks_for_number(cell_index, solution[cell_index])

	result.units_completed = _get_completed_units(cell_index)

	if _check_win():
		is_completed = true
		result.game_won = true

	return result


## Select and fill a hint cell automatically.
## Prefers preferred_index if it is unsolved and editable; otherwise picks a random unsolved cell.
## Returns a result with success=false when no unsolved cell exists.
func use_hint_auto(preferred_index: int) -> HintResult:
	var index := -1
	if preferred_index >= 0 and preferred_index < GRID_CELLS:
		if _is_unsolved_editable(preferred_index):
			index = preferred_index
	if index < 0:
		var candidates: Array[int] = []
		for i in GRID_CELLS:
			if _is_unsolved_editable(i):
				candidates.append(i)
		if candidates.is_empty():
			return HintResult.new()
		candidates.shuffle()
		index = candidates[0]
	return use_hint(index)


## Revert the most recent undoable action. Returns the restored cell state.
func undo() -> UndoRedoResult:
	var result := UndoRedoResult.new()
	if not _undo_stack.can_undo():
		return result

	var state: Dictionary = _undo_stack.undo()
	var index: int = state["index"]

	# Replace the auto-moved redo entry with the current state (captured before restore).
	_undo_stack.replace_redo_top(_capture_cell_state(index))

	current_grid[index] = state["value"]
	pencil_marks[index] = (state["pencil_marks"] as Array).duplicate()
	colors[index] = state["color"]

	result.success = true
	result.cell_index = index
	result.restored_value = state["value"]
	result.restored_pencil_marks = (state["pencil_marks"] as Array).duplicate()
	result.restored_color = state["color"]

	return result


## Re-apply a previously undone action. Returns the restored cell state.
func redo() -> UndoRedoResult:
	var result := UndoRedoResult.new()
	if not _undo_stack.can_redo():
		return result

	var state: Dictionary = _undo_stack.redo()
	var index: int = state["index"]

	# Replace the auto-moved undo entry with the current state (captured before restore).
	_undo_stack.replace_undo_top(_capture_cell_state(index))

	current_grid[index] = state["value"]
	pencil_marks[index] = (state["pencil_marks"] as Array).duplicate()
	colors[index] = state["color"]

	result.success = true
	result.cell_index = index
	result.restored_value = state["value"]
	result.restored_pencil_marks = (state["pencil_marks"] as Array).duplicate()
	result.restored_color = state["color"]

	return result


## Apply a user colour to a cell (captured in undo history).
func set_cell_color(cell_index: int, color: Color) -> void:
	if cell_index < 0 or cell_index >= GRID_CELLS:
		return
	_push_undo(cell_index)
	colors[cell_index] = color
	_undo_stack.clear_redo()


## Place the correct answer without pushing an undo entry (cheat / auto-solve).
func apply_cheat_place(cell_index: int) -> PlaceResult:
	var result := PlaceResult.new()
	result.cell_index = cell_index

	if cell_index < 0 or cell_index >= GRID_CELLS:
		return result
	if current_grid[cell_index] == solution[cell_index]:
		return result  # Already correct

	result.valid = true
	result.placed = true
	result.number = solution[cell_index]

	current_grid[cell_index] = solution[cell_index]
	pencil_marks[cell_index] = []
	colors[cell_index] = Color.TRANSPARENT
	_undo_stack.clear_redo()

	if auto_remove_pencil_marks:
		result.pencil_marks_removed = _remove_pencil_marks_for_number(cell_index, solution[cell_index])

	result.units_completed = _get_completed_units(cell_index)

	if _check_win():
		is_completed = true
		result.game_won = true

	return result


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func is_cell_editable(index: int) -> bool:
	return index >= 0 and index < GRID_CELLS and puzzle[index] == 0


func is_cell_correctly_placed(index: int) -> bool:
	if index < 0 or index >= GRID_CELLS:
		return false
	return current_grid[index] != 0 and current_grid[index] == solution[index]


func count_filled_cells() -> int:
	var count := 0
	for v in current_grid:
		if int(v) != 0:
			count += 1
	return count


func is_board_locked() -> bool:
	return is_completed or is_failed


## Returns true when there is at least one action to undo.
func can_undo() -> bool:
	return _undo_stack.can_undo()


## Returns true when there is at least one action to redo.
func can_redo() -> bool:
	return _undo_stack.can_redo()


## Count how many cells in the current grid contain the given number.
func count_number_placements(number: int) -> int:
	var count := 0
	for v in current_grid:
		if int(v) == number:
			count += 1
	return count


## Pick a random unsolved cell (current_grid != solution). Returns -1 when fully solved.
## Used by the cheat auto-solve so the screen never needs to scan the grid directly.
func pick_unsolved_cell() -> int:
	var candidates: Array[int] = []
	for i in GRID_CELLS:
		if current_grid[i] != solution[i]:
			candidates.append(i)
	if candidates.is_empty():
		return -1
	candidates.shuffle()
	return candidates[0]


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _setup_from_arrays(diff: int, p_puzzle: Array, p_solution: Array) -> void:
	difficulty = diff
	puzzle.clear()
	puzzle.assign(p_puzzle)
	solution.clear()
	solution.assign(p_solution)
	current_grid.clear()
	current_grid.assign(p_puzzle.duplicate())
	_init_pencil_marks()
	_init_colors()
	strikes = 0
	is_failed = false
	is_completed = false
	hints_used = 0
	_undo_stack.clear()


func _init_pencil_marks() -> void:
	pencil_marks.clear()
	pencil_marks.resize(GRID_CELLS)
	for i in GRID_CELLS:
		pencil_marks[i] = []


func _init_colors() -> void:
	colors.clear()
	colors.resize(GRID_CELLS)
	for i in GRID_CELLS:
		colors[i] = Color.TRANSPARENT


func _push_undo(cell_index: int) -> void:
	_undo_stack.push(_capture_cell_state(cell_index))


func _capture_cell_state(cell_index: int) -> Dictionary:
	var marks: Array = pencil_marks[cell_index]
	return {
		"index": cell_index,
		"value": current_grid[cell_index],
		"pencil_marks": marks.duplicate(),
		"color": colors[cell_index],
	}


func _check_win() -> bool:
	for i in GRID_CELLS:
		if current_grid[i] != solution[i]:
			return false
	return true


## Remove all pencil marks for number in the same row, column and box as placed_index.
## Returns an Array of {index, number} for each mark removed (no duplicates).
func _remove_pencil_marks_for_number(placed_index: int, number: int) -> Array:
	var removed: Array = []
	var seen: Dictionary = {}
	var row := placed_index / 9
	var col := placed_index % 9
	var box_row := (row / 3) * 3
	var box_col := (col / 3) * 3

	var indices: Array[int] = []
	for i in 9:
		indices.append(row * 9 + i)
		indices.append(i * 9 + col)
	for r in range(box_row, box_row + 3):
		for c in range(box_col, box_col + 3):
			indices.append(r * 9 + c)

	for idx in indices:
		if seen.has(idx):
			continue
		seen[idx] = true
		var marks: Array = pencil_marks[idx]
		if number in marks:
			marks.erase(number)
			removed.append({"index": idx, "number": number})

	return removed


## Returns an Array of completed-unit descriptors for the row/col/box containing index.
## Each entry: {type: String, unit_index: int, cells: Array[int]}
func _get_completed_units(index: int) -> Array:
	var row := index / 9
	var col := index % 9
	var box_row := (row / 3) * 3
	var box_col := (col / 3) * 3
	var units: Array = []

	# Row
	var row_complete := true
	for c in 9:
		var i := row * 9 + c
		if current_grid[i] == 0 or current_grid[i] != solution[i]:
			row_complete = false
			break
	if row_complete:
		var cells: Array[int] = []
		for c in 9:
			cells.append(row * 9 + c)
		units.append({"type": "row", "unit_index": row, "cells": cells})

	# Column
	var col_complete := true
	for r in 9:
		var i := r * 9 + col
		if current_grid[i] == 0 or current_grid[i] != solution[i]:
			col_complete = false
			break
	if col_complete:
		var cells: Array[int] = []
		for r in 9:
			cells.append(r * 9 + col)
		units.append({"type": "col", "unit_index": col, "cells": cells})

	# Box
	var box_complete := true
	for r in range(box_row, box_row + 3):
		if not box_complete:
			break
		for c in range(box_col, box_col + 3):
			var i := r * 9 + c
			if current_grid[i] == 0 or current_grid[i] != solution[i]:
				box_complete = false
				break
	if box_complete:
		var cells: Array[int] = []
		for r in range(box_row, box_row + 3):
			for c in range(box_col, box_col + 3):
				cells.append(r * 9 + c)
		units.append({"type": "box", "unit_index": (box_row / 3) * 3 + box_col / 3, "cells": cells})

	return units


func _is_unsolved_editable(index: int) -> bool:
	return puzzle[index] == 0 and current_grid[index] != solution[index]


## Returns false if any active constraint forbids placing number at cell_index
## in the current grid state.  Always true when constraints is empty.
func _is_constraint_valid(cell_index: int, number: int) -> bool:
	for c in constraints:
		if not c.is_valid(current_grid, cell_index, number):
			return false
	return true
