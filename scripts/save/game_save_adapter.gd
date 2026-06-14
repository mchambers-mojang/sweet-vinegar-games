class_name GameSaveAdapter extends RefCounted

## Base class for per-game save adapters.
## Provides a typed interface over GameSaveManager for a single game.
##
## Subclasses must override _get_game_id() and may override _can_resume_from()
## to add game-specific resume-eligibility checks (e.g. skip completed saves,
## validate schema on load).
##
## Usage:
##   var adapter := SudokuSaveAdapter.new()
##   if adapter.can_resume():
##       game_screen.resume_game(adapter.restore())
##   adapter.save(state)
##   adapter.clear()


## Return the game_id used for saves (e.g. "sudoku", "shikaku").
## Must be overridden in every concrete subclass.
func _get_game_id() -> String:
	return ""


## Returns true if there is any persisted data for this game.
func has_save() -> bool:
	return GameSaveManager.has_saved_game(_get_game_id())


## Returns true if the saved state represents an in-progress game that
## can be resumed.  Falls through to _can_resume_from() for game-specific
## logic (schema validation, completed-state check, etc.).
func can_resume() -> bool:
	if not has_save():
		return false
	return _can_resume_from(GameSaveManager.load_game(_get_game_id()))


## Persist game state to disk.
func save(state: Dictionary) -> void:
	GameSaveManager.save_game(_get_game_id(), state)


## Load and return the persisted game state.  Returns {} if none exists or
## if the save is corrupted beyond recovery.
func restore() -> Dictionary:
	return GameSaveManager.load_game(_get_game_id())


## Remove the persisted game state.
func clear() -> void:
	GameSaveManager.clear_save(_get_game_id())


## Override to inspect the raw save data and decide whether the game is
## resumable.  Default: any non-empty save is resumable.
## Called only when has_save() is true, so data is guaranteed non-empty
## at the GameSaveManager level.
func _can_resume_from(_data: Dictionary) -> bool:
	return true
