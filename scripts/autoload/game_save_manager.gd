extends Node

## Unified save manager for all Games in the Collection.
## Stores opaque Dictionary blobs keyed by game_id.
## Uses a single ConfigFile with one section per game.
##
## Versioning: every saved section is stamped with VERSION_KEY so that
## schema migrations can be applied transparently on load.
## Corruption recovery: file-level parse failures are caught and logged;
## callers receive an empty Dictionary rather than a crash.
## Migration: per-game callables can be registered via register_migrator()
## (typically called from a GameSaveAdapter._init()).

const SAVE_PATH := "user://game_saves.cfg"

## Current save-format version.  Bump this whenever a schema migration is needed.
const SAVE_VERSION := 1

## Internal key used to stamp the version into each saved section.
## Stripped from Dictionaries returned by load_game() so callers never see it.
const VERSION_KEY := "_version"

# Legacy file paths from the per-game save managers
const _LEGACY_PATHS := {
	"sudoku": "user://game_save.cfg",
	"blockudoku": "user://blockudoku_save.cfg",
	"shikaku": "user://shikaku_save.cfg",
}

# Registered migration callables: game_id -> Callable(data: Dictionary, from_version: int) -> Dictionary
var _migrators: Dictionary = {}

signal game_saved(game_id: String)
signal game_loaded(game_id: String)
signal game_cleared(game_id: String)


func _ready() -> void:
	_migrate_legacy_saves()


## Register a migration callable for game_id.
## The callable receives (data: Dictionary, from_version: int) and must
## return the migrated Dictionary.  Called by GameSaveAdapter subclasses
## from their _init() to keep migration logic close to the schema it owns.
func register_migrator(game_id: String, callable: Callable) -> void:
	_migrators[game_id] = callable


func has_saved_game(game_id: String) -> bool:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			push_warning("GameSaveManager: could not read save file (error %d)" % err)
		return false
	return config.has_section(game_id)


## Persist data for game_id.  A version stamp is added automatically so
## that load_game() can detect stale saves and apply migrations.
func save_game(game_id: String, data: Dictionary) -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)  # OK if file doesn't exist yet
	# Clear previous section to remove stale keys
	if config.has_section(game_id):
		config.erase_section(game_id)
	# Write version stamp first so it is always present
	config.set_value(game_id, VERSION_KEY, SAVE_VERSION)
	for key in data.keys():
		config.set_value(game_id, str(key), data[key])
	config.save(SAVE_PATH)
	game_saved.emit(game_id)


## Load the persisted data for game_id.
## Returns {} if no save exists or if the file cannot be parsed (corruption).
## The internal version stamp is stripped before returning; callers never see it.
## If a migration callable is registered and the saved version is older than
## SAVE_VERSION, the callable is invoked to upgrade the data in-memory.
func load_game(game_id: String) -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			push_warning("GameSaveManager: could not read save file (error %d) — treating as no save" % err)
		return {}
	if not config.has_section(game_id):
		return {}
	var data: Dictionary = {}
	for key in config.get_section_keys(game_id):
		data[key] = config.get_value(game_id, key)
	# Read and strip the internal version stamp
	var saved_version: int = int(data.get(VERSION_KEY, 0))
	data.erase(VERSION_KEY)
	# Apply registered migration if the save is from an older version
	if saved_version < SAVE_VERSION and _migrators.has(game_id):
		data = _migrators[game_id].call(data, saved_version)
	game_loaded.emit(game_id)
	return data


func clear_save(game_id: String) -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		game_cleared.emit(game_id)
		return
	if config.has_section(game_id):
		config.erase_section(game_id)
		config.save(SAVE_PATH)
	game_cleared.emit(game_id)


func clear_all() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## One-time migration: read legacy per-game save files and import into unified file.
func _migrate_legacy_saves() -> void:
	for game_id in _LEGACY_PATHS.keys():
		var legacy_path: String = _LEGACY_PATHS[game_id]
		if not FileAccess.file_exists(legacy_path):
			continue
		# Skip if we already have data for this game
		if has_saved_game(game_id):
			DirAccess.remove_absolute(legacy_path)
			continue
		var config := ConfigFile.new()
		if config.load(legacy_path) != OK:
			continue
		# Old format: all keys under a "game" section
		if not config.has_section("game"):
			DirAccess.remove_absolute(legacy_path)
			continue
		var data := {}
		for key in config.get_section_keys("game"):
			data[key] = config.get_value("game", key)
		if not data.is_empty():
			save_game(game_id, data)
		DirAccess.remove_absolute(legacy_path)
