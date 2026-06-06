extends Control

## Landing screen — choose between Sudoku and Shikaku

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var sudoku_button: Button = %SudokuButton
@onready var shikaku_button: Button = %ShikakuButton
@onready var blockudoku_button: Button = %BlockudokuButton
@onready var carom_button: Button = %CaromButton
@onready var settings_button: Button = %SettingsButton
@onready var replays_button: Button = %ReplaysButton
@onready var achievements_button: Button = %AchievementsButton


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
	carom_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://carom/scenes/carom_arena.tscn")
	)
	settings_button.pressed.connect(func() -> void:
		var SettingsScreen := load("res://scripts/settings_screen.gd")
		SettingsScreen.return_scene = "res://scenes/game_picker.tscn"
		SceneTransition.transition_to("res://scenes/settings.tscn")
	)
	achievements_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/achievements.tscn")
	)
	replays_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/replays.tscn")
	)
	# Hidden debug trigger: 7 rapid taps on the title
	title_label.mouse_filter = Control.MOUSE_FILTER_STOP
	title_label.gui_input.connect(_on_title_gui_input)
	_apply_theme()
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_theme())

	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("background")
	add_theme_stylebox_override("panel", style)


func _on_title_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			DebugOverlay.register_version_label_tap()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if not st.pressed:
			DebugOverlay.register_version_label_tap()
