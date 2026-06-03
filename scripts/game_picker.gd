extends Control

## Landing screen — choose between Sudoku and Shikaku

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var sudoku_button: Button = %SudokuButton
@onready var shikaku_button: Button = %ShikakuButton
@onready var blockudoku_button: Button = %BlockudokuButton
@onready var settings_button: Button = %SettingsButton


func _ready() -> void:
	sudoku_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/main_menu.tscn")
	)
	shikaku_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/shikaku_menu.tscn")
	)
	blockudoku_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/blockudoku_menu.tscn")
	)
	settings_button.pressed.connect(func() -> void:
		var SettingsScreen := load("res://scripts/settings_screen.gd")
		SettingsScreen.return_scene = "res://scenes/game_picker.tscn"
		SceneTransition.transition_to("res://scenes/settings.tscn")
	)
	_apply_theme()
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("background")
	add_theme_stylebox_override("panel", style)
