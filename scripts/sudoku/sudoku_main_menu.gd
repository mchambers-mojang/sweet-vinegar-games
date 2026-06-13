extends Control

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


func _ready() -> void:
	continue_button.pressed.connect(_on_continue)
	new_game_button.pressed.connect(_on_new_game)
	stats_button.pressed.connect(_on_stats)
	settings_button.pressed.connect(_on_settings)
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/game_picker.tscn")
	)

	continue_button.visible = GameSaveManager.has_saved_game("sudoku")
	difficulty_container.visible = false

	_setup_difficulty_buttons()
	_add_how_to_play_button()
	_apply_theme()
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_theme())

	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)


func _add_how_to_play_button() -> void:
	var btn := Button.new()
	btn.text = "How to Play"
	btn.custom_minimum_size = Vector2(0, 50)
	btn.pressed.connect(func() -> void: HowToPlay.show_for(self, "sudoku"))
	settings_button.get_parent().add_child(btn)
	settings_button.get_parent().move_child(btn, settings_button.get_index())


func _on_continue() -> void:
	var data := GameSaveManager.load_game("sudoku")
	if data.is_empty():
		return
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load("res://scenes/game.tscn").instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.resume_game(data)
		queue_free()
	)


func _on_new_game() -> void:
	_showing_difficulty = not _showing_difficulty
	difficulty_container.visible = _showing_difficulty


func _on_difficulty_selected(diff: int) -> void:
	if GameSaveManager.has_saved_game("sudoku"):
		_confirm_abandon_and_start(diff)
	else:
		_start_new_game(diff)


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
		var save_data := GameSaveManager.load_game("sudoku")
		var saved_diff: int = save_data.get("difficulty", 0)
		GameStatsManager.increment_counter("sudoku", "abandoned_d%d" % saved_diff)
		GameStatsManager.set_counter("sudoku", "current_streak", 0)
		GameSaveManager.clear_save("sudoku")
		_start_new_game(diff)
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())


func _start_new_game(diff: int) -> void:
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load("res://scenes/game.tscn").instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.start_new_game(diff)
		queue_free()
	)


func _on_stats() -> void:
	SceneTransition.transition_to("res://scenes/stats.tscn")


func _on_settings() -> void:
	var SettingsScreen := load("res://scripts/settings_screen.gd")
	SettingsScreen.return_scene = "res://scenes/main_menu.tscn"
	SceneTransition.transition_to("res://scenes/settings.tscn")


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


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("background")
	add_theme_stylebox_override("panel", style)
	title_label.add_theme_color_override("font_color", ThemeManager.get_color("text_given"))
