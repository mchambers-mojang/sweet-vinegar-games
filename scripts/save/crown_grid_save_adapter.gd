class_name CrownGridSaveAdapter extends GameSaveAdapter

## Save adapter for Crown Grid.
## Validates tier, size, regions, cells arrays.


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
	var size = data.get("size", 0)
	if not (size is int) or (size as int) < 6 or (size as int) > 9:
		push_warning("CrownGridSaveAdapter: corrupted save — invalid size")
		return false
	var regions = data.get("regions", null)
	if regions == null:
		return false
	var expected := (size as int) * (size as int)
	var regions_size: int = 0
	if regions is Array:
		regions_size = (regions as Array).size()
	elif regions is PackedInt32Array:
		regions_size = (regions as PackedInt32Array).size()
	if regions_size != expected:
		push_warning("CrownGridSaveAdapter: corrupted save — regions length mismatch")
		return false
	return true
