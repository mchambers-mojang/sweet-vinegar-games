extends GameMenu

## Main menu — new game, continue, stats, settings

@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var stats_button: Button = %StatsButton
@onready var settings_button: Button = $MarginContainer/VBoxContainer/TopBar/SettingsButton
@onready var difficulty_button: OptionButton = %DifficultyButton
@onready var title_label: Label = %TitleLabel
@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton

const DIFFICULTY_NAMES := ["Easy", "Medium", "Hard", "Expert", "Evil"]


# --- GameMenu overrides ---

func _get_game_id() -> String:
	return "sudoku"


func _get_display_name() -> String:
	return "Sudoku"


func _get_menu_scene_path() -> String:
	return Scenes.SUDOKU_MENU


func _get_game_scene_path() -> String:
	return Scenes.SUDOKU_GAME


func _get_stats_scene_path() -> String:
	return Scenes.SUDOKU_STATS


func _get_help_topic() -> String:
	return "sudoku"


func _on_menu_ready() -> void:
	# Defensive registration — handles direct entry (e.g. from replays).
	GameRulesRegistry.register_rules("sudoku", {
		"input_mode": "cell_first",
		"error_mode": "strict",
		"highlight_row_col_box": true,
		"auto_remove_pencil_marks": true,
	})
	difficulty_button.selected = 1


func _apply_game_theme() -> void:
	title_label.add_theme_color_override("font_color", AppTheme.get_color("text_given"))


func _start_game() -> void:
	var diff := difficulty_button.selected
	_start_new_game_with_difficulty(diff)


func _resume_game(data: Dictionary) -> void:
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load(_get_game_scene_path()).instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.resume_game(data)
		queue_free()
	)


func _on_abandon_confirmed() -> void:
	var save_data := GameSaveManager.load_game("sudoku")
	var saved_diff: int = save_data.get("difficulty", 0)
	GameStatsManager.increment_counter("sudoku", "abandoned_d%d" % saved_diff)
	GameStatsManager.set_counter("sudoku", "current_streak", 0)


# --- Sudoku-specific ---

func _start_new_game_with_difficulty(diff: int) -> void:
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load(_get_game_scene_path()).instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.start_new_game(diff)
		queue_free()
	)
