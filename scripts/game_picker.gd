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

const CAROM_UNLOCK_MOUSE_WINDOW_SEC := 1.0
const CAROM_UNLOCK_MOUSE_TAP_COUNT := 5
const CAROM_UNLOCK_TOUCH_WINDOW_SEC := 0.6
const CAROM_UNLOCK_TOUCH_TAP_COUNT := 7

var _carom_mouse_taps: Array[float] = []
var _carom_touch_taps: Array[float] = []


func _ready() -> void:
	sudoku_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(Scenes.SUDOKU_MENU)
	)
	shikaku_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(Scenes.SHIKAKU_MENU)
	)
	blockudoku_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(Scenes.BLOCKUDOKU_MENU)
	)
	if carom_button:
		carom_button.visible = false
		carom_button.pressed.connect(func() -> void:
			if ResourceLoader.exists(Scenes.CAROM_MENU):
				SceneTransition.transition_to(Scenes.CAROM_MENU)
			else:
				push_warning("Carom menu scene is missing: %s" % Scenes.CAROM_MENU)
		)
	settings_button.pressed.connect(func() -> void:
		var SettingsScreen := load("res://scripts/settings_screen.gd")
		SettingsScreen.return_scene = Scenes.GAME_PICKER
		SceneTransition.transition_to(Scenes.SETTINGS)
	)
	achievements_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(Scenes.ACHIEVEMENTS)
	)
	replays_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(Scenes.REPLAYS)
	)
	# Hidden debug trigger: 7 rapid taps on the title area
	title_label.mouse_filter = Control.MOUSE_FILTER_STOP
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_STOP
	title_label.gui_input.connect(_on_title_gui_input)
	subtitle_label.gui_input.connect(_on_title_gui_input)
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())

	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)


func _on_title_gui_input(event: InputEvent) -> void:
	if not _is_title_tap_release(event):
		return

	var is_touch := event is InputEventScreenTouch
	DebugOverlay.register_version_label_tap()
	_register_carom_unlock_tap(Time.get_ticks_msec() / 1000.0, is_touch)


func _is_title_tap_release(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		return not st.pressed
	return false


func _register_carom_unlock_tap(now_sec: float, is_touch: bool) -> void:
	var taps: Array[float] = _carom_touch_taps if is_touch else _carom_mouse_taps
	var window: float = CAROM_UNLOCK_TOUCH_WINDOW_SEC if is_touch else CAROM_UNLOCK_MOUSE_WINDOW_SEC
	var required: int = CAROM_UNLOCK_TOUCH_TAP_COUNT if is_touch else CAROM_UNLOCK_MOUSE_TAP_COUNT

	taps.append(now_sec)
	while taps.size() > 0 and now_sec - taps[0] > window:
		taps.remove_at(0)
	if taps.size() < required:
		return

	taps.clear()
	if carom_button:
		carom_button.visible = true
