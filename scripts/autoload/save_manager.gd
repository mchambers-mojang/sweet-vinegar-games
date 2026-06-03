extends Node

## Save and resume in-progress games

const SAVE_PATH := "user://game_save.cfg"

signal game_loaded
signal game_cleared


func has_saved_game() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(data: Dictionary) -> void:
	var config := ConfigFile.new()
	config.set_value("game", "puzzle", data.get("puzzle", []))
	config.set_value("game", "solution", data.get("solution", []))
	config.set_value("game", "current_grid", data.get("current_grid", []))
	config.set_value("game", "pencil_marks", data.get("pencil_marks", {}))
	config.set_value("game", "cell_colors", data.get("cell_colors", {}))
	config.set_value("game", "difficulty", data.get("difficulty", 0))
	config.set_value("game", "elapsed_time", data.get("elapsed_time", 0.0))
	config.set_value("game", "strikes", data.get("strikes", 0))
	config.set_value("game", "error_mode", data.get("error_mode", "strict"))
	config.set_value("game", "is_failed", data.get("is_failed", false))
	config.set_value("game", "hints_used", data.get("hints_used", 0))
	config.save(SAVE_PATH)


func load_game() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return {}
	var data := {
		"puzzle": config.get_value("game", "puzzle", []),
		"solution": config.get_value("game", "solution", []),
		"current_grid": config.get_value("game", "current_grid", []),
		"pencil_marks": config.get_value("game", "pencil_marks", {}),
		"cell_colors": config.get_value("game", "cell_colors", {}),
		"difficulty": config.get_value("game", "difficulty", 0),
		"elapsed_time": config.get_value("game", "elapsed_time", 0.0),
		"strikes": config.get_value("game", "strikes", 0),
		"error_mode": config.get_value("game", "error_mode", "strict"),
		"is_failed": config.get_value("game", "is_failed", false),
		"hints_used": config.get_value("game", "hints_used", 0),
	}
	game_loaded.emit()
	return data


func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	game_cleared.emit()
