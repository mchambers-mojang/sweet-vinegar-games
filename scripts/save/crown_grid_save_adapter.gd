class_name CrownGridSaveAdapter extends GameSaveAdapter

## Save adapter for Crown Grid.
## Validates tier, size, regions (topology + connectivity), cells, solution
## (range + puzzle compatibility), assistance_mode, and undo/redo entries.

const VALID_TIERS := [0, 1, 2, 3]
const VALID_ASSISTANCE_MODES := [0, 1]
## Maps each tier to its required board size (Easy→6, Medium→7, Hard→8, Expert→9).
const TIER_TO_SIZE := {0: 6, 1: 7, 2: 8, 3: 9}


func _get_game_id() -> String:
	return "crown_grid"


func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	# v0 → v1: no schema changes required
	return data


func _can_resume_from(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	if bool(data.get("is_completed", false)):
		return false

	# Validate size
	var size = data.get("size", 0)
	if typeof(size) != TYPE_INT or (size as int) < 6 or (size as int) > 9:
		push_warning("CrownGridSaveAdapter: corrupted save — invalid size")
		return false
	var sz: int = size as int

	# Validate tier
	var tier = data.get("tier", null)
	if typeof(tier) != TYPE_INT or not VALID_TIERS.has(tier as int):
		push_warning("CrownGridSaveAdapter: corrupted save — invalid tier")
		return false

	# Validate tier-to-size mapping
	var expected_size: int = TIER_TO_SIZE.get(tier as int, -1)
	if expected_size != sz:
		push_warning("CrownGridSaveAdapter: corrupted save — tier/size mismatch")
		return false

	# Validate assistance_mode
	var mode = data.get("assistance_mode", null)
	if mode != null:
		if typeof(mode) != TYPE_INT or not VALID_ASSISTANCE_MODES.has(mode as int):
			push_warning("CrownGridSaveAdapter: corrupted save — invalid assistance_mode")
			return false

	# Validate regions
	var regions = data.get("regions", null)
	if regions == null:
		push_warning("CrownGridSaveAdapter: corrupted save — missing regions")
		return false
	var regions_size: int = 0
	if regions is Array:
		regions_size = (regions as Array).size()
	elif regions is PackedInt32Array:
		regions_size = (regions as PackedInt32Array).size()
	if regions_size != sz * sz:
		push_warning("CrownGridSaveAdapter: corrupted save — regions length mismatch")
		return false
	if not _validate_region_topology(sz, regions):
		push_warning("CrownGridSaveAdapter: corrupted save — invalid region topology")
		return false
	if not _validate_region_connectivity(sz, regions):
		push_warning("CrownGridSaveAdapter: corrupted save — disconnected region")
		return false

	# Validate solution
	var solution = data.get("solution", null)
	if solution == null:
		push_warning("CrownGridSaveAdapter: corrupted save — missing solution")
		return false
	var sol_arr: Array = solution as Array if solution is Array else []
	if sol_arr.size() != sz:
		push_warning("CrownGridSaveAdapter: corrupted save — solution length mismatch")
		return false
	for v in sol_arr:
		var col := int(v)
		if col < 0 or col >= sz:
			push_warning("CrownGridSaveAdapter: corrupted save — solution column out of range")
			return false

	# Build a PackedInt32Array for the solver call
	var p_regions := PackedInt32Array()
	if regions is Array:
		for v in (regions as Array):
			p_regions.append(int(v))
	else:
		p_regions = regions as PackedInt32Array

	if not CrownGridSolver.validate_solution(sz, p_regions, sol_arr):
		push_warning("CrownGridSaveAdapter: corrupted save — solution incompatible with regions")
		return false

	# Validate cells — required field
	var cells = data.get("cells", null)
	if cells == null:
		push_warning("CrownGridSaveAdapter: corrupted save — missing cells")
		return false
	var cells_size: int = 0
	if cells is Array:
		cells_size = (cells as Array).size()
	elif cells is PackedByteArray:
		cells_size = (cells as PackedByteArray).size()
	if cells_size != sz * sz:
		push_warning("CrownGridSaveAdapter: corrupted save — cells length mismatch")
		return false
	if not _validate_cell_values(cells):
		push_warning("CrownGridSaveAdapter: corrupted save — cells contain invalid values")
		return false

	# Validate undo_stack entries
	var undo_stack = data.get("undo_stack", null)
	if undo_stack != null:
		if not (undo_stack is Array):
			push_warning("CrownGridSaveAdapter: corrupted save — undo_stack is not an array")
			return false
		for entry in (undo_stack as Array):
			if not _validate_undo_entry(entry, sz):
				push_warning("CrownGridSaveAdapter: corrupted save — invalid undo entry")
				return false

	# Validate redo_stack entries
	var redo_stack = data.get("redo_stack", null)
	if redo_stack != null:
		if not (redo_stack is Array):
			push_warning("CrownGridSaveAdapter: corrupted save — redo_stack is not an array")
			return false
		for entry in (redo_stack as Array):
			if not _validate_undo_entry(entry, sz):
				push_warning("CrownGridSaveAdapter: corrupted save — invalid redo entry")
				return false

	return true


## Validate that all region IDs are in 0..N-1 and each of the N regions appears at least once.
static func _validate_region_topology(sz: int, regions: Variant) -> bool:
	var seen: Dictionary = {}
	var arr: Array = regions as Array if regions is Array else []
	if arr.is_empty() and regions is PackedInt32Array:
		for v in (regions as PackedInt32Array):
			var reg := int(v)
			if reg < 0 or reg >= sz:
				return false
			seen[reg] = true
	else:
		for v in arr:
			var reg := int(v)
			if reg < 0 or reg >= sz:
				return false
			seen[reg] = true
	return seen.size() == sz


## Validate that every region forms a single 4-connected component.
static func _validate_region_connectivity(sz: int, regions: Variant) -> bool:
	# Group flat cell indices by region ID
	var region_cells: Dictionary = {}
	var total := sz * sz
	for i in range(total):
		var reg: int
		if regions is Array:
			reg = int((regions as Array)[i])
		elif regions is PackedInt32Array:
			reg = int((regions as PackedInt32Array)[i])
		else:
			return false
		if not region_cells.has(reg):
			region_cells[reg] = []
		(region_cells[reg] as Array).append(i)

	for reg in region_cells:
		var cell_list: Array = region_cells[reg]
		if cell_list.is_empty():
			continue
		# Build a set for O(1) membership tests
		var cell_set: Dictionary = {}
		for idx in cell_list:
			cell_set[idx] = true
		# BFS from the first cell in this region
		var visited: Dictionary = {}
		var queue: Array = [cell_list[0]]
		visited[cell_list[0]] = true
		while not queue.is_empty():
			var idx: int = queue.pop_front()
			var r := idx / sz
			var c := idx % sz
			for delta in [[0, 1], [0, -1], [1, 0], [-1, 0]]:
				var nr := r + int(delta[0])
				var nc := c + int(delta[1])
				if nr < 0 or nr >= sz or nc < 0 or nc >= sz:
					continue
				var nidx := nr * sz + nc
				if visited.has(nidx) or not cell_set.has(nidx):
					continue
				visited[nidx] = true
				queue.append(nidx)
		if visited.size() != cell_list.size():
			return false

	return true


## Validate that all cell values are 0 (empty), 1 (excluded), or 2 (crown).
static func _validate_cell_values(cells: Variant) -> bool:
	if cells is Array:
		for v in (cells as Array):
			var st := int(v)
			if st < 0 or st > 2:
				return false
	elif cells is PackedByteArray:
		for v in (cells as PackedByteArray):
			if v > 2:
				return false
	return true


## Validate an undo/redo entry for required fields, value ranges, and coordinate
## bounds.  sz must be the board size (6–9) so coordinate ranges can be checked.
static func _validate_undo_entry(entry: Variant, sz: int = -1) -> bool:
	if not (entry is Dictionary):
		return false
	var d := entry as Dictionary
	if not d.has("action"):
		return false
	var action := str(d.get("action", ""))
	match action:
		"tap":
			if not d.has("cell") or not d.has("from") or not d.has("to"):
				return false
			if not _validate_cell_coord(d["cell"], sz):
				return false
			if not _validate_cell_state(d["from"]) or not _validate_cell_state(d["to"]):
				return false
			if not d.has("auto_marked"):
				return false
			if not _validate_auto_marked(d["auto_marked"], sz):
				return false
			if not d.has("old_states"):
				return false
			if not _validate_old_states(d["old_states"], sz):
				return false
		"paint":
			if not d.has("changed") or not (d["changed"] is Array):
				return false
			for item in (d["changed"] as Array):
				if not _validate_cell_coord(item, sz):
					return false
			if not d.has("old_states"):
				return false
			if not _validate_old_states(d["old_states"], sz):
				return false
		"hint_crown":
			if not d.has("cell"):
				return false
			if not _validate_cell_coord(d["cell"], sz):
				return false
			if not d.has("auto_marked"):
				return false
			if not _validate_auto_marked(d["auto_marked"], sz):
				return false
			if not d.has("old_states"):
				return false
			if not _validate_old_states(d["old_states"], sz):
				return false
		"hint_exclude":
			if not d.has("changed") or not (d["changed"] is Array):
				return false
			for item in (d["changed"] as Array):
				if not _validate_cell_coord(item, sz):
					return false
			if not d.has("old_states"):
				return false
			if not _validate_old_states(d["old_states"], sz):
				return false
		_:
			return false
	return true


## Return true when v is a 2-element Array whose components are integers in
## [0, sz).  If sz <= 0 the range check is skipped (only shape is checked).
static func _validate_cell_coord(v: Variant, sz: int = -1) -> bool:
	if not (v is Array):
		return false
	var arr := v as Array
	if arr.size() < 2:
		return false
	if typeof(arr[0]) != TYPE_INT or typeof(arr[1]) != TYPE_INT:
		return false
	if sz > 0:
		var cx: int = int(arr[0])
		var cy: int = int(arr[1])
		if cx < 0 or cx >= sz or cy < 0 or cy >= sz:
			return false
	return true


## Return true when v is an integer equal to one of the three valid cell states.
static func _validate_cell_state(v: Variant) -> bool:
	if typeof(v) != TYPE_INT:
		return false
	var st := int(v)
	return st >= 0 and st <= 2


## Return true when v is an Array of valid 2-element coordinate arrays.
## Each element must satisfy _validate_cell_coord with the given sz bound.
static func _validate_auto_marked(v: Variant, sz: int = -1) -> bool:
	if not (v is Array):
		return false
	for item in (v as Array):
		if not _validate_cell_coord(item, sz):
			return false
	return true


## Return true when v is a Dictionary whose keys are "x,y" coordinate strings
## with components in [0, sz) and whose values are valid cell states (0–2).
## If sz <= 0, the coordinate range check is skipped.
static func _validate_old_states(v: Variant, sz: int = -1) -> bool:
	if not (v is Dictionary):
		return false
	for key in (v as Dictionary):
		if typeof(key) != TYPE_STRING:
			return false
		var parts := str(key).split(",")
		if parts.size() != 2:
			return false
		if not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return false
		if sz > 0:
			var kx := int(parts[0])
			var ky := int(parts[1])
			if kx < 0 or kx >= sz or ky < 0 or ky >= sz:
				return false
		var val: Variant = (v as Dictionary)[key]
		if not _validate_cell_state(val):
			return false
	return true
