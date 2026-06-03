extends Node

## Save and resume Blockudoku games

const SAVE_PATH := "user://blockudoku_save.cfg"


func has_saved_game() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(data: Dictionary) -> void:
	var config := ConfigFile.new()
	config.set_value("game", "score", data.get("score", 0))
	config.set_value("game", "turns", data.get("turns", 0))
	config.set_value("game", "combo_count", data.get("combo_count", 0))
	config.set_value("game", "elapsed_time", data.get("elapsed_time", 0.0))
	config.set_value("game", "board_state", data.get("board_state", {}))
	config.set_value("game", "available_blocks", data.get("available_blocks", []))
	config.set_value("game", "blocks_placed_this_set", data.get("blocks_placed_this_set", 0))
	config.save(SAVE_PATH)


func load_game() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return {}
	return {
		"score": config.get_value("game", "score", 0),
		"turns": config.get_value("game", "turns", 0),
		"combo_count": config.get_value("game", "combo_count", 0),
		"elapsed_time": config.get_value("game", "elapsed_time", 0.0),
		"board_state": config.get_value("game", "board_state", {}),
		"available_blocks": config.get_value("game", "available_blocks", []),
		"blocks_placed_this_set": config.get_value("game", "blocks_placed_this_set", 0),
	}


func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
