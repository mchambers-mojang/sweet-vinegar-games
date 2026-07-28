class_name SudokuSaveAdapter extends GameSaveAdapter

## Save adapter for Sudoku.
## Validates the expected schema and exposes typed accessors so menus never
## need to peek into raw save data.
## Supports both standard 9×9 (81 cells) and mini 6×6 (36 cells) grid specs.


func _get_game_id() -> String:
	return "sudoku"


## Return the saved difficulty level (0 = Easy … 4 = Evil), or 0 if no save.
func get_difficulty() -> int:
	return int(restore().get("difficulty", 0))


## Return the saved rule set index (0 = Standard, 1 = Anti-Knight, 2 = Anti-King,
## 3 = Killer, 4 = Mini), or 0 if no save.
func get_rule_set() -> int:
	return int(restore().get("rule_set", 0))


## Return the grid spec ID from the save ("standard_9x9" or "mini_6x6").
## Legacy saves without this field return "standard_9x9".
func get_grid_spec_id() -> String:
	return str(restore().get("grid_spec_id", "standard_9x9"))


## Return true when the saved game is a Killer Sudoku.
func get_is_killer() -> bool:
	return bool(restore().get("is_killer", false))


## Upgrade save data from an older schema version.
func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	# v0 → v1: no schema changes required; version stamp is added by
	# the adapter on the next save() call.
	# Legacy saves without grid_spec_id are valid standard_9x9 saves.
	return data


## A valid sudoku save must contain a puzzle array matching the expected cell count.
## Legacy saves with 81 cells and no grid_spec_id are treated as standard_9×9.
## Saves with grid_spec_id must match the cell count for that spec.
## For Killer saves, the cages array must also be present and non-empty.
## Corrupted or structurally invalid data is treated as no-save.
func _can_resume_from(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var puzzle = data.get("puzzle", null)
	if not (puzzle is Array):
		push_warning("SudokuSaveAdapter: corrupted save — puzzle is not an array")
		return false
	var puzzle_size: int = (puzzle as Array).size()

	# Determine the expected cell count from the grid spec id
	var spec_id: String = str(data.get("grid_spec_id", "standard_9x9"))
	var spec := SudokuGridSpec.from_id(spec_id)
	if spec == null:
		push_warning("SudokuSaveAdapter: unknown grid_spec_id '%s' — not resumable" % spec_id)
		return false

	if puzzle_size != spec.cell_count:
		push_warning("SudokuSaveAdapter: corrupted save — puzzle has %d cells, expected %d for '%s'" % [puzzle_size, spec.cell_count, spec_id])
		return false

	# Validate cage data for killer saves
	if data.get("is_killer", false):
		var cages = data.get("killer_cages", null)
		if not (cages is Array) or (cages as Array).is_empty():
			push_warning("SudokuSaveAdapter: corrupted killer save — missing cage data")
			return false
	return true
