extends Control

## Landing screen — choose between Sudoku and Shikaku

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var sudoku_button: Button = %SudokuButton
@onready var shikaku_button: Button = %ShikakuButton
@onready var blockudoku_button: Button = %BlockudokuButton
@onready var settings_button: Button = %SettingsButton
@onready var achievements_button: Button = %AchievementsButton
@onready var version_label: Label = %VersionLabel


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
	achievements_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/achievements.tscn")
	)
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "dev")
	version_label.gui_input.connect(_on_version_label_gui_input)
	_apply_theme()
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_theme())

	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("background")
	add_theme_stylebox_override("panel", style)


func _on_version_label_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			DebugOverlay.register_version_label_tap()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if not st.pressed:
			DebugOverlay.register_version_label_tap()
