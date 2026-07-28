class_name EclipseGridSaveAdapter extends GameSaveAdapter

## Save adapter for Eclipse Grid.
## Validates the expected schema (positive size, matching cell array).


func _get_game_id() -> String:
	return "eclipse_grid"


## Return the saved grid size, or 4 (default) if no save.
func get_grid_size() -> int:
	return int(restore().get("size", 4))


## Upgrade save data from an older schema version.
func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	return data


## A valid Eclipse Grid save must have a positive size and a cell array of
## matching length.  Completed games are cleared on win so they are never resumed.
func _can_resume_from(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var sz: Variant = data.get("size", null)
	if typeof(sz) != TYPE_INT or int(sz) <= 0:
		push_warning("EclipseGridSaveAdapter: corrupted save — missing or invalid size")
		return false
	var expected: int = int(sz) * int(sz)
	var cells: Variant = data.get("cells", null)
	if typeof(cells) != TYPE_ARRAY or int((cells as Array).size()) != expected:
		push_warning("EclipseGridSaveAdapter: corrupted save — missing or wrong-length cells")
		return false
	return not bool(data.get("is_completed", false))
