class_name EclipseGridReplayAdapter extends GameReplayAdapter

## Replay adapter for Eclipse Grid.
## Handles glyph_changed, hint_applied, and game_completed events.

const _BoardScript := preload("res://scripts/eclipse_grid/eclipse_grid_board.gd")


func get_initial_state(replay: Dictionary) -> Dictionary:
	return super.get_initial_state(replay)


func setup_playback(initial_state: Dictionary) -> Control:
	var board := Control.new()
	board.set_script(_BoardScript)
	return board


func reset_to_state(initial_state: Dictionary, visual: Control) -> void:
	var board := visual as EclipseGridBoard
	var sz := int(initial_state.get("size", 4))
	var givens_raw = initial_state.get("givens", [])
	var givens: Array[int] = []
	for v in givens_raw:
		givens.append(int(v))
	var hr: Dictionary = _deserialize_relations(initial_state.get("h_relations", {}))
	var vr: Dictionary = _deserialize_relations(initial_state.get("v_relations", {}))
	board.setup(sz, givens, givens.duplicate(), hr, vr)
	board.queue_redraw()


func apply_frame(frame: Dictionary, visual: Control, _suppress_effects: bool = false) -> void:
	var board := visual as EclipseGridBoard
	var input_event: Dictionary = frame.get("input_event", {})
	var event_type := str(input_event.get("type", ""))
	var payload: Dictionary = input_event.get("payload", {})

	if event_type == "glyph_changed" or event_type == "hint_applied":
		var idx := int(payload.get("index", -1))
		var val := int(payload.get("new_value", 0))
		if event_type == "hint_applied":
			val = int(payload.get("value", 0))
		if idx >= 0 and idx < board.cells.size():
			board.cells[idx] = val
	board.queue_redraw()


func should_include_frame(frame: Dictionary) -> bool:
	var input_event: Dictionary = frame.get("input_event", {})
	var event_type := str(input_event.get("type", ""))
	var payload: Dictionary = input_event.get("payload", {})
	if event_type == "glyph_changed":
		return payload.has("index") and payload.has("new_value")
	if event_type == "hint_applied":
		return payload.has("index") and payload.has("value")
	return false


func get_visual_event_types() -> Array[String]:
	return ["glyph_changed", "hint_applied"]


func _deserialize_relations(data: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not (data is Dictionary):
		return result
	for key in data.keys():
		if key is Vector2i:
			result[key] = int(data[key])
			continue
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() == 2:
			result[Vector2i(int(parts[0]), int(parts[1]))] = int(data[key])
	return result
