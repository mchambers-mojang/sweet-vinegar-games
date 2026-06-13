extends PanelContainer

## Placeholder Carom menu — launches the prototype arena scene.

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var back_button: Button = %BackButton
@onready var difficulty_button: OptionButton = %DifficultyButton

## Shared state so the arena scene can read the chosen difficulty.
static var selected_difficulty: int = 1


func _ready() -> void:
	difficulty_button.selected = selected_difficulty
	difficulty_button.item_selected.connect(func(idx: int) -> void:
		selected_difficulty = idx
	)
	play_button.pressed.connect(func() -> void:
		selected_difficulty = difficulty_button.selected
		SceneTransition.transition_to("res://carom/scenes/carom_arena.tscn")
	)
	settings_button.pressed.connect(func() -> void:
		var SettingsScreen := load("res://scripts/settings_screen.gd")
		SettingsScreen.return_scene = "res://scenes/carom_menu.tscn"
		SceneTransition.transition_to("res://scenes/settings.tscn")
	)
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/game_picker.tscn")
	)
	_apply_theme()
	ThemeManager.theme_changed.connect(func(_is_dark: bool) -> void: _apply_theme())

	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("background")
	add_theme_stylebox_override("panel", style)
