extends Node

## Unified save manager for all Games in the Collection.
## Stores opaque Dictionary blobs keyed by game_id.
## Uses a single ConfigFile with one section per game.

const SAVE_PATH := "user://game_saves.cfg"

# Legacy file paths from the per-game save managers
const _LEGACY_PATHS := {
	"sudoku": "user://game_save.cfg",
	"blockudoku": "user://blockudoku_save.cfg",
	"shikaku": "user://shikaku_save.cfg",
}

signal game_saved(game_id: String)
signal game_loaded(game_id: String)
signal game_cleared(game_id: String)


func _ready() -> void:
	_migrate_legacy_saves()


func has_saved_game(game_id: String) -> bool:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return false
	return config.has_section(game_id)


func save_game(game_id: String, data: Dictionary) -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)  # OK if file doesn't exist yet
	# Clear previous section to remove stale keys
	if config.has_section(game_id):
		config.erase_section(game_id)
	for key in data.keys():
		config.set_value(game_id, str(key), data[key])
	config.save(SAVE_PATH)
	game_saved.emit(game_id)


func load_game(game_id: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return {}
	if not config.has_section(game_id):
		return {}
	var data := {}
	for key in config.get_section_keys(game_id):
		data[key] = config.get_value(game_id, key)
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
