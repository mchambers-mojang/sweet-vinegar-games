class_name EclipseGridSaveAdapter extends GameSaveAdapter

## Save adapter for Eclipse Grid.
## Validates the expected schema (positive size, matching cell array).

const _VALID_SIZES: Array[int] = [4, 6, 8, 10]
const _VALID_GLYPHS: Array[int] = [0, 1, 2]   # EMPTY, PLUS, MINUS
const _VALID_RELS: Array[int]   = [1, 2]       # EQ, NEQ
const EMPTY := EclipseGridSolver.EMPTY


func _get_game_id() -> String:
	return "eclipse_grid"


## Return the saved grid size, or 4 (default) if no save.
func get_grid_size() -> int:
	return int(restore().get("size", 4))


## Upgrade save data from an older schema version.
func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	return data


## A valid Eclipse Grid save must pass every structural check below.
## Completed games are cleared on win so they are never resumed.
func _can_resume_from(data: Dictionary) -> bool:
	if data.is_empty():
		return false

	# --- size ---
	var sz: Variant = data.get("size", null)
	if typeof(sz) != TYPE_INT:
		push_warning("EclipseGridSaveAdapter: size is not an int")
		return false
	if not (int(sz) in _VALID_SIZES):
		push_warning("EclipseGridSaveAdapter: unsupported size %d" % int(sz))
		return false
	var n: int = int(sz)
	var expected: int = n * n

	# --- cells ---
	if not _validate_glyph_array(data.get("cells", null), expected, "cells"):
		return false

	# --- givens (required) ---
	if not _validate_glyph_array(data.get("givens", null), expected, "givens"):
		return false

	# --- solution (required, no EMPTY values — must be fully solved) ---
	if not _validate_solution_array(data.get("solution", null), expected, "solution"):
		return false

	# --- cells must agree with givens at every given position ---
	var cells_arr: Array = data["cells"] as Array
	var givens_arr: Array = data["givens"] as Array
	for i in expected:
		var gv_val: int = int(givens_arr[i])
		if gv_val != EMPTY and int(cells_arr[i]) != gv_val:
			push_warning("EclipseGridSaveAdapter: cells[%d]=%d conflicts with givens[%d]=%d" % [
					i, int(cells_arr[i]), i, gv_val])
			return false

	# --- relations ---
	if not _validate_relations(data.get("h_relations", null), n, false, "h_relations"):
		return false
	if not _validate_relations(data.get("v_relations", null), n, true, "v_relations"):
		return false

	# --- assistance_mode (required; 0=NONE, 1=FREE, 2=STRICT) ---
	var am: Variant = data.get("assistance_mode", null)
	if typeof(am) != TYPE_INT or not (int(am) in [0, 1, 2]):
		push_warning("EclipseGridSaveAdapter: assistance_mode missing or invalid: %s" % str(am))
		return false

	# --- seed (must be an int; 0 is a valid seed) ---
	var seed_val: Variant = data.get("seed", null)
	if typeof(seed_val) != TYPE_INT:
		push_warning("EclipseGridSaveAdapter: seed is not an int")
		return false

	# --- undo_stack / redo_stack (must be arrays; entries validated structurally) ---
	if not _validate_undo_stack(data.get("undo_stack", null), expected, "undo_stack"):
		return false
	if not _validate_undo_stack(data.get("redo_stack", null), expected, "redo_stack"):
		return false

	return not bool(data.get("is_completed", false))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _validate_glyph_array(v: Variant, expected_len: int, label: String) -> bool:
	if typeof(v) != TYPE_ARRAY:
		push_warning("EclipseGridSaveAdapter: %s is not an Array" % label)
		return false
	var arr: Array = v as Array
	if arr.size() != expected_len:
		push_warning("EclipseGridSaveAdapter: %s has wrong length %d (expected %d)" % [label, arr.size(), expected_len])
		return false
	for element in arr:
		if typeof(element) != TYPE_INT or not (int(element) in _VALID_GLYPHS):
			push_warning("EclipseGridSaveAdapter: %s contains invalid glyph value" % label)
			return false
	return true


## Like _validate_glyph_array but also rejects EMPTY (0) values.
## Used for solution arrays, which must be fully filled.
func _validate_solution_array(v: Variant, expected_len: int, label: String) -> bool:
	if typeof(v) != TYPE_ARRAY:
		push_warning("EclipseGridSaveAdapter: %s is not an Array" % label)
		return false
	var arr: Array = v as Array
	if arr.size() != expected_len:
		push_warning("EclipseGridSaveAdapter: %s has wrong length %d (expected %d)" % [label, arr.size(), expected_len])
		return false
	for element in arr:
		if typeof(element) != TYPE_INT:
			push_warning("EclipseGridSaveAdapter: %s contains non-int value" % label)
			return false
		var val: int = int(element)
		if val != EclipseGridSolver.PLUS and val != EclipseGridSolver.MINUS:
			push_warning("EclipseGridSaveAdapter: %s contains EMPTY or invalid value %d" % [label, val])
			return false
	return true


func _validate_relations(v: Variant, n: int, is_vertical: bool, label: String) -> bool:
	if v == null:
		return true   # omitted relations dictionary is fine
	if typeof(v) != TYPE_DICTIONARY:
		push_warning("EclipseGridSaveAdapter: %s is not a Dictionary" % label)
		return false
	var d: Dictionary = v as Dictionary
	for key in d.keys():
		# Keys may be stored as "x,y" strings (serialised) or Vector2i (in-memory).
		var x := -1
		var y := -1
		if key is Vector2i:
			x = (key as Vector2i).x
			y = (key as Vector2i).y
		elif typeof(key) == TYPE_STRING:
			var parts: PackedStringArray = (key as String).split(",")
			if parts.size() != 2:
				push_warning("EclipseGridSaveAdapter: %s key has wrong format" % label)
				return false
			if not parts[0].is_valid_int() or not parts[1].is_valid_int():
				push_warning("EclipseGridSaveAdapter: %s key is not a valid coordinate pair" % label)
				return false
			x = int(parts[0])
			y = int(parts[1])
		else:
			push_warning("EclipseGridSaveAdapter: %s key has unexpected type" % label)
			return false
		# Horizontal clue: x in [0, n-2], y in [0, n-1]
		# Vertical clue:   x in [0, n-1], y in [0, n-2]
		var x_max := n - 2 if not is_vertical else n - 1
		var y_max := n - 1 if not is_vertical else n - 2
		if x < 0 or x > x_max or y < 0 or y > y_max:
			push_warning("EclipseGridSaveAdapter: %s key (%d,%d) out of bounds for size %d" % [label, x, y, n])
			return false
		var rel: Variant = d[key]
		if typeof(rel) != TYPE_INT or not (int(rel) in _VALID_RELS):
			push_warning("EclipseGridSaveAdapter: %s relation value is invalid" % label)
			return false
	return true


## Validate that a undo/redo stack is an Array whose entries are Dictionaries with
## valid index (int in [0, max_idx-1]) and old/new_value (int in _VALID_GLYPHS).
## A missing (null) stack is treated as an empty array and accepted.
func _validate_undo_stack(v: Variant, max_idx: int, label: String) -> bool:
	if v == null:
		return true  # omitted stack is fine
	if typeof(v) != TYPE_ARRAY:
		push_warning("EclipseGridSaveAdapter: %s is not an Array" % label)
		return false
	var arr: Array = v as Array
	for entry in arr:
		if typeof(entry) != TYPE_DICTIONARY:
			push_warning("EclipseGridSaveAdapter: %s entry is not a Dictionary" % label)
			return false
		var d: Dictionary = entry as Dictionary
		var idx_v: Variant = d.get("index", null)
		if typeof(idx_v) != TYPE_INT or int(idx_v) < 0 or int(idx_v) >= max_idx:
			push_warning("EclipseGridSaveAdapter: %s entry has invalid index" % label)
			return false
		for field in ["old_value", "new_value"]:
			var fv: Variant = d.get(field, null)
			if typeof(fv) != TYPE_INT or not (int(fv) in _VALID_GLYPHS):
				push_warning("EclipseGridSaveAdapter: %s entry has invalid %s" % [label, field])
				return false
	return true
