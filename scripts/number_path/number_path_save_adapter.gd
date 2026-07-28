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


## A valid Number Path save must have positive width and height and must not be
## a completed game (completed games are cleared on win).
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
	# Reject missing checkpoints
	var cps = data.get("checkpoints", null)
	if not (cps is Array) or (cps as Array).is_empty():
		push_warning("NumberPathSaveAdapter: corrupted save — missing checkpoints")
		return false
	return true
