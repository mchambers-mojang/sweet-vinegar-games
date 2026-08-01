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


## A valid Shikaku save must have positive dimensions, at least one well-formed
## anchor, and every anchor must satisfy the clue-component invariant.
## Corrupted or structurally invalid data is treated as no-save.
func _can_resume_from(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var w = data.get("width", 0)
	var h = data.get("height", 0)
	if not (w is int) or (w as int) <= 0 or not (h is int) or (h as int) <= 0:
		push_warning("ShikakuSaveAdapter: corrupted save — invalid dimensions")
		return false
	if data.get("is_completed", false):
		return false
	# Must have at least one anchor (new format) or numbers (legacy).
	var has_anchors: bool = (data.get("anchors", null) is Dictionary) and not (data["anchors"] as Dictionary).is_empty()
	var has_numbers: bool = (data.get("numbers", null) is Dictionary) and not (data["numbers"] as Dictionary).is_empty()
	if not has_anchors and not has_numbers:
		push_warning("ShikakuSaveAdapter: corrupted save — no anchor clues found")
		return false
	# Deep-validate each anchor when present in new format.
	if has_anchors:
		var grid_w: int = w as int
		var grid_h: int = h as int
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
			# Anchor position must be within grid bounds.
			var pos: Vector2i
			if key is Vector2i:
				pos = key as Vector2i
			else:
				var parts: PackedStringArray = str(key).split(",")
				if parts.size() != 2:
					push_warning("ShikakuSaveAdapter: corrupted save — malformed anchor key '%s'" % str(key))
					return false
				pos = Vector2i(int(parts[0]), int(parts[1]))
			if pos.x < 0 or pos.x >= grid_w or pos.y < 0 or pos.y >= grid_h:
				push_warning("ShikakuSaveAdapter: corrupted save — anchor position %s out of bounds" % str(pos))
				return false
	return true