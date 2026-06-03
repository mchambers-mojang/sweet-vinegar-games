extends Node

## Save and resume Shikaku games (independent from Sudoku)

const SAVE_PATH := "user://shikaku_save.cfg"


func has_saved_game() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(data: Dictionary) -> void:
	var config := ConfigFile.new()
	config.set_value("game", "width", data.get("width", 10))
	config.set_value("game", "height", data.get("height", 10))
	config.set_value("game", "numbers", data.get("numbers", {}))
	config.set_value("game", "solution", data.get("solution", []))
	config.set_value("game", "placed_rects", data.get("placed_rects", []))
	config.set_value("game", "elapsed_time", data.get("elapsed_time", 0.0))
	config.set_value("game", "hints_used", data.get("hints_used", 0))
	config.save(SAVE_PATH)


func load_game() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return {}
	return {
		"width": config.get_value("game", "width", 10),
		"height": config.get_value("game", "height", 10),
		"numbers": config.get_value("game", "numbers", {}),
		"solution": config.get_value("game", "solution", []),
		"placed_rects": config.get_value("game", "placed_rects", []),
		"elapsed_time": config.get_value("game", "elapsed_time", 0.0),
		"hints_used": config.get_value("game", "hints_used", 0),
	}


func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
