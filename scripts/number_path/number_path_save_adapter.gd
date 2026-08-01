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
## range, barriers with valid fields (not at board edges), fully-validated solution path,
## non-empty current path starting at CP1, valid history stacks, and a non-completed game.
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
	# Validate barriers and build lookup set for path validators
	var bs = data.get("barriers", null)
	var barrier_set: Dictionary = {}
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
			# A DIR_RIGHT barrier at the rightmost column has no cell to the right
			if (bd as int) == NumberPathLogic.DIR_RIGHT and (bc2 as int) >= (w as int) - 1:
				push_warning("NumberPathSaveAdapter: corrupted save — DIR_RIGHT barrier at rightmost column")
				return false
			# A DIR_DOWN barrier at the bottom row has no cell below
			if (bd as int) == NumberPathLogic.DIR_DOWN and (br as int) >= (h as int) - 1:
				push_warning("NumberPathSaveAdapter: corrupted save — DIR_DOWN barrier at bottom row")
				return false
			barrier_set["%d,%d,%d" % [(br as int), (bc2 as int), (bd as int)]] = true
	# Validate solution path: must have exactly w*h cells and pass full path validation
	var sp = data.get("solution_path", null)
	if sp == null or not (sp is Array) or (sp as Array).is_empty():
		push_warning("NumberPathSaveAdapter: corrupted save — missing solution path")
		return false
	if (sp as Array).size() != (w as int) * (h as int):
		push_warning("NumberPathSaveAdapter: corrupted save — solution path wrong length")
		return false
	if not _validate_path_data(sp as Array, w as int, h as int, barrier_set, cps_arr):
		push_warning("NumberPathSaveAdapter: corrupted save — solution path failed validation")
		return false
	# Validate current_path: must be present and non-empty (game always starts at CP1)
	var cp_raw = data.get("current_path", null)
	if cp_raw == null or not (cp_raw is Array) or (cp_raw as Array).is_empty():
		push_warning("NumberPathSaveAdapter: corrupted save — current_path missing or empty")
		return false
	if not _validate_path_data(cp_raw as Array, w as int, h as int, barrier_set, cps_arr):
		push_warning("NumberPathSaveAdapter: corrupted save — current_path failed validation")
		return false
	# Validate undo/redo stacks: action values, required snapshots, valid paths, transitions
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
			# Action must be a known operation name
			var action = (entry as Dictionary).get("action", null)
			if not (action is String) or not (action as String in ["extend", "truncate"]):
				push_warning("NumberPathSaveAdapter: corrupted save — %s has invalid action" % stack_key)
				return false
			# Both snapshots are required and must be non-empty valid paths
			var pre_snap = (entry as Dictionary).get("pre_snapshot", null)
			var post_snap = (entry as Dictionary).get("post_snapshot", null)
			if pre_snap == null or not (pre_snap is Array) or (pre_snap as Array).is_empty():
				push_warning("NumberPathSaveAdapter: corrupted save — %s pre_snapshot missing or empty" % stack_key)
				return false
			if post_snap == null or not (post_snap is Array) or (post_snap as Array).is_empty():
				push_warning("NumberPathSaveAdapter: corrupted save — %s post_snapshot missing or empty" % stack_key)
				return false
			if not _validate_path_data(pre_snap as Array, w as int, h as int, barrier_set, cps_arr):
				push_warning("NumberPathSaveAdapter: corrupted save — %s pre_snapshot failed validation" % stack_key)
				return false
			if not _validate_path_data(post_snap as Array, w as int, h as int, barrier_set, cps_arr):
				push_warning("NumberPathSaveAdapter: corrupted save — %s post_snapshot failed validation" % stack_key)
				return false
			# Transition must be consistent with the recorded action
			if not _validate_snapshot_transition(action as String, pre_snap as Array, post_snap as Array):
				push_warning("NumberPathSaveAdapter: corrupted save — %s transition invalid for action '%s'" % [stack_key, action])
				return false
	return true


## Validate that a non-empty path array represents a valid game path:
## each entry is a typed in-bounds cell, cells are unique, consecutive cells are
## orthogonally adjacent, no barrier is crossed, checkpoints are visited in order,
## and the path starts at CP1.
func _validate_path_data(path_arr: Array, w: int, h: int,
		barrier_set: Dictionary, cps_arr: Array) -> bool:
	if path_arr.is_empty():
		return false
	# First cell must be CP1
	var first = path_arr[0]
	if not (first is Dictionary):
		return false
	var cp1 := cps_arr[0] as Dictionary
	if int((first as Dictionary).get("x", -1)) != int(cp1.get("x", -2)) \
			or int((first as Dictionary).get("y", -1)) != int(cp1.get("y", -2)):
		return false
	var seen_cells: Dictionary = {}
	var prev_x := -1
	var prev_y := -1
	var next_cp_idx := 0
	for i in range(path_arr.size()):
		var entry = path_arr[i]
		if not (entry is Dictionary):
			return false
		var ex = (entry as Dictionary).get("x", null)
		var ey = (entry as Dictionary).get("y", null)
		if not (ex is int) or not (ey is int):
			return false
		var exi := ex as int
		var eyi := ey as int
		if exi < 0 or exi >= w or eyi < 0 or eyi >= h:
			return false
		var cell_key := "%d,%d" % [exi, eyi]
		if seen_cells.has(cell_key):
			return false
		if prev_x >= 0:
			var adx := absi(exi - prev_x)
			var ady := absi(eyi - prev_y)
			if not ((adx == 1 and ady == 0) or (adx == 0 and ady == 1)):
				return false
			# Barrier crossing check
			if adx == 1:
				var left_x := mini(exi, prev_x)
				var bk := "%d,%d,%d" % [prev_y, left_x, NumberPathLogic.DIR_RIGHT]
				if barrier_set.has(bk):
					return false
			else:
				var top_y := mini(eyi, prev_y)
				var bk := "%d,%d,%d" % [top_y, exi, NumberPathLogic.DIR_DOWN]
				if barrier_set.has(bk):
					return false
		# Checkpoint ordering: if this cell is a checkpoint it must be the next expected one
		for cpi in range(cps_arr.size()):
			var cpe := cps_arr[cpi] as Dictionary
			if int(cpe.get("x", -1)) == exi and int(cpe.get("y", -1)) == eyi:
				if cpi != next_cp_idx:
					return false
				next_cp_idx += 1
				break
		seen_cells[cell_key] = true
		prev_x = exi
		prev_y = eyi
	return true


## Validate that the pre→post snapshot transition is consistent with the action.
## "extend":  post has exactly one more cell than pre, and pre is a prefix of post.
## "truncate": post has fewer cells than pre, and post is a prefix of pre.
func _validate_snapshot_transition(action: String, pre: Array, post: Array) -> bool:
	if action == "extend":
		if post.size() != pre.size() + 1:
			return false
		for i in range(pre.size()):
			if not (pre[i] is Dictionary) or not (post[i] is Dictionary):
				return false
			if int((pre[i] as Dictionary).get("x", -1)) != int((post[i] as Dictionary).get("x", -1)):
				return false
			if int((pre[i] as Dictionary).get("y", -1)) != int((post[i] as Dictionary).get("y", -1)):
				return false
		return true
	elif action == "truncate":
		if post.size() >= pre.size():
			return false
		for i in range(post.size()):
			if not (pre[i] is Dictionary) or not (post[i] is Dictionary):
				return false
			if int((pre[i] as Dictionary).get("x", -1)) != int((post[i] as Dictionary).get("x", -1)):
				return false
			if int((pre[i] as Dictionary).get("y", -1)) != int((post[i] as Dictionary).get("y", -1)):
				return false
		return true
	return false
