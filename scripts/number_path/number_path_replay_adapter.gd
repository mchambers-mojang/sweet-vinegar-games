class_name NumberPathReplayAdapter extends GameReplayAdapter

## Replay adapter for Number Path.
## Handles path_extended, path_truncated, hint_applied, and game_completed events.

const _BoardScript := preload("res://scripts/number_path/number_path_board.gd")


func get_initial_state(replay: Dictionary) -> Dictionary:
	return super.get_initial_state(replay)


func setup_playback(_initial_state: Dictionary) -> Control:
	var board := Control.new()
	board.set_script(_BoardScript)
	return board


func reset_to_state(initial_state: Dictionary, visual: Control) -> void:
	var board := visual as NumberPathBoard
	if board == null:
		return
	var w := int(initial_state.get("width", 5))
	var h := int(initial_state.get("height", 5))
	var cps_raw: Array = initial_state.get("checkpoints", [])
	var barriers_raw: Array = initial_state.get("barriers", [])

	var checkpoints: Array[Dictionary] = []
	for cp in cps_raw:
		if cp is Dictionary:
			checkpoints.append(cp.duplicate())

	var barriers: Array[Dictionary] = []
	for b in barriers_raw:
		if b is Dictionary:
			barriers.append(b.duplicate())

	board.setup(w, h, checkpoints, barriers)

	# Restore initial path (checkpoint 1 is already placed at game start)
	var initial_path_raw: Array = initial_state.get("initial_path", [])
	var initial_path: Array[Vector2i] = []
	for p in initial_path_raw:
		if p is Dictionary:
			initial_path.append(Vector2i(int(p.get("x", 0)), int(p.get("y", 0))))
	board.set_path(initial_path)
	board.queue_redraw()


func apply_frame(frame: Dictionary, visual: Control, _suppress_effects: bool = false) -> void:
	var board := visual as NumberPathBoard
	if board == null:
		return

	var input_event: Dictionary = frame.get("input_event", {})
	var event_type := str(input_event.get("type", ""))
	var payload: Dictionary = input_event.get("payload", {})

	if event_type == "path_extended":
		var cell := Vector2i(int(payload.get("x", 0)), int(payload.get("y", 0)))
		board.extend_path(cell)
	elif event_type == "path_truncated":
		var length := int(payload.get("length", 0))
		board.truncate_path(length)
	elif event_type == "hint_applied":
		# Contradiction hints only flash cells — geometry is unchanged.
		if not payload.get("contradiction", false):
			var cell := Vector2i(int(payload.get("x", 0)), int(payload.get("y", 0)))
			board.extend_path(cell)
	elif event_type == "undo_applied":
		var path_arr: Array = payload.get("path", [])
		if not path_arr.is_empty():
			var restored: Array[Vector2i] = []
			for p in path_arr:
				if p is Dictionary:
					restored.append(Vector2i(int(p.get("x", 0)), int(p.get("y", 0))))
			board.set_path(restored)
		else:
			# Legacy: older replays only recorded length (truncation only)
			board.truncate_path(int(payload.get("length", 0)))
	elif event_type == "redo_applied":
		var path_arr: Array = payload.get("path", [])
		if not path_arr.is_empty():
			var restored: Array[Vector2i] = []
			for p in path_arr:
				if p is Dictionary:
					restored.append(Vector2i(int(p.get("x", 0)), int(p.get("y", 0))))
			board.set_path(restored)
		else:
			# Fallback: truncation/extension by length is not enough for redo;
			# this branch handles old replays missing the path field.
			board.truncate_path(int(payload.get("length", 0)))
	board.queue_redraw()


func should_include_frame(frame: Dictionary) -> bool:
	var input_event: Dictionary = frame.get("input_event", {})
	var event_type := str(input_event.get("type", ""))
	return event_type in ["path_extended", "path_truncated", "hint_applied",
			"undo_applied", "redo_applied", "game_completed"]


func get_visual_event_types() -> Array[String]:
	return ["path_extended", "path_truncated", "hint_applied",
			"undo_applied", "redo_applied", "game_completed"]
