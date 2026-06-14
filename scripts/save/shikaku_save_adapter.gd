class_name ShikakuSaveAdapter extends GameSaveAdapter

## Save adapter for Shikaku.
## Validates the expected schema (positive width/height) and exposes
## typed accessors so menus never need to peek into raw save data.


func _get_game_id() -> String:
	return "shikaku"


## Return the saved grid width, or 10 (default grid size) if no save.
func get_grid_width() -> int:
	return int(restore().get("width", 10))


## Migrate save data from an older schema version.
## Registered automatically so GameSaveManager calls this when loading
## a save whose version is below the current SAVE_VERSION.
func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	# v0 → v1: no schema changes required; version stamp is added by
	# GameSaveManager on the next save_game() call.
	return data


func _init() -> void:
	GameSaveManager.register_migrator("shikaku", _migrate)


## A valid shikaku save must have positive width and height dimensions and
## must not be a completed game (completed games are cleared on win).
## Corrupted or structurally invalid data is treated as no-save.
func _can_resume_from(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var w = data.get("width", 0)
	var h = data.get("height", 0)
	if not (w is int) or (w as int) <= 0 or not (h is int) or (h as int) <= 0:
		push_warning("ShikakuSaveAdapter: corrupted save — invalid dimensions")
		return false
	return not data.get("is_completed", false)
