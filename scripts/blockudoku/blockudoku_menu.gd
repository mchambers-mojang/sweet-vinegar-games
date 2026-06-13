extends GameMenu

## Blockudoku main menu — new game, continue, stats, settings

@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var stats_button: Button = %StatsButton
@onready var settings_button: Button = $MarginContainer/VBoxContainer/TopBar/SettingsButton
@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton


# --- GameMenu overrides ---

func _on_menu_ready() -> void:
	GameRulesRegistry.register_rules("blockudoku", {
		"pentominoes": true,
		"p_pentomino": false,
		"w_pentomino": false,
		"y_pentomino": false,
		"f_pentomino": false,
		"n_pentomino": false,
		"hexominoes": false,
		"diagonals": false,
		"drag_offset": 1,
		"rotation_mode": false,
	})

func _get_game_id() -> String:
	return "blockudoku"


func _get_display_name() -> String:
	return "Blockudoku"


func _get_menu_scene_path() -> String:
	return "res://scenes/blockudoku_menu.tscn"


func _get_game_scene_path() -> String:
	return "res://scenes/blockudoku_game.tscn"


func _get_stats_scene_path() -> String:
	return "res://scenes/blockudoku_stats.tscn"


func _get_help_topic() -> String:
	return "blockudoku"


func _start_game() -> void:
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load(_get_game_scene_path()).instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.start_new_game()
		queue_free()
	)


func _resume_game(data: Dictionary) -> void:
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load(_get_game_scene_path()).instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.resume_game(data)
		queue_free()
	)

