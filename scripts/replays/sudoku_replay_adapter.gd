class_name SudokuReplayAdapter extends GameReplayAdapter

## Replay adapter for Sudoku.
## Steps through number placements and hint reveals on the puzzle grid.

const _BoardScript := preload("res://scripts/sudoku/sudoku_board.gd")


func setup_playback(_initial_state: Dictionary) -> Control:
	var board := Control.new()
	board.set_script(_BoardScript)
	return board


func reset_to_state(initial_state: Dictionary, visual: Control) -> void:
	var board := visual as SudokuBoard
	var puzzle_data: Array = initial_state.get("puzzle", [])
	var puzzle: Array[int] = []
	for v in puzzle_data:
		puzzle.append(int(v))
	if puzzle.size() == 81:
		board.load_puzzle(puzzle)


func should_include_frame(frame: Dictionary) -> bool:
	var input_event: Dictionary = frame.get("input_event", {})
	var event_type := str(input_event.get("type", ""))
	var payload: Dictionary = input_event.get("payload", {})
	# Notes-mode inputs have no visual effect; reject at collection time so the
	# frame counter and progress slider stay accurate.
	if event_type == "number_input" and bool(payload.get("notes_mode", false)):
		return false
	return true


func apply_frame(frame: Dictionary, visual: Control, suppress_effects: bool = false) -> void:
	var board := visual as SudokuBoard
	var input_event: Dictionary = frame.get("input_event", {})
	var event_type := str(input_event.get("type", ""))
	var payload: Dictionary = input_event.get("payload", {})

	var index := int(payload.get("index", -1))
	var number := 0

	if event_type == "hint_pressed":
		number = int(payload.get("value", 0))
	else:
		number = int(payload.get("number", 0))

	if index < 0 or index >= 81 or number <= 0 or number > 9:
		return
	var cell := board.cells[index]
	if cell.is_given:
		return
	cell.set_value(number)
	if not suppress_effects:
		board.select_cell(index)


func get_visual_event_types() -> Array[String]:
	return ["number_input", "hint_pressed"]
