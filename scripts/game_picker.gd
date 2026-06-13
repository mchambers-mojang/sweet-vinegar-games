extends Control

## Landing screen — choose between Sudoku and Shikaku

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var sudoku_button: Button = %SudokuButton
@onready var shikaku_button: Button = %ShikakuButton
@onready var blockudoku_button: Button = %BlockudokuButton
@onready var carom_button: Button = get_node_or_null("%CaromButton") as Button
@onready var settings_button: Button = %SettingsButton
@onready var replays_button: Button = %ReplaysButton
@onready var achievements_button: Button = %AchievementsButton

const CAROM_UNLOCK_TAP_WINDOW_SEC := 0.8
const CAROM_UNLOCK_TAP_COUNT := 7
const CAROM_MENU_SCENE_PATH := "res://scenes/carom_menu.tscn"

var _carom_unlock_taps: Array[float] = []


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
	if carom_button:
		carom_button.visible = false
		carom_button.pressed.connect(func() -> void:
			if ResourceLoader.exists(CAROM_MENU_SCENE_PATH):
				SceneTransition.transition_to(CAROM_MENU_SCENE_PATH)
			else:
				push_warning("Carom menu scene is missing: %s" % CAROM_MENU_SCENE_PATH)
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
	if not _is_title_tap_release(event):
		return

	DebugOverlay.register_version_label_tap()
	_register_carom_unlock_tap(Time.get_ticks_msec() / 1000.0)


func _is_title_tap_release(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		return not st.pressed
	return false


func _register_carom_unlock_tap(now_sec: float) -> void:
	_carom_unlock_taps.append(now_sec)
	while _carom_unlock_taps.size() > 0 and now_sec - _carom_unlock_taps[0] > CAROM_UNLOCK_TAP_WINDOW_SEC:
		_carom_unlock_taps.remove_at(0)
	if _carom_unlock_taps.size() < CAROM_UNLOCK_TAP_COUNT:
		return

	_carom_unlock_taps.clear()
	if carom_button:
		carom_button.visible = true
