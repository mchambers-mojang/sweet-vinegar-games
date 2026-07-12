class_name SudokuSaveAdapter extends GameSaveAdapter

## Save adapter for Sudoku.
## Validates the expected schema (81-cell puzzle array) and exposes
## typed accessors so menus never need to peek into raw save data.


func _get_game_id() -> String:
	return "sudoku"


## Return the saved difficulty level (0 = Easy … 4 = Evil), or 0 if no save.
func get_difficulty() -> int:
	return int(restore().get("difficulty", 0))


## Return true when the saved game is a Killer Sudoku.
func get_is_killer() -> bool:
	return bool(restore().get("is_killer", false))


## Upgrade save data from an older schema version.
func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	# v0 → v1: no schema changes required; version stamp is added by
	# the adapter on the next save() call.
	return data


## A valid sudoku save must contain a 81-element puzzle array.
## For Killer saves, the cages array must also be present and non-empty.
## Corrupted or structurally invalid data is treated as no-save.
func _can_resume_from(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var puzzle = data.get("puzzle", null)
	if not (puzzle is Array) or (puzzle as Array).size() != 81:
		push_warning("SudokuSaveAdapter: corrupted save — invalid puzzle array")
		return false
	# Validate cage data for killer saves
	if data.get("is_killer", false):
		var cages = data.get("killer_cages", null)
		if not (cages is Array) or (cages as Array).is_empty():
			push_warning("SudokuSaveAdapter: corrupted killer save — missing cage data")
			return false
	return true
