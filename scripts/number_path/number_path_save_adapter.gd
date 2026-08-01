class_name NumberPathSaveAdapter extends GameSaveAdapter

## Save adapter for Number Path.
## Validates that the saved data contains valid dimensions and a non-completed game.


func _get_game_id() -> String:
	return "number_path"


## Return the saved tier, or TIER_EASY if no save.
func get_tier() -> int:
	return int(restore().get("tier", NumberPathLogic.TIER_EASY))


## Upgrade save data from an older schema version.
func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	return data


## A valid Number Path save must have valid dimensions, tier, non-empty checkpoints in
## range, barriers with valid fields, non-empty solution path, and a non-completed game.
func _can_resume_from(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var w = data.get("width", 0)
	var h = data.get("height", 0)
	if not (w is int) or (w as int) <= 0 or not (h is int) or (h as int) <= 0:
		push_warning("NumberPathSaveAdapter: corrupted save — invalid dimensions")
		return false
	# Reject completed saves
	if data.get("is_completed", false):
		return false
	# Validate tier
	var tier = data.get("tier", -1)
	if not (tier is int) or (tier as int) < 0 or (tier as int) > 3:
		push_warning("NumberPathSaveAdapter: corrupted save — invalid tier")
		return false
	# Validate checkpoints
	var cps = data.get("checkpoints", null)
	if not (cps is Array):
		push_warning("NumberPathSaveAdapter: corrupted save — missing checkpoints")
		return false
	var cps_arr := cps as Array
	if cps_arr.is_empty():
		push_warning("NumberPathSaveAdapter: corrupted save — no checkpoints")
		return false
	for cp in cps_arr:
		if not (cp is Dictionary):
			push_warning("NumberPathSaveAdapter: corrupted save — invalid checkpoint entry")
			return false
		var cx = (cp as Dictionary).get("x", -1)
		var cy = (cp as Dictionary).get("y", -1)
		var cn = (cp as Dictionary).get("n", -1)
		if not (cx is int) or (cx as int) < 0 or (cx as int) >= (w as int):
			push_warning("NumberPathSaveAdapter: corrupted save — checkpoint x out of range")
			return false
		if not (cy is int) or (cy as int) < 0 or (cy as int) >= (h as int):
			push_warning("NumberPathSaveAdapter: corrupted save — checkpoint y out of range")
			return false
		if not (cn is int) or (cn as int) < 1:
			push_warning("NumberPathSaveAdapter: corrupted save — invalid checkpoint number")
			return false
	# Validate barriers
	var bs = data.get("barriers", null)
	if bs != null:
		if not (bs is Array):
			push_warning("NumberPathSaveAdapter: corrupted save — invalid barriers field")
			return false
		for b in (bs as Array):
			if not (b is Dictionary):
				push_warning("NumberPathSaveAdapter: corrupted save — invalid barrier entry")
				return false
			var br = (b as Dictionary).get("r", -1)
			var bc2 = (b as Dictionary).get("c", -1)
			var bd = (b as Dictionary).get("dir", -1)
			if not (br is int) or (br as int) < 0 or (br as int) >= (h as int):
				push_warning("NumberPathSaveAdapter: corrupted save — barrier r out of range")
				return false
			if not (bc2 is int) or (bc2 as int) < 0 or (bc2 as int) >= (w as int):
				push_warning("NumberPathSaveAdapter: corrupted save — barrier c out of range")
				return false
			if not (bd is int) or ((bd as int) != 0 and (bd as int) != 1):
				push_warning("NumberPathSaveAdapter: corrupted save — invalid barrier dir")
				return false
	# Validate solution path length
	var sp = data.get("solution_path", null)
	if sp == null or not (sp is Array) or (sp as Array).is_empty():
		push_warning("NumberPathSaveAdapter: corrupted save — missing solution path")
		return false
	if (sp as Array).size() != (w as int) * (h as int):
		push_warning("NumberPathSaveAdapter: corrupted save — solution path wrong length")
		return false
	return true
