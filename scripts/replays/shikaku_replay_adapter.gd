class_name ShikakuReplayAdapter extends GameReplayAdapter

## Replay adapter for Shikaku.
## Handles rectangle placements and removals on the puzzle grid.

const _BoardScript := preload("res://scripts/shikaku/shikaku_board.gd")


func setup_playback(_initial_state: Dictionary) -> Control:
	var board := Control.new()
	board.set_script(_BoardScript)
	return board


func reset_to_state(initial_state: Dictionary, visual: Control) -> void:
	var board := visual as ShikakuBoard
	var w := int(initial_state.get("width", 5))
	var h := int(initial_state.get("height", 5))
	var numbers_data: Dictionary = initial_state.get("numbers", {})
	var numbers: Dictionary = {}
	for key in numbers_data.keys():
		var parts := str(key).split(",")
		if parts.size() == 2:
			numbers[Vector2i(int(parts[0]), int(parts[1]))] = int(numbers_data[key])
	board.setup(w, h, numbers)
	board.queue_redraw()


func apply_frame(frame: Dictionary, visual: Control) -> void:
	var board := visual as ShikakuBoard
	var input_event: Dictionary = frame.get("input_event", {})
	var event_type := str(input_event.get("type", ""))
	var payload: Dictionary = input_event.get("payload", {})

	if event_type == "rectangle_placed":
		var rect := Rect2i(
			int(payload.get("x", 0)),
			int(payload.get("y", 0)),
			int(payload.get("w", 1)),
			int(payload.get("h", 1)),
		)
		board.add_rect(rect)
	elif event_type == "rectangle_removed":
		var index := int(payload.get("index", -1))
		if index >= 0 and index < board.placed_rects.size():
			board.remove_rect(index)
	board.queue_redraw()


func get_visual_event_types() -> Array[String]:
	return ["rectangle_placed", "rectangle_removed"]
