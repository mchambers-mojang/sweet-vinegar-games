extends GameMenu

## Shikaku main menu — new game, continue, stats, settings

@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var stats_button: Button = %StatsButton
@onready var settings_button: Button = $MarginContainer/VBoxContainer/TopBar/SettingsButton
@onready var size_button: OptionButton = %SizeButton
@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton

const SIZE_OPTIONS := [5, 7, 8, 10, 12, 15]


# --- GameMenu overrides ---

func _get_game_id() -> String:
	return "shikaku"


func _get_display_name() -> String:
	return "Shikaku"


func _get_menu_scene_path() -> String:
	return Scenes.SHIKAKU_MENU


func _get_game_scene_path() -> String:
	return Scenes.SHIKAKU_GAME


func _get_stats_scene_path() -> String:
	return Scenes.SHIKAKU_STATS


func _get_help_topic() -> String:
	return "shikaku"


func _on_menu_ready() -> void:
	size_button.selected = 3  # Default to 10×10


func _start_game() -> void:
	var grid_size: int = SIZE_OPTIONS[size_button.selected]
	_start_new_game_with_size(grid_size)


func _resume_game(data: Dictionary) -> void:
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load(_get_game_scene_path()).instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.resume_game(data)
		queue_free()
	)


func _on_abandon_confirmed() -> void:
	var save_data := GameSaveManager.load_game("shikaku")
	var saved_size: int = save_data.get("width", 10)
	GameStatsManager.increment_counter("shikaku", "abandoned_s%d" % saved_size)
	GameStatsManager.set_counter("shikaku", "current_streak", 0)


# --- Shikaku-specific ---

func _start_new_game_with_size(grid_size: int) -> void:
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load(_get_game_scene_path()).instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.start_new_game(grid_size, grid_size)
		queue_free()
	)
