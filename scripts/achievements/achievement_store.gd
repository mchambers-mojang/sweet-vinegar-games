class_name AchievementStore
extends RefCounted

var save_path: String


func _init(p_save_path: String) -> void:
	save_path = p_save_path


func load_progress() -> Dictionary:
	var progress: Dictionary = {}
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return progress
	for section in config.get_sections():
		if section == "__meta":
			continue
		progress[section] = {
			"achievement_id": section,
			"current_value": int(config.get_value(section, "current_value", 0)),
			"target_value": int(config.get_value(section, "target_value", 1)),
			"unlocked": bool(config.get_value(section, "unlocked", false)),
			"unlocked_at": int(config.get_value(section, "unlocked_at", 0)),
		}
	return progress


func save_progress(progress: Dictionary) -> void:
	var config := ConfigFile.new()
	for id in progress.keys():
		var entry: Dictionary = progress[id]
		config.set_value(id, "current_value", int(entry.get("current_value", 0)))
		config.set_value(id, "target_value", int(entry.get("target_value", 1)))
		config.set_value(id, "unlocked", bool(entry.get("unlocked", false)))
		config.set_value(id, "unlocked_at", int(entry.get("unlocked_at", 0)))
	config.save(save_path)


func clear() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
