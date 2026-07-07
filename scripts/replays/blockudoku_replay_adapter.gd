class_name BlockudokuReplayAdapter extends GameReplayAdapter

## Replay adapter for Blockudoku.
## Handles piece placements on the 9x9 grid.

const _BoardScript := preload("res://scripts/blockudoku/blockudoku_board.gd")


func setup_playback(_initial_state: Dictionary) -> Control:
	var board := Control.new()
	board.set_script(_BoardScript)
	return board


func reset_to_state(initial_state: Dictionary, visual: Control) -> void:
	var board := visual as BlockudokuBoard
	board.reset()
	if initial_state.has("board_state"):
		board.set_state(initial_state.get("board_state"))
	board.queue_redraw()


func apply_frame(frame: Dictionary, visual: Control, suppress_effects: bool = false) -> void:
	var board := visual as BlockudokuBoard
	var input_event: Dictionary = frame.get("input_event", {})
	var payload: Dictionary = input_event.get("payload", {})
	var grid_x := int(payload.get("grid_x", 0))
	var grid_y := int(payload.get("grid_y", 0))
	var shape_data: Array = payload.get("shape", [])

	var shape: Array[Vector2i] = []
	for cell in shape_data:
		if cell is Array and cell.size() >= 2:
			shape.append(Vector2i(int(cell[0]), int(cell[1])))
		elif cell is Dictionary:
			shape.append(Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0))))

	if shape.is_empty():
		return

	board.place_block(shape, grid_x, grid_y)
	board.check_and_clear(suppress_effects)
	board.queue_redraw()


func get_visual_event_types() -> Array[String]:
	return ["piece_placed"]
