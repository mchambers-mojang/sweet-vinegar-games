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
	var cp_seen_coords: Dictionary = {}
	var cp_seen_ns: Dictionary = {}
	for i in range(cps_arr.size()):
		var cp = cps_arr[i]
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
		# n must equal the sequential position (1-based)
		if (cn as int) != i + 1:
			push_warning("NumberPathSaveAdapter: corrupted save — non-sequential checkpoint n")
			return false
		# Duplicate coordinate check
		var coord_key := "%d,%d" % [(cx as int), (cy as int)]
		if cp_seen_coords.has(coord_key):
			push_warning("NumberPathSaveAdapter: corrupted save — duplicate checkpoint coordinates")
			return false
		cp_seen_coords[coord_key] = true
		# Duplicate n check
		if cp_seen_ns.has(cn as int):
			push_warning("NumberPathSaveAdapter: corrupted save — duplicate checkpoint n")
			return false
		cp_seen_ns[cn as int] = true
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
	# Validate current_path invariants
	var cp_raw = data.get("current_path", null)
	if cp_raw != null:
		if not (cp_raw is Array):
			push_warning("NumberPathSaveAdapter: corrupted save — current_path not an array")
			return false
		var cp_arr := cp_raw as Array
		if not cp_arr.is_empty():
			# Build barrier lookup for fast access
			var barrier_set: Dictionary = {}
			if bs != null and (bs is Array):
				for b in (bs as Array):
					if b is Dictionary:
						barrier_set["%d,%d,%d" % [int((b as Dictionary).get("r", 0)), int((b as Dictionary).get("c", 0)), int((b as Dictionary).get("dir", 0))]] = true
			# Must start at CP1
			var cp1 = cps_arr[0] as Dictionary
			var first = cp_arr[0]
			if not (first is Dictionary):
				push_warning("NumberPathSaveAdapter: corrupted save — current_path entry not a dict")
				return false
			if int((first as Dictionary).get("x", -1)) != int(cp1.get("x", -2)) \
					or int((first as Dictionary).get("y", -1)) != int(cp1.get("y", -2)):
				push_warning("NumberPathSaveAdapter: corrupted save — current_path does not start at CP1")
				return false
			var seen_cells: Dictionary = {}
			var prev_x := -1
			var prev_y := -1
			var next_cp_idx := 0
			for entry in cp_arr:
				if not (entry is Dictionary):
					push_warning("NumberPathSaveAdapter: corrupted save — current_path entry not a dict")
					return false
				var ex := int((entry as Dictionary).get("x", -1))
				var ey := int((entry as Dictionary).get("y", -1))
				if ex < 0 or ex >= (w as int) or ey < 0 or ey >= (h as int):
					push_warning("NumberPathSaveAdapter: corrupted save — current_path cell out of bounds")
					return false
				var cell_key := "%d,%d" % [ex, ey]
				if seen_cells.has(cell_key):
					push_warning("NumberPathSaveAdapter: corrupted save — current_path revisits a cell")
					return false
				if prev_x >= 0:
					var adx := absi(ex - prev_x)
					var ady := absi(ey - prev_y)
					if not ((adx == 1 and ady == 0) or (adx == 0 and ady == 1)):
						push_warning("NumberPathSaveAdapter: corrupted save — current_path has non-adjacent step")
						return false
					# Barrier crossing check
					if adx == 1:
						var left_x := mini(ex, prev_x)
						var bk := "%d,%d,%d" % [prev_y, left_x, NumberPathLogic.DIR_RIGHT]
						if barrier_set.has(bk):
							push_warning("NumberPathSaveAdapter: corrupted save — current_path crosses barrier")
							return false
					else:
						var top_y := mini(ey, prev_y)
						var bk := "%d,%d,%d" % [top_y, ex, NumberPathLogic.DIR_DOWN]
						if barrier_set.has(bk):
							push_warning("NumberPathSaveAdapter: corrupted save — current_path crosses barrier")
							return false
				# Checkpoint ordering
				for cpi in range(cps_arr.size()):
					var cpe := cps_arr[cpi] as Dictionary
					if int(cpe.get("x", -1)) == ex and int(cpe.get("y", -1)) == ey:
						if cpi != next_cp_idx:
							push_warning("NumberPathSaveAdapter: corrupted save — current_path visits checkpoint out of order")
							return false
						next_cp_idx += 1
						break
				seen_cells[cell_key] = true
				prev_x = ex
				prev_y = ey
	# Validate undo/redo stack entries contain valid path arrays
	for stack_key in ["undo_stack", "redo_stack"]:
		var stack_raw = data.get(stack_key, null)
		if stack_raw == null:
			continue
		if not (stack_raw is Array):
			push_warning("NumberPathSaveAdapter: corrupted save — %s not an array" % stack_key)
			return false
		for entry in (stack_raw as Array):
			if not (entry is Dictionary):
				push_warning("NumberPathSaveAdapter: corrupted save — %s entry not a dict" % stack_key)
				return false
			for snap_key in ["pre_snapshot", "post_snapshot"]:
				var snap = (entry as Dictionary).get(snap_key, null)
				if snap == null:
					continue
				if not (snap is Array):
					push_warning("NumberPathSaveAdapter: corrupted save — %s.%s not an array" % [stack_key, snap_key])
					return false
				for cell in (snap as Array):
					if not (cell is Dictionary):
						push_warning("NumberPathSaveAdapter: corrupted save — %s snapshot cell not a dict" % stack_key)
						return false
					var sx := (cell as Dictionary).get("x", -1)
					var sy := (cell as Dictionary).get("y", -1)
					if not (sx is int) or (sx as int) < 0 or (sx as int) >= (w as int):
						push_warning("NumberPathSaveAdapter: corrupted save — %s snapshot x out of range" % stack_key)
						return false
					if not (sy is int) or (sy as int) < 0 or (sy as int) >= (h as int):
						push_warning("NumberPathSaveAdapter: corrupted save — %s snapshot y out of range" % stack_key)
						return false
	return true
