class_name BlockudokuSaveAdapter extends GameSaveAdapter

## Save adapter for Blockudoku.
## Validates the expected schema (board_state Dictionary, available_blocks Array)
## and exposes typed accessors so menus never need to peek into raw save data.


func _get_game_id() -> String:
	return "blockudoku"


## Return the saved score, or 0 if no save.
func get_score() -> int:
	return int(restore().get("score", 0))


## Upgrade save data from an older schema version.
func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	# v0 → v1: no schema changes required; version stamp is added by
	# the adapter on the next save() call.
	return data


## A valid blockudoku save must contain a board_state Dictionary and an
## available_blocks Array.  Corrupted or structurally invalid data is
## treated as no-save.
func _can_resume_from(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var board_state = data.get("board_state", null)
	if not (board_state is Dictionary):
		push_warning("BlockudokuSaveAdapter: corrupted save — missing board_state")
		return false
	var available_blocks = data.get("available_blocks", null)
	if not (available_blocks is Array):
		push_warning("BlockudokuSaveAdapter: corrupted save — missing available_blocks")
		return false
	return true
