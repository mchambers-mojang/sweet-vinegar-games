extends Node

## Unified save manager for all Games in the Collection.
## Stores opaque Dictionary blobs keyed by game_id.
## Uses a single ConfigFile with one section per game.

const SAVE_PATH := "user://game_saves.cfg"

signal game_saved(game_id: String)
signal game_loaded(game_id: String)
signal game_cleared(game_id: String)


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
