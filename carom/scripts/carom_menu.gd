extends GameMenu

## Carom menu — launches the arena scene with selected difficulty.

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var back_button: Button = %BackButton
@onready var difficulty_button: OptionButton = %DifficultyButton

## Shared state so the arena scene can read the chosen difficulty.
static var selected_difficulty: int = 1


# --- GameMenu overrides ---

func _get_game_id() -> String:
	return "carom"


func _get_menu_scene_path() -> String:
	return "res://scenes/carom_menu.tscn"


func _get_game_scene_path() -> String:
	return "res://carom/scenes/carom_arena.tscn"


func _has_save_support() -> bool:
	return false


func _on_menu_ready() -> void:
	difficulty_button.selected = selected_difficulty
	difficulty_button.item_selected.connect(func(idx: int) -> void:
		selected_difficulty = idx
	)
	play_button.pressed.connect(func() -> void:
		selected_difficulty = difficulty_button.selected
		SceneTransition.transition_to(_get_game_scene_path())
	)

