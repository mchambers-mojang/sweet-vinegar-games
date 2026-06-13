extends GameMenu

## Shikaku main menu — new game, continue, stats, settings

@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var stats_button: Button = %StatsButton
@onready var settings_button: Button = $MarginContainer/VBoxContainer/TopBar/SettingsButton
@onready var size_container: VBoxContainer = %SizeContainer
@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton

const SIZE_OPTIONS := [5, 7, 8, 10, 12, 15]
const SIZE_NAMES := {5: "5×5", 7: "7×7", 8: "8×8", 10: "10×10", 12: "12×12", 15: "15×15"}

var _showing_sizes := false


# --- GameMenu overrides ---

func _get_game_id() -> String:
	return "shikaku"


func _get_display_name() -> String:
	return "Shikaku"


func _get_menu_scene_path() -> String:
	return "res://scenes/shikaku_menu.tscn"


func _get_game_scene_path() -> String:
	return "res://scenes/shikaku_game.tscn"


func _get_stats_scene_path() -> String:
	return "res://scenes/shikaku_stats.tscn"


func _get_help_topic() -> String:
	return "shikaku"


func _on_menu_ready() -> void:
	size_container.visible = false
	_setup_size_buttons()


func _start_game() -> void:
	# After abandon, show size selector instead of starting immediately
	_toggle_sizes()


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


# --- Shikaku-specific: size selector ---

func _on_new_game_pressed() -> void:
	# Override base: toggle size selector instead of immediate start
	if GameSaveManager.has_saved_game("shikaku"):
		if _showing_sizes:
			_toggle_sizes()
			return
		_show_abandon_dialog()
	else:
		_toggle_sizes()


func _toggle_sizes() -> void:
	_showing_sizes = not _showing_sizes
	size_container.visible = _showing_sizes


func _on_size_selected(grid_size: int) -> void:
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load(_get_game_scene_path()).instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.start_new_game(grid_size, grid_size)
		queue_free()
	)


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

