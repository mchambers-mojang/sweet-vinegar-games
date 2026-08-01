class_name ShikakuSaveAdapter extends GameSaveAdapter

## Save adapter for Shikaku.
## Validates the expected schema (positive width/height, valid anchors) and
## migrates legacy saves that use a flat 'numbers' dict to the anchors format.
## Saves without a 'mode' key default to Standard (RULE_SET_STANDARD = 0).


func _get_game_id() -> String:
	return "shikaku"


## Return the saved grid width, or 10 (default grid size) if no save.
func get_grid_width() -> int:
	return int(restore().get("width", 10))


## Return the saved mode (0 = Standard, 1 = Shapes), defaulting to Standard.
func get_mode() -> int:
	return int(restore().get("mode", ShikakuLogic.RULE_SET_STANDARD))


## Upgrade save data from an older schema version.
## v0 → v1: 'numbers' dict migrated to 'anchors' (area-only) on next save.
func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	if data.has("numbers") and not data.has("anchors"):
		var numbers: Dictionary = data.get("numbers", {})
		if numbers is Dictionary:
			var anchors: Dictionary = {}
			for key in numbers.keys():
				var pos: Vector2i
				if key is Vector2i:
					pos = key
				else:
					var parts: PackedStringArray = str(key).split(",")
					if parts.size() != 2:
						continue
					pos = Vector2i(int(parts[0]), int(parts[1]))
				anchors["%d,%d" % [pos.x, pos.y]] = {
					"area": int(numbers[key]),
					"shape": ShikakuLogic.SHAPE_ABSENT,
				}
			data["anchors"] = anchors
		if not data.has("mode"):
			data["mode"] = ShikakuLogic.RULE_SET_STANDARD
	return data


## A valid Shikaku save must have positive dimensions, a known mode, at least
## one well-formed anchor, and every anchor must satisfy the clue-component
## invariant. Solution, placed rectangles, and undo/redo history are validated
## when present. Corrupted or structurally invalid data is treated as no-save.
func _can_resume_from(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var w = data.get("width", 0)
	var h = data.get("height", 0)
	if not (w is int) or (w as int) <= 0 or not (h is int) or (h as int) <= 0:
		push_warning("ShikakuSaveAdapter: corrupted save — invalid dimensions")
		return false
	var grid_w: int = w as int
	var grid_h: int = h as int

	# Validate mode — must be a known rule-set constant.
	var mode_val = data.get("mode", ShikakuLogic.RULE_SET_STANDARD)
	if not (mode_val is int) or (mode_val as int) < ShikakuLogic.RULE_SET_STANDARD or (mode_val as int) > ShikakuLogic.RULE_SET_SHAPES:
		push_warning("ShikakuSaveAdapter: corrupted save — unknown mode %s" % str(mode_val))
		return false

	if data.get("is_completed", false):
		return false
	# Must have at least one anchor (new format) or numbers (legacy).
	var has_anchors: bool = (data.get("anchors", null) is Dictionary) and not (data["anchors"] as Dictionary).is_empty()
	var has_numbers: bool = (data.get("numbers", null) is Dictionary) and not (data["numbers"] as Dictionary).is_empty()
	if not has_anchors and not has_numbers:
		push_warning("ShikakuSaveAdapter: corrupted save — no anchor clues found")
		return false
	# Validate legacy numbers dict when no new-format anchors are present.
	if not has_anchors and has_numbers:
		var raw_numbers: Dictionary = data["numbers"] as Dictionary
		for key in raw_numbers.keys():
			var pos: Vector2i
			if key is Vector2i:
				pos = key as Vector2i
			else:
				var parts: PackedStringArray = str(key).split(",")
				if parts.size() != 2:
					push_warning("ShikakuSaveAdapter: corrupted save — malformed legacy number key '%s'" % str(key))
					return false
				var col_str := parts[0].strip_edges()
				var row_str := parts[1].strip_edges()
				if not col_str.is_valid_int() or not row_str.is_valid_int():
					push_warning("ShikakuSaveAdapter: corrupted save — non-integer legacy number key '%s'" % str(key))
					return false
				pos = Vector2i(int(col_str), int(row_str))
			if pos.x < 0 or pos.x >= grid_w or pos.y < 0 or pos.y >= grid_h:
				push_warning("ShikakuSaveAdapter: corrupted save — legacy number position out of bounds %s" % str(pos))
				return false
			var val = raw_numbers[key]
			if not (val is int) and not (val is float):
				push_warning("ShikakuSaveAdapter: corrupted save — legacy number value not a number")
				return false
			if int(val) <= 0:
				push_warning("ShikakuSaveAdapter: corrupted save — legacy number value must be positive")
				return false
	# Deep-validate each anchor when present in new format.
	if has_anchors:
		var raw_anchors: Dictionary = data["anchors"] as Dictionary
		for key in raw_anchors.keys():
			var entry = raw_anchors[key]
			if not (entry is Dictionary):
				push_warning("ShikakuSaveAdapter: corrupted save — anchor entry not a Dictionary")
				return false
			var anchor: Dictionary = entry as Dictionary
			var area: int = int(anchor.get("area", 0))
			var shape: int = int(anchor.get("shape", ShikakuLogic.SHAPE_ABSENT))
			# Area must be non-negative.
			if area < 0:
				push_warning("ShikakuSaveAdapter: corrupted save — negative anchor area")
				return false
			# Shape must be a known constant.
			if shape < ShikakuLogic.SHAPE_ABSENT or shape > ShikakuLogic.SHAPE_WIDE:
				push_warning("ShikakuSaveAdapter: corrupted save — unknown shape enum %d" % shape)
				return false
			# Clue-component invariant: must carry at least one constraint.
			if area == 0 and shape == ShikakuLogic.SHAPE_ABSENT:
				push_warning("ShikakuSaveAdapter: corrupted save — anchor has no clue component")
				return false
			# Parse and validate anchor position — use is_valid_int() to reject
			# coercive int("garbage") == 0 silent failures.
			var pos: Vector2i
			if key is Vector2i:
				pos = key as Vector2i
			else:
				var parts: PackedStringArray = str(key).split(",")
				if parts.size() != 2:
					push_warning("ShikakuSaveAdapter: corrupted save — malformed anchor key '%s'" % str(key))
					return false
				var col_str := parts[0].strip_edges()
				var row_str := parts[1].strip_edges()
				if not col_str.is_valid_int() or not row_str.is_valid_int():
					push_warning("ShikakuSaveAdapter: corrupted save — non-integer anchor key '%s'" % str(key))
					return false
				pos = Vector2i(int(col_str), int(row_str))
			if pos.x < 0 or pos.x >= grid_w or pos.y < 0 or pos.y >= grid_h:
				push_warning("ShikakuSaveAdapter: corrupted save — anchor position %s out of bounds" % str(pos))
				return false

	# Validate solution rects if present — reject non-Array values outright.
	var raw_solution = data.get("solution", null)
	if raw_solution != null:
		if not (raw_solution is Array):
			push_warning("ShikakuSaveAdapter: corrupted save — solution must be an Array")
			return false
		for entry in raw_solution as Array:
			if not _validate_rect_entry(entry, grid_w, grid_h, "solution"):
				return false

	# Validate placed_rects if present — reject non-Array values outright.
	var raw_placed = data.get("placed_rects", null)
	if raw_placed != null:
		if not (raw_placed is Array):
			push_warning("ShikakuSaveAdapter: corrupted save — placed_rects must be an Array")
			return false
		for entry in raw_placed as Array:
			if not _validate_rect_entry(entry, grid_w, grid_h, "placed_rects"):
				return false

	# Validate undo/redo history entries if present — reject non-Array values outright.
	for stack_key in ["undo_stack", "redo_stack"]:
		var raw_stack = data.get(stack_key, null)
		if raw_stack == null:
			continue
		if not (raw_stack is Array):
			push_warning("ShikakuSaveAdapter: corrupted save — %s must be an Array" % stack_key)
			return false
		for entry in raw_stack as Array:
			if not _validate_history_entry(entry, grid_w, grid_h, stack_key):
				return false

	return true


## Return false and emit a warning when [param entry] is not a valid rect dict
## with positive dimensions inside the grid.
func _validate_rect_entry(entry: Variant, grid_w: int, grid_h: int, context: String) -> bool:
	if not (entry is Dictionary):
		push_warning("ShikakuSaveAdapter: corrupted save — %s entry not a Dictionary" % context)
		return false
	var d: Dictionary = entry as Dictionary
	# Require numeric types to avoid coercive int("garbage") == 0 silent failures.
	var x_raw = d.get("x")
	var y_raw = d.get("y")
	var rw_raw = d.get("w")
	var rh_raw = d.get("h")
	if not (x_raw is int or x_raw is float) or not (y_raw is int or y_raw is float) \
			or not (rw_raw is int or rw_raw is float) or not (rh_raw is int or rh_raw is float):
		push_warning("ShikakuSaveAdapter: corrupted save — %s rect has non-numeric field" % context)
		return false
	var x: int = int(x_raw)
	var y: int = int(y_raw)
	var rw: int = int(rw_raw)
	var rh: int = int(rh_raw)
	if rw <= 0 or rh <= 0:
		push_warning("ShikakuSaveAdapter: corrupted save — %s rect has non-positive dimensions" % context)
		return false
	if x < 0 or y < 0 or x + rw > grid_w or y + rh > grid_h:
		push_warning("ShikakuSaveAdapter: corrupted save — %s rect out of bounds" % context)
		return false
	return true


## Return false and emit a warning when [param entry] is not a valid undo/redo entry.
func _validate_history_entry(entry: Variant, grid_w: int, grid_h: int, context: String) -> bool:
	if not (entry is Dictionary):
		push_warning("ShikakuSaveAdapter: corrupted save — %s entry not a Dictionary" % context)
		return false
	var d: Dictionary = entry as Dictionary
	var action := str(d.get("action", ""))
	if action != "place" and action != "remove":
		push_warning("ShikakuSaveAdapter: corrupted save — %s unknown action '%s'" % [context, action])
		return false
	var rect_data = d.get("rect", null)
	if not (rect_data is Dictionary):
		push_warning("ShikakuSaveAdapter: corrupted save — %s entry missing rect" % context)
		return false
	return _validate_rect_entry(rect_data, grid_w, grid_h, context + ".rect")