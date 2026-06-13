extends GameMenu

## Main menu — new game, continue, stats, settings

@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var stats_button: Button = %StatsButton
@onready var settings_button: Button = %SettingsButton
@onready var difficulty_container: VBoxContainer = %DifficultyContainer
@onready var title_label: Label = %TitleLabel
@onready var back_button: Button = %BackButton

const DIFFICULTY_NAMES := ["Easy", "Medium", "Hard", "Expert", "Evil"]

var _showing_difficulty := false


# --- GameMenu overrides ---

func _get_game_id() -> String:
	return "sudoku"


func _get_menu_scene_path() -> String:
	return "res://scenes/main_menu.tscn"


func _get_game_scene_path() -> String:
	return "res://scenes/game.tscn"


func _get_stats_scene_path() -> String:
	return "res://scenes/stats.tscn"


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
	difficulty_container.visible = false
	_setup_difficulty_buttons()


func _apply_game_theme() -> void:
	title_label.add_theme_color_override("font_color", AppTheme.get_color("text_given"))


func _start_game() -> void:
	# After abandon, show difficulty selector
	_showing_difficulty = true
	difficulty_container.visible = true


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


# --- Sudoku-specific: difficulty selector ---

func _on_new_game_pressed() -> void:
	# Override base: toggle difficulty list, only abandon-confirm if save exists
	_showing_difficulty = not _showing_difficulty
	difficulty_container.visible = _showing_difficulty


func _on_difficulty_selected(diff: int) -> void:
	if GameSaveManager.has_saved_game("sudoku"):
		_confirm_abandon_and_start(diff)
	else:
		_start_new_game_with_difficulty(diff)


func _confirm_abandon_and_start(diff: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Abandon Game?"
	dialog.dialog_text = "Starting a new game will abandon\nyour current game and end\nyour streak."
	dialog.ok_button_text = "Start New"
	dialog.cancel_button_text = "Cancel"
	dialog.min_size = Vector2i(300, 0)
	dialog.size = Vector2i(300, 0)
	add_child(dialog)
	dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		_on_abandon_confirmed()
		GameSaveManager.clear_save("sudoku")
		dialog.queue_free()
		_start_new_game_with_difficulty(diff)
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())


func _start_new_game_with_difficulty(diff: int) -> void:
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load(_get_game_scene_path()).instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.start_new_game(diff)
		queue_free()
	)


func _setup_difficulty_buttons() -> void:
	for child in difficulty_container.get_children():
		child.queue_free()

	for i in range(DIFFICULTY_NAMES.size()):
		var btn := Button.new()
		btn.text = DIFFICULTY_NAMES[i]
		btn.custom_minimum_size = Vector2(200, 44)
		var diff := i
		btn.pressed.connect(func() -> void: _on_difficulty_selected(diff))
		difficulty_container.add_child(btn)

