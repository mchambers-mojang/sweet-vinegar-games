class_name CaromMenu
extends GameMenu

## Carom menu — launches the arena scene with selected difficulty.

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var back_button: Button = %BackButton
@onready var difficulty_button: OptionButton = %DifficultyButton

## Last selected difficulty tier (persists display state across menu visits).
var _selected_difficulty: int = 1


# --- GameMenu overrides ---

func _get_game_id() -> String:
	return "carom"


func _get_menu_scene_path() -> String:
	return Scenes.CAROM_MENU


func _get_game_scene_path() -> String:
	return Scenes.CAROM_ARENA


func _has_save_support() -> bool:
	return false


func _on_menu_ready() -> void:
	difficulty_button.selected = _selected_difficulty
	difficulty_button.item_selected.connect(func(idx: int) -> void:
		_selected_difficulty = idx
	)
	play_button.pressed.connect(func() -> void:
		var difficulty := difficulty_button.selected
		SceneTransition.transition_with_callback(func() -> void:
			var arena: Node = load(_get_game_scene_path()).instantiate()
			arena.set_meta("carom_difficulty", difficulty)
			get_tree().root.add_child(arena)
			queue_free()
		)
	)

