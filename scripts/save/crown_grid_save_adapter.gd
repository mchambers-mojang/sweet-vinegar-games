class_name CrownGridSaveAdapter extends GameSaveAdapter

## Save adapter for Crown Grid.
## Validates tier, size, regions, cells, solution, assistance_mode, and undo entries.

const VALID_TIERS := [0, 1, 2, 3]
const VALID_ASSISTANCE_MODES := [0, 1]


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

	# Validate cells
	var cells = data.get("cells", null)
	if cells != null:
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

	# Validate undo/redo entries (spot-check structure)
	var undo_stack = data.get("undo_stack", null)
	if undo_stack != null:
		if not (undo_stack is Array):
			push_warning("CrownGridSaveAdapter: corrupted save — undo_stack is not an array")
			return false
		for entry in (undo_stack as Array):
			if not _validate_undo_entry(entry):
				push_warning("CrownGridSaveAdapter: corrupted save — invalid undo entry")
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


## Spot-check an undo entry for the minimal required fields.
static func _validate_undo_entry(entry: Variant) -> bool:
	if not (entry is Dictionary):
		return false
	var d := entry as Dictionary
	if not d.has("action"):
		return false
	var action := str(d.get("action", ""))
	return action in ["tap", "paint", "hint_crown", "hint_exclude"]
