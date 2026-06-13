extends Control

## Shikaku main menu — new game, continue, stats, settings

@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var stats_button: Button = %StatsButton
@onready var settings_button: Button = %SettingsButton
@onready var size_container: VBoxContainer = %SizeContainer
@onready var back_button: Button = %BackButton

const SIZE_OPTIONS := [5, 7, 8, 10, 12, 15]
const SIZE_NAMES := {5: "5×5", 7: "7×7", 8: "8×8", 10: "10×10", 12: "12×12", 15: "15×15"}

var _showing_sizes := false


func _ready() -> void:
	continue_button.pressed.connect(_on_continue)
	new_game_button.pressed.connect(_on_new_game)
	stats_button.pressed.connect(_on_stats)
	settings_button.pressed.connect(_on_settings)
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/game_picker.tscn")
	)

	continue_button.visible = GameSaveManager.has_saved_game("shikaku")
	size_container.visible = false
	_setup_size_buttons()
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
	btn.pressed.connect(func() -> void: HowToPlay.show_for(self, "shikaku"))
	settings_button.get_parent().add_child(btn)
	settings_button.get_parent().move_child(btn, settings_button.get_index())


func _on_continue() -> void:
	var data := GameSaveManager.load_game("shikaku")
	if data.is_empty():
		return
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load("res://scenes/shikaku_game.tscn").instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.resume_game(data)
		queue_free()
	)


func _on_new_game() -> void:
	if GameSaveManager.has_saved_game("shikaku"):
		_confirm_abandon_and_show_sizes()
	else:
		_toggle_sizes()


func _toggle_sizes() -> void:
	_showing_sizes = not _showing_sizes
	size_container.visible = _showing_sizes


func _confirm_abandon_and_show_sizes() -> void:
	if _showing_sizes:
		_toggle_sizes()
		return
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
		var save_data := GameSaveManager.load_game("shikaku")
		var saved_size: int = save_data.get("width", 10)
		GameStatsManager.increment_counter("shikaku", "abandoned_s%d" % saved_size)
		GameStatsManager.set_counter("shikaku", "current_streak", 0)
		GameSaveManager.clear_save("shikaku")
		dialog.queue_free()
		_toggle_sizes()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())


func _on_size_selected(grid_size: int) -> void:
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load("res://scenes/shikaku_game.tscn").instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.start_new_game(grid_size, grid_size)
		queue_free()
	)


func _on_stats() -> void:
	SceneTransition.transition_to("res://scenes/shikaku_stats.tscn")


func _on_settings() -> void:
	var SettingsScreen := load("res://scripts/settings_screen.gd")
	SettingsScreen.return_scene = "res://scenes/shikaku_menu.tscn"
	SceneTransition.transition_to("res://scenes/settings.tscn")


func _setup_size_buttons() -> void:
	for child in size_container.get_children():
		child.queue_free()
	for s in SIZE_OPTIONS:
		var btn := Button.new()
		btn.text = SIZE_NAMES[s]
		btn.custom_minimum_size = Vector2(200, 44)
		var grid_size: int = s
		btn.pressed.connect(func() -> void: _on_size_selected(grid_size))
		size_container.add_child(btn)


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("background")
	add_theme_stylebox_override("panel", style)
