class_name CrownGridReplayAdapter extends GameReplayAdapter

## Replay adapter for Crown Grid.
## Reconstructs board state from recorded crown placements, exclusions, and hints.

const _BoardScript := preload("res://scripts/crown_grid/crown_grid_board.gd")


func get_initial_state(replay: Dictionary) -> Dictionary:
	return super.get_initial_state(replay)


func setup_playback(_initial_state: Dictionary) -> Control:
	var board := Control.new()
	board.set_script(_BoardScript)
	return board


func reset_to_state(initial_state: Dictionary, visual: Control) -> void:
	var board := visual as CrownGridBoard
	var size := int(initial_state.get("size", 6))
	var regions_raw = initial_state.get("regions", [])
	var regions := PackedInt32Array()
	if regions_raw is Array:
		for v in regions_raw:
			regions.append(int(v))
	elif regions_raw is PackedInt32Array:
		regions = regions_raw as PackedInt32Array
	board.setup(size, regions)
	board.queue_redraw()


func apply_frame(frame: Dictionary, visual: Control, _suppress_effects: bool = false) -> void:
	var board := visual as CrownGridBoard
	var input_event: Dictionary = frame.get("input_event", {})
	var event_type := str(input_event.get("type", ""))
	var payload: Dictionary = input_event.get("payload", {})

	var size := board.grid_size

	match event_type:
		"cell_state_changed", "hint_applied":
			var col := int(payload.get("col", -1))
			var row := int(payload.get("row", -1))
			var new_state := int(payload.get("new_state", CrownGridLogic.CELL_EMPTY))
			if col >= 0 and row >= 0 and col < size and row < size:
				board.cell_states[row * size + col] = new_state

		"exclusions_painted":
			var cols: Array = payload.get("cols", [])
			var rows: Array = payload.get("rows", [])
			for i in range(mini(cols.size(), rows.size())):
				var c := int(cols[i])
				var r := int(rows[i])
				if c >= 0 and r >= 0 and c < size and r < size:
					if board.cell_states[r * size + c] == CrownGridLogic.CELL_EMPTY:
						board.cell_states[r * size + c] = CrownGridLogic.CELL_EXCLUDED

	board.queue_redraw()


func should_include_frame(frame: Dictionary) -> bool:
	var input_event: Dictionary = frame.get("input_event", {})
	var event_type := str(input_event.get("type", ""))
	return event_type in ["cell_state_changed", "exclusions_painted", "hint_applied"]


func get_visual_event_types() -> Array[String]:
	return ["cell_state_changed", "exclusions_painted", "hint_applied", "game_completed"]
