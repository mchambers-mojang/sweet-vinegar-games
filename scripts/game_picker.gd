extends Control

## Hub — dynamically builds game buttons from GameRegistry.
## To add a new game, create a GameEntry .tres and add it to GameRegistry.ENTRIES;
## this script never needs editing.

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var game_buttons_container: VBoxContainer = %GameButtonsContainer
@onready var settings_button: Button = %SettingsButton
@onready var replays_button: Button = %ReplaysButton
@onready var achievements_button: Button = %AchievementsButton

## Buttons created for each game entry, keyed by entry id.
var _game_buttons: Dictionary = {}

## Per-entry tap timestamps for "secret_tap" unlock, keyed by entry id.
var _mouse_taps: Dictionary = {}
var _touch_taps: Dictionary = {}


func _ready() -> void:
	# Redirect to first-boot name prompt before showing the Hub.
	if not PlayerIdentity.is_setup_complete:
		SceneTransition.navigate(Scenes.NAME_PROMPT)
		return

	_build_game_buttons()

	settings_button.pressed.connect(func() -> void:
		var SettingsScreen := load("res://scripts/settings_screen.gd")
		SettingsScreen.return_scene = Scenes.GAME_PICKER
		SceneTransition.push(Scenes.SETTINGS)
	)
	achievements_button.pressed.connect(func() -> void:
		SceneTransition.navigate(Scenes.ACHIEVEMENTS)
	)
	replays_button.pressed.connect(func() -> void:
		SceneTransition.navigate(Scenes.REPLAYS)
	)
	# Hidden debug trigger: taps on the title area reveal secret entries.
	title_label.mouse_filter = Control.MOUSE_FILTER_STOP
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_STOP
	title_label.gui_input.connect(_on_title_gui_input)
	subtitle_label.gui_input.connect(_on_title_gui_input)
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


func _build_game_buttons() -> void:
	for entry: GameEntry in GameRegistry.ENTRIES:
		var btn := Button.new()
		btn.text = entry.title
		btn.custom_minimum_size = Vector2(0, 60)
		btn.layout_mode = 2
		btn.visible = entry.unlock_rule != "secret_tap"
		btn.pressed.connect(func() -> void:
			if ResourceLoader.exists(entry.menu_scene_path):
				SceneTransition.navigate(entry.menu_scene_path)
			else:
				push_warning("Game menu scene is missing: %s" % entry.menu_scene_path)
		)
		game_buttons_container.add_child(btn)
		_game_buttons[entry.id] = btn
		if entry.unlock_rule == "secret_tap":
			_mouse_taps[entry.id] = []
			_touch_taps[entry.id] = []


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)


func _on_title_gui_input(event: InputEvent) -> void:
	if not _is_title_tap_release(event):
		return
	var is_touch := event is InputEventScreenTouch
	DebugOverlay.register_version_label_tap()
	_handle_unlock_taps(Time.get_ticks_msec() / 1000.0, is_touch)


func _is_title_tap_release(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		return not st.pressed
	return false


func _handle_unlock_taps(now_sec: float, is_touch: bool) -> void:
	for entry: GameEntry in GameRegistry.ENTRIES:
		if entry.unlock_rule == "secret_tap":
			_register_secret_tap(entry, now_sec, is_touch)


func _register_secret_tap(entry: GameEntry, now_sec: float, is_touch: bool) -> void:
	var taps: Array = _touch_taps[entry.id] if is_touch else _mouse_taps[entry.id]
	var window: float = entry.tap_touch_window_sec if is_touch else entry.tap_mouse_window_sec
	var required: int = entry.tap_touch_count if is_touch else entry.tap_mouse_count

	taps.append(now_sec)
	while taps.size() > 0 and now_sec - taps[0] > window:
		taps.remove_at(0)
	if taps.size() < required:
		return

	taps.clear()
	var btn := _game_buttons.get(entry.id) as Button
	if btn:
		btn.visible = true
