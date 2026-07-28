class_name SudokuReplayAdapter extends GameReplayAdapter

## Replay adapter for Sudoku.
## Steps through number placements and hint reveals on the puzzle grid.
## Supports both standard 9×9 and mini 6×6 grid specs.
## Legacy replays without a grid_spec_id in initial_state default to standard_9×9.

const _BoardScript := preload("res://scripts/sudoku/sudoku_board.gd")


func setup_playback(_initial_state: Dictionary) -> Control:
	var spec := _get_spec(_initial_state)
	var board := Control.new()
	board.set_script(_BoardScript)
	if spec != null and spec.id != "standard_9x9":
		board.spec = spec
	return board


func reset_to_state(initial_state: Dictionary, visual: Control) -> void:
	var board := visual as SudokuBoard
	var spec := _get_spec(initial_state)
	if spec != null and board.spec.id != spec.id:
		board.configure_for_spec(spec)
	var puzzle_data: Array = initial_state.get("puzzle", [])
	var puzzle: Array[int] = []
	for v in puzzle_data:
		puzzle.append(int(v))
	if spec != null and puzzle.size() == spec.cell_count:
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

	if index < 0 or index >= board.spec.cell_count or number <= 0 or number > board.spec.sym_max:
		return
	var cell := board.cells[index]
	if cell.is_given:
		return
	cell.set_value(number)
	if not suppress_effects:
		board.select_cell(index)


func get_visual_event_types() -> Array[String]:
	return ["number_input", "hint_pressed"]


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Extract the SudokuGridSpec from the initial_state dictionary.
## Legacy replays without grid_spec_id default to standard_9×9.
## Returns null if the spec id is unrecognised (replay should be skipped).
func _get_spec(initial_state: Dictionary) -> SudokuGridSpec:
	var spec_id: String = str(initial_state.get("grid_spec_id", "standard_9x9"))
	var spec := SudokuGridSpec.from_id(spec_id)
	if spec == null:
		push_warning("SudokuReplayAdapter: unknown grid_spec_id '%s'" % spec_id)
		return SudokuGridSpec.STANDARD_9X9
	return spec
