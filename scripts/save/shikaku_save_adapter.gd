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


## A valid Shikaku save must have positive dimensions and at least one anchor.
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
	return true