class_name SudokuSaveAdapter extends GameSaveAdapter

## Save adapter for Sudoku.
## Validates the expected schema (81-cell puzzle array) and exposes
## typed accessors so menus never need to peek into raw save data.


func _get_game_id() -> String:
	return "sudoku"


## Return the saved difficulty level (0 = Easy … 4 = Evil), or 0 if no save.
func get_difficulty() -> int:
	return int(restore().get("difficulty", 0))


## Migration callable: upgrade save data from an older schema version.
## Declared static so the Callable does not keep an instance alive unnecessarily.
static func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	# v0 → v1: no schema changes required; version stamp is added by
	# GameSaveManager on the next save_game() call.
	return data


# Registered once per class, not once per instance.
static var _migrator_registered: bool = false

func _init() -> void:
	if _migrator_registered:
		return
	_migrator_registered = true
	GameSaveManager.register_migrator("sudoku", SudokuSaveAdapter._migrate)


## A valid sudoku save must contain a 81-element puzzle array.
## Corrupted or structurally invalid data is treated as no-save.
func _can_resume_from(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var puzzle = data.get("puzzle", null)
	if not (puzzle is Array) or (puzzle as Array).size() != 81:
		push_warning("SudokuSaveAdapter: corrupted save — invalid puzzle array")
		return false
	return true
