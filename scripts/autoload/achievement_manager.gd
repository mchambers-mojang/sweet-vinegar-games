extends Node

## Global achievement tracking with local persistence and event-driven updates.

signal achievement_unlocked(achievement_id: String, definition: Dictionary)
signal platform_unlock_requested(payload: Dictionary)

const SAVE_PATH := "user://achievements.cfg"

const TIER_ORDER := {"Bronze": 0, "Silver": 1, "Gold": 2}

const ACHIEVEMENT_DEFINITIONS := {
	"first_game": {
		"id": "first_game",
		"title": "Getting Started",
		"description": "Play your first game.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"win_10": {
		"id": "win_10",
		"title": "Puzzle Winner",
		"description": "Win 10 games.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 10,
	},
	"win_50": {
		"id": "win_50",
		"title": "Puzzle Veteran",
		"description": "Win 50 games.",
		"tier": "Silver",
		"hidden": true,
		"prerequisite_id": "win_10",
		"reward_type": "",
		"reward_id": "",
		"target_value": 50,
	},
	"win_100": {
		"id": "win_100",
		"title": "Puzzle Legend",
		"description": "Win 100 games.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "win_50",
		"reward_type": "",
		"reward_id": "",
		"target_value": 100,
	},
	"blockudoku_clear_three": {
		"id": "blockudoku_clear_three",
		"title": "Triple Threat",
		"description": "Clear 3 lines or boxes at once in Blockudoku.",
		"tier": "Bronze",
		"hidden": true,
		"prerequisite_id": "",
		"reward_type": "effect",
		"reward_id": "",
		"target_value": 1,
	},
	"sudoku_no_errors": {
		"id": "sudoku_no_errors",
		"title": "Clean Finish",
		"description": "Complete a Sudoku with no errors.",
		"tier": "Silver",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "theme",
		"reward_id": "",
		"target_value": 1,
	},
	"all_modes_session": {
		"id": "all_modes_session",
		"title": "Sampler Session",
		"description": "Use all 3 game modes in one session.",
		"tier": "Bronze",
		"hidden": true,
		"prerequisite_id": "",
		"reward_type": "shape",
		"reward_id": "",
		"target_value": 1,
	},
}

var _progress: Dictionary = {}
var _session_modes: Dictionary = {}
var _toast_layer: CanvasLayer


func _ready() -> void:
	_init_progress_defaults()
	_load_progress()


func track_game_started(mode: String) -> void:
	_increment_progress("first_game", 1)
	if mode != "":
		_session_modes[mode] = true
	if _session_modes.size() >= 3:
		_increment_progress("all_modes_session", 1)
	_save_progress()


func track_game_won(mode: String, metadata: Dictionary = {}) -> void:
	if mode == "":
		return
	_increment_progress("win_10", 1)
	_increment_progress("win_50", 1)
	_increment_progress("win_100", 1)
	if mode == "sudoku" and int(metadata.get("strikes", 0)) == 0:
		_increment_progress("sudoku_no_errors", 1)
	_save_progress()


func track_blockudoku_clear(clear_count: int) -> void:
	if clear_count >= 3:
		_increment_progress("blockudoku_clear_three", 1)
		_save_progress()


func get_achievement_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in ACHIEVEMENT_DEFINITIONS.keys():
		var definition: Dictionary = ACHIEVEMENT_DEFINITIONS[id]
		var progress_entry: Dictionary = _progress.get(id, {})
		var is_visible := _is_visible(id)
		result.append({
			"id": id,
			"title": definition.get("title", ""),
			"description": definition.get("description", ""),
			"tier": definition.get("tier", "Bronze"),
			"hidden": definition.get("hidden", false),
			"is_visible": is_visible,
			"prerequisite_id": definition.get("prerequisite_id", ""),
			"reward_type": definition.get("reward_type", ""),
			"reward_id": definition.get("reward_id", ""),
			"current_value": int(progress_entry.get("current_value", 0)),
			"target_value": int(progress_entry.get("target_value", int(definition.get("target_value", 1)))),
			"unlocked": bool(progress_entry.get("unlocked", false)),
			"unlocked_at": int(progress_entry.get("unlocked_at", 0)),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var tier_a = TIER_ORDER.get(str(a.get("tier", "Bronze")), 0)
		var tier_b = TIER_ORDER.get(str(b.get("tier", "Bronze")), 0)
		if tier_a == tier_b:
			return str(a.get("id", "")) < str(b.get("id", ""))
		return tier_a < tier_b
	)
	return result


func get_platform_unlock_payload(achievement_id: String) -> Dictionary:
	if not ACHIEVEMENT_DEFINITIONS.has(achievement_id):
		return {}
	var definition: Dictionary = ACHIEVEMENT_DEFINITIONS[achievement_id]
	var progress_entry: Dictionary = _progress.get(achievement_id, {})
	if not bool(progress_entry.get("unlocked", false)):
		return {}
	return {
		"id": achievement_id,
		"title": definition.get("title", ""),
		"tier": definition.get("tier", "Bronze"),
		"reward_type": definition.get("reward_type", ""),
		"reward_id": definition.get("reward_id", ""),
		"target_value": int(definition.get("target_value", 1)),
		"unlocked_at": int(progress_entry.get("unlocked_at", 0)),
	}


func _init_progress_defaults() -> void:
	for id in ACHIEVEMENT_DEFINITIONS.keys():
		var definition: Dictionary = ACHIEVEMENT_DEFINITIONS[id]
		_progress[id] = {
			"achievement_id": id,
			"current_value": 0,
			"target_value": int(definition.get("target_value", 1)),
			"unlocked": false,
			"unlocked_at": 0,
		}


func _increment_progress(achievement_id: String, amount: int) -> void:
	if not _progress.has(achievement_id):
		return
	var entry: Dictionary = _progress[achievement_id]
	if bool(entry.get("unlocked", false)):
		return
	var target := int(entry.get("target_value", 1))
	entry["current_value"] = min(int(entry.get("current_value", 0)) + amount, target)
	if int(entry["current_value"]) >= target:
		_unlock_achievement(achievement_id, entry)
	_progress[achievement_id] = entry


func _unlock_achievement(achievement_id: String, entry: Dictionary) -> void:
	entry["unlocked"] = true
	entry["unlocked_at"] = Time.get_unix_time_from_system()
	_progress[achievement_id] = entry
	var definition: Dictionary = ACHIEVEMENT_DEFINITIONS.get(achievement_id, {})
	achievement_unlocked.emit(achievement_id, definition)
	platform_unlock_requested.emit(get_platform_unlock_payload(achievement_id))
	_show_toast(definition)


func _is_visible(achievement_id: String) -> bool:
	var definition: Dictionary = ACHIEVEMENT_DEFINITIONS.get(achievement_id, {})
	if not bool(definition.get("hidden", false)):
		return true
	if bool(_progress.get(achievement_id, {}).get("unlocked", false)):
		return true
	var prereq := str(definition.get("prerequisite_id", ""))
	if prereq == "":
		return false
	return bool(_progress.get(prereq, {}).get("unlocked", false))


func reset_all_progress() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_progress.clear()
	_init_progress_defaults()


func _save_progress() -> void:
	var config := ConfigFile.new()
	for id in _progress.keys():
		var entry: Dictionary = _progress[id]
		config.set_value(id, "current_value", int(entry.get("current_value", 0)))
		config.set_value(id, "target_value", int(entry.get("target_value", 1)))
		config.set_value(id, "unlocked", bool(entry.get("unlocked", false)))
		config.set_value(id, "unlocked_at", int(entry.get("unlocked_at", 0)))
	config.save(SAVE_PATH)


func _load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for id in ACHIEVEMENT_DEFINITIONS.keys():
		var target := int(ACHIEVEMENT_DEFINITIONS[id].get("target_value", 1))
		var current := int(config.get_value(id, "current_value", 0))
		_progress[id] = {
			"achievement_id": id,
			"current_value": clampi(current, 0, target),
			"target_value": target,
			"unlocked": bool(config.get_value(id, "unlocked", false)),
			"unlocked_at": int(config.get_value(id, "unlocked_at", 0)),
		}


func _show_toast(definition: Dictionary) -> void:
	if definition.is_empty():
		return
	var root := get_tree().root
	if root == null:
		return
	if _toast_layer == null or not is_instance_valid(_toast_layer):
		_toast_layer = CanvasLayer.new()
		_toast_layer.layer = 120
		_toast_layer.name = "AchievementToastLayer"
		root.add_child(_toast_layer)

	var label := Label.new()
	label.text = "Achievement Unlocked: %s" % str(definition.get("title", ""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var vp_size := root.get_visible_rect().size
	var safe_top: int = SafeAreaManager.get_insets().get("top", 0)
	var toast_width := minf(420.0, vp_size.x * 0.85)
	label.custom_minimum_size = Vector2(toast_width, 48)
	label.size = Vector2(toast_width, 48)
	label.position = Vector2((vp_size.x - toast_width) * 0.5, safe_top + 24)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.pivot_offset = Vector2(toast_width, 48) / 2.0
	label.scale = Vector2(1.2, 1.2)
	_toast_layer.add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(label, "position:y", label.position.y + 12.0, 3.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(2.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(label.queue_free)
