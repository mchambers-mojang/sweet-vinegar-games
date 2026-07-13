class_name ShikakuReplayAdapter extends GameReplayAdapter

## Replay adapter for Shikaku.
## Handles rectangle placements and removals on the puzzle grid.

const _BoardScript := preload("res://scripts/shikaku/shikaku_board.gd")


func get_initial_state(replay: Dictionary) -> Dictionary:
	var initial_state := super.get_initial_state(replay)
	var numbers: Dictionary = initial_state.get("numbers", {})
	if not numbers.is_empty():
		return initial_state

	var header: Dictionary = replay.get("header", {})
	var footer: Dictionary = replay.get("footer", {})
	var final_state: Dictionary = footer.get("final_state", {})
	var width := int(final_state.get("width", 0))
	var height := int(final_state.get("height", 0))
	var seed := int(header.get("seed", -1))
	if width <= 0 or height <= 0 or seed < 0:
		return initial_state

	var generated := ShikakuGenerator.generate(width, height, seed)
	var generated_numbers: Dictionary = generated.get("numbers", {})
	if not _numbers_match_recording(replay, width, height, generated_numbers):
		return initial_state
	var serialized_numbers: Dictionary = {}
	for pos in generated_numbers:
		var cell := pos as Vector2i
		serialized_numbers["%d,%d" % [cell.x, cell.y]] = int(generated_numbers[pos])
	return {
		"width": width,
		"height": height,
		"numbers": serialized_numbers,
	}


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


func apply_frame(frame: Dictionary, visual: Control, _suppress_effects: bool = false) -> void:
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


func should_include_frame(frame: Dictionary) -> bool:
	var input_event: Dictionary = frame.get("input_event", {})
	var event_type := str(input_event.get("type", ""))
	var payload: Dictionary = input_event.get("payload", {})
	if event_type == "rectangle_placed":
		return (
			payload.has("x")
			and payload.has("y")
			and payload.has("w")
			and payload.has("h")
			and int(payload["w"]) > 0
			and int(payload["h"]) > 0
		)
	if event_type == "rectangle_removed":
		return payload.has("index") and int(payload["index"]) >= 0
	return false


func _numbers_match_recording(
		replay: Dictionary, width: int, height: int, numbers: Dictionary) -> bool:
	var rects: Array[Rect2i] = []
	for frame in replay.get("frames", []):
		if not should_include_frame(frame):
			continue
		var input_event: Dictionary = frame.get("input_event", {})
		var payload: Dictionary = input_event.get("payload", {})
		if str(input_event.get("type", "")) == "rectangle_placed":
			rects.append(Rect2i(
				int(payload["x"]),
				int(payload["y"]),
				int(payload["w"]),
				int(payload["h"]),
			))
		else:
			var index := int(payload["index"])
			if index < rects.size():
				rects.remove_at(index)

	var covered: Dictionary = {}
	for rect in rects:
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > width or rect.end.y > height:
			return false
		var clue_count := 0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				if covered.has(cell):
					return false
				covered[cell] = true
				if numbers.has(cell):
					clue_count += 1
					if int(numbers[cell]) != rect.get_area():
						return false
		if clue_count != 1:
			return false

	var footer: Dictionary = replay.get("footer", {})
	if str(footer.get("outcome", "")) == "win":
		return covered.size() == width * height
	return true


func get_visual_event_types() -> Array[String]:
	return ["rectangle_placed", "rectangle_removed"]
