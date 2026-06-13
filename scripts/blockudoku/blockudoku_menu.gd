extends Control

## Blockudoku main menu — new game, continue, stats, settings

@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var stats_button: Button = %StatsButton
@onready var settings_button: Button = %SettingsButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	continue_button.pressed.connect(_on_continue)
	new_game_button.pressed.connect(_on_new_game)
	stats_button.pressed.connect(_on_stats)
	settings_button.pressed.connect(_on_settings)
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/game_picker.tscn")
	)

	continue_button.visible = BlockudokuSaveManager.has_saved_game()
	_add_how_to_play_button()
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())

	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)


func _add_how_to_play_button() -> void:
	var btn := Button.new()
	btn.text = "How to Play"
	btn.custom_minimum_size = Vector2(0, 50)
	btn.pressed.connect(func() -> void: HowToPlay.show_for(self, "blockudoku"))
	settings_button.get_parent().add_child(btn)
	settings_button.get_parent().move_child(btn, settings_button.get_index())


func _on_continue() -> void:
	var data := BlockudokuSaveManager.load_game()
	if data.is_empty():
		return
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load("res://scenes/blockudoku_game.tscn").instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.resume_game(data)
		queue_free()
	)


func _on_new_game() -> void:
	if BlockudokuSaveManager.has_saved_game():
		_confirm_abandon()
	else:
		_start_game()


func _confirm_abandon() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Abandon Game?"
	dialog.dialog_text = "Starting a new game will abandon\nyour current game."
	dialog.ok_button_text = "Start New"
	dialog.cancel_button_text = "Cancel"
	dialog.min_size = Vector2i(300, 0)
	dialog.size = Vector2i(300, 0)
	add_child(dialog)
	dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		BlockudokuSaveManager.clear_save()
		dialog.queue_free()
		_start_game()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())


func _start_game() -> void:
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load("res://scenes/blockudoku_game.tscn").instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.start_new_game()
		queue_free()
	)


func _on_stats() -> void:
	SceneTransition.transition_to("res://scenes/blockudoku_stats.tscn")


func _on_settings() -> void:
	var SettingsScreen := load("res://scripts/settings_screen.gd")
	SettingsScreen.return_scene = "res://scenes/blockudoku_menu.tscn"
	SceneTransition.transition_to("res://scenes/settings.tscn")


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)
