class_name GameSaveAdapter extends RefCounted

## Base class for per-game save adapters.
## Each adapter owns its own ConfigFile I/O, format versioning, and schema
## migration for a single game section.  There is no GameSaveManager
## intermediary — all reads and writes go directly through ConfigFile.
##
## Subclasses must override _get_game_id() and may override _can_resume_from()
## to add game-specific resume-eligibility checks (e.g. skip completed saves,
## validate schema on load), and _migrate() to upgrade saved data from older
## schema versions.
##
## Usage:
##   var adapter := SudokuSaveAdapter.new()
##   if adapter.can_resume():
##       game_screen.resume_game(adapter.restore())
##   adapter.save(state)
##   adapter.clear()

## Internal key used to stamp the version into each saved section.
## Stripped from Dictionaries returned to callers so they never see it.
const VERSION_KEY := "_version"


## Return the game_id used for saves (e.g. "sudoku", "shikaku").
## Must be overridden in every concrete subclass.
func _get_game_id() -> String:
	return ""


## Return the current save-format version for this adapter.
## Override in a concrete subclass when bumping the schema version so that
## _load_raw() and save() dispatch to the subclass value at runtime.
## (GDScript constants are resolved at parse-time to the declaring class, so
## a const on the base would not reflect a const on the subclass.)
func _get_save_version() -> int:
	return 1


## Returns true if there is any persisted data for this game.
func has_save() -> bool:
	var config := ConfigFile.new()
	var err := config.load(GameSaveManager.save_path)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			push_warning("GameSaveAdapter: could not read save file (error %d)" % err)
		return false
	return config.has_section(_get_game_id())


## Returns true if the saved state represents an in-progress game that
## can be resumed.  Falls through to _can_resume_from() for game-specific
## logic (schema validation, completed-state check, etc.).
func can_resume() -> bool:
	if not has_save():
		return false
	return _can_resume_from(_load_raw())


## Persist game state to disk with a version stamp.
func save(state: Dictionary) -> void:
	var config := ConfigFile.new()
	# ERR_FILE_NOT_FOUND is expected and safe on first save; all other errors
	# are silently ignored because we are about to overwrite the file anyway.
	config.load(GameSaveManager.save_path)
	var game_id := _get_game_id()
	if config.has_section(game_id):
		config.erase_section(game_id)
	config.set_value(game_id, VERSION_KEY, _get_save_version())
	for key in state.keys():
		config.set_value(game_id, str(key), state[key])
	config.save(GameSaveManager.save_path)


## Load and return the persisted game state.  Returns {} if none exists or
## if the save is corrupted beyond recovery.  Applies _migrate() when the
## saved version is older than _get_save_version().
func restore() -> Dictionary:
	return _load_raw()


## Remove the persisted game state.
func clear() -> void:
	var config := ConfigFile.new()
	if config.load(GameSaveManager.save_path) != OK:
		return
	var game_id := _get_game_id()
	if config.has_section(game_id):
		config.erase_section(game_id)
		config.save(GameSaveManager.save_path)


## Override to inspect the raw save data and decide whether the game is
## resumable.  Default: any non-empty save is resumable.
## Note: data may be empty even when has_save() was true if the save file
## was corrupted and could not be parsed.
func _can_resume_from(_data: Dictionary) -> bool:
	return true


## Override to upgrade save data from an older schema version.
## Receives the data dict (VERSION_KEY already stripped) and the version it
## was saved under.  Must return the migrated Dictionary.
## Default implementation is a no-op (forward-compatible with v1 baseline).
func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	return data


## Load and validate in a single step.  Returns the save data when the save
## exists and passes validation, or {} otherwise.  Use this in auto-resume
## paths to avoid reading the save file twice (once to validate, once to load).
func restore_if_resumable() -> Dictionary:
	if not has_save():
		return {}
	var data := _load_raw()
	if not _can_resume_from(data):
		return {}
	return data


## Internal: read ConfigFile section, strip version stamp, apply migration.
func _load_raw() -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(GameSaveManager.save_path)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			push_warning("GameSaveAdapter: could not read save file (error %d) — treating as no save" % err)
		return {}
	var game_id := _get_game_id()
	if not config.has_section(game_id):
		return {}
	var data: Dictionary = {}
	for key in config.get_section_keys(game_id):
		data[key] = config.get_value(game_id, key)
	var saved_version := int(data.get(VERSION_KEY, 0))
	data.erase(VERSION_KEY)
	if saved_version < _get_save_version():
		data = _migrate(data, saved_version)
	return data
