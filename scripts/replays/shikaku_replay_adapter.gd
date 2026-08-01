class_name ShikakuReplayAdapter extends GameReplayAdapter

## Replay adapter for Shikaku.
## Handles rectangle placements and removals on the puzzle grid.
## Supports both Standard and Shapes modes; migrates legacy replays that only
## recorded 'numbers' to area-only anchors.

const _BoardScript := preload("res://scripts/shikaku/shikaku_board.gd")


func get_initial_state(replay: Dictionary) -> Dictionary:
	var initial_state := super.get_initial_state(replay)

	# If the initial state already has anchors, use them directly.
	if not (initial_state.get("anchors", null) is Dictionary and (initial_state["anchors"] as Dictionary).is_empty()):
		if initial_state.get("anchors", null) is Dictionary and not (initial_state["anchors"] as Dictionary).is_empty():
			return initial_state

	# Legacy path: try to recover from recorded numbers or re-generate.
	var raw_numbers = initial_state.get("numbers")
	if raw_numbers is Dictionary and not (raw_numbers as Dictionary).is_empty():
		# Convert legacy numbers to area-only anchors.
		var numbers: Dictionary = raw_numbers as Dictionary
		var anchors: Dictionary = {}
		for key in numbers.keys():
			anchors[key] = {"area": int(numbers[key]), "shape": ShikakuLogic.SHAPE_ABSENT}
		initial_state["anchors"] = anchors
		if not initial_state.has("mode"):
			initial_state["mode"] = ShikakuLogic.RULE_SET_STANDARD
		return initial_state

	# Nothing in initial state — try re-generating from seed.
	var header: Dictionary = replay.get("header", {})
	var footer: Dictionary = replay.get("footer", {})
	var final_state: Dictionary = footer.get("final_state", {})
	var width := int(final_state.get("width", 0))
	var height := int(final_state.get("height", 0))
	var seed_val := int(header.get("seed", -1))
	var rule_set := int(final_state.get("mode", ShikakuLogic.RULE_SET_STANDARD))
	if width <= 0 or height <= 0 or seed_val < 0:
		return initial_state

	var generated := ShikakuGenerator.generate(width, height, seed_val, rule_set)
	var generated_anchors: Dictionary = generated.get("anchors", {})
	if not _anchors_match_recording(replay, width, height, generated_anchors):
		return initial_state

	var serialized_anchors: Dictionary = {}
	for pos in generated_anchors:
		var cell := pos as Vector2i
		var anchor: Dictionary = generated_anchors[pos]
		serialized_anchors["%d,%d" % [cell.x, cell.y]] = {
			"area": int(anchor.get("area", 0)),
			"shape": int(anchor.get("shape", ShikakuLogic.SHAPE_ABSENT)),
		}
	return {
		"width": width,
		"height": height,
		"mode": rule_set,
		"anchors": serialized_anchors,
	}


func setup_playback(_initial_state: Dictionary) -> Control:
	var board := Control.new()
	board.set_script(_BoardScript)
	return board


func reset_to_state(initial_state: Dictionary, visual: Control) -> void:
	var board := visual as ShikakuBoard
	var w := int(initial_state.get("width", 5))
	var h := int(initial_state.get("height", 5))

	# Build anchors dict from serialized form.
	var anchors: Dictionary = {}

	var raw_anchors = initial_state.get("anchors", null)
	if raw_anchors is Dictionary and not (raw_anchors as Dictionary).is_empty():
		for key in raw_anchors.keys():
			var pos: Vector2i
			if key is Vector2i:
				pos = key
			else:
				var parts := str(key).split(",")
				if parts.size() == 2:
					pos = Vector2i(int(parts[0]), int(parts[1]))
				else:
					continue
			var entry = raw_anchors[key]
			if entry is Dictionary:
				anchors[pos] = entry
			elif entry is int or entry is float:
				anchors[pos] = {"area": int(entry), "shape": ShikakuLogic.SHAPE_ABSENT}
	else:
		# Legacy: numbers dict.
		var raw_numbers_data = initial_state.get("numbers")
		if raw_numbers_data is Dictionary:
			var numbers_data: Dictionary = raw_numbers_data as Dictionary
			for key in numbers_data.keys():
				var parts := str(key).split(",")
				if parts.size() == 2:
					anchors[Vector2i(int(parts[0]), int(parts[1]))] = {
						"area": int(numbers_data[key]),
						"shape": ShikakuLogic.SHAPE_ABSENT,
					}

	board.setup(w, h, anchors)

	# Restore placed rectangles from initial state so that resumed-session
	# replays start with the correct board state and removal indices match.
	var placed_data = initial_state.get("placed_rects", null)
	if placed_data is Array:
		for entry in placed_data as Array:
			if entry is Dictionary:
				var d := entry as Dictionary
				var rect := Rect2i(
					int(d.get("x", 0)),
					int(d.get("y", 0)),
					int(d.get("w", 1)),
					int(d.get("h", 1)),
				)
				board.add_rect(rect)

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


## Verify that the regenerated anchors are consistent with the recorded moves.
func _anchors_match_recording(
		replay: Dictionary, width: int, height: int, anchors: Dictionary) -> bool:
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
		var rect_area := rect.size.x * rect.size.y
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				if covered.has(cell):
					return false
				covered[cell] = true
				if anchors.has(cell):
					clue_count += 1
					var anchor: Dictionary = anchors[cell]
					var anchor_area: int = int(anchor.get("area", 0))
					if anchor_area > 0 and anchor_area != rect_area:
						return false
		if clue_count != 1:
			return false

	var footer: Dictionary = replay.get("footer", {})
	if str(footer.get("outcome", "")) == "win":
		return covered.size() == width * height
	return true


## Backward-compat wrapper used by legacy code paths.
func _numbers_match_recording(
		replay: Dictionary, width: int, height: int, numbers: Dictionary) -> bool:
	var anchors: Dictionary = {}
	for pos in numbers.keys():
		anchors[pos] = {"area": int(numbers[pos]), "shape": ShikakuLogic.SHAPE_ABSENT}
	return _anchors_match_recording(replay, width, height, anchors)


func get_visual_event_types() -> Array[String]:
	return ["rectangle_placed", "rectangle_removed"]
