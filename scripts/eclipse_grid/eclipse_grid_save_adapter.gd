class_name EclipseGridSaveAdapter extends GameSaveAdapter

## Save adapter for Eclipse Grid.
## Validates the expected schema (positive size, matching cell array).

const _VALID_SIZES: Array[int] = [4, 6, 8, 10]
const _VALID_GLYPHS: Array[int] = [0, 1, 2]   # EMPTY, PLUS, MINUS
const _VALID_RELS: Array[int]   = [1, 2]       # EQ, NEQ


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

	# --- givens (optional but validated when present) ---
	var gv: Variant = data.get("givens", null)
	if gv != null and not _validate_glyph_array(gv, expected, "givens"):
		return false

	# --- solution (optional but validated when present) ---
	var sol: Variant = data.get("solution", null)
	if sol != null and not _validate_glyph_array(sol, expected, "solution"):
		return false

	# --- relations ---
	if not _validate_relations(data.get("h_relations", null), n, false, "h_relations"):
		return false
	if not _validate_relations(data.get("v_relations", null), n, true, "v_relations"):
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
