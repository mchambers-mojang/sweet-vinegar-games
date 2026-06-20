class_name CaromHUD
extends Node

## HUD controller — score labels, ammo display, status text, game-over panel,
## on-screen reload button, Carom settings panel, and debug overlay.

signal rematch_requested
signal menu_requested
signal difficulty_changed(level: int)
signal reload_requested
signal pause_requested
signal resume_requested
signal camera_mode_changed(mode: String)

@onready var player_score_label: Label = %PlayerScoreLabel
@onready var ai_score_label: Label = %AIScoreLabel
@onready var status_label: Label = %StatusLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _overlay_layer: Control = %OverlayLayer

var _game_over_panel: Control = null
var _pause_overlay: Control = null
var _disconnect_overlay: Control = null
var _disconnect_countdown_label: Label = null
var _pause_button: Button = null
var _debug_label: Label = null
var _debug_visible: bool = false
var _touch_debug_draw: Control = null
var _reload_button: CaromReloadButton = null
var _settings_panel: CaromSettings = null
var _gear_button: Button = null
var _current_camera_mode: String = CaromSettings.CAMERA_MODE_TOP_DOWN

const AI_STATE_NAMES := ["ATTACK", "DEFEND", "RELOAD_PRESSURE", "TRICK_SHOT"]


func _ready() -> void:
	CaromSettings.ensure_loaded()
	_current_camera_mode = CaromSettings.camera_mode
	_create_reload_button()
	_create_pause_button()
	_create_gear_button()
	# Re-apply safe area offsets when the viewport resizes
	get_tree().root.size_changed.connect(_apply_safe_area_offsets)
	_apply_safe_area_offsets.call_deferred()


func update_scores(player_score: int, ai_score: int) -> void:
	player_score_label.text = "%d" % player_score
	ai_score_label.text = "%d" % ai_score


func update_status(text: String) -> void:
	status_label.text = text


## Update the match-timer label.
## `ticks_remaining` is the raw tick count from SimWorld; pass 0 with
## `is_sudden_death = true` to switch the label to "SUDDEN DEATH" mode.
## The final 10 seconds are highlighted in red as an urgency cue.
func update_timer(ticks_remaining: int, is_sudden_death: bool) -> void:
	if is_sudden_death:
		_timer_label.text = "SUDDEN DEATH"
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.1))
		return
	var seconds: int = ticks_remaining / SimWorld.TICKS_PER_SECOND
	var minutes: int = seconds / 60
	var secs: int = seconds % 60
	_timer_label.text = "%d:%02d" % [minutes, secs]
	if seconds <= 10:
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	else:
		_timer_label.remove_theme_color_override("font_color")


func update_player_ammo(current_ammo: int, max_ammo: int, is_reloading: bool) -> void:
	if _reload_button:
		_reload_button.update_ammo(current_ammo, max_ammo, is_reloading)


func update_ai_ammo(_current_ammo: int, _max_ammo: int, _is_reloading: bool) -> void:
	pass


func show_game_over(winner: String, player_score: int, ai_score: int, current_difficulty: int) -> void:
	if _game_over_panel:
		_game_over_panel.queue_free()

	_game_over_panel = PanelContainer.new()
	_game_over_panel.custom_minimum_size = Vector2(280, 240)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_color = Color(0.2, 0.8, 1.0, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	_game_over_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	_game_over_panel.add_child(vbox)

	var winner_label := Label.new()
	winner_label.text = "%s Wins!" % winner
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_label.add_theme_font_size_override("font_size", 28)
	winner_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
	vbox.add_child(winner_label)

	var score_text := Label.new()
	score_text.text = "%d – %d" % [player_score, ai_score]
	score_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_text.add_theme_font_size_override("font_size", 22)
	vbox.add_child(score_text)

	# Difficulty selector
	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(diff_row)

	var diff_label := Label.new()
	diff_label.text = "Difficulty: "
	diff_row.add_child(diff_label)

	var diff_picker := OptionButton.new()
	diff_picker.add_item("Easy")
	diff_picker.add_item("Medium")
	diff_picker.add_item("Hard")
	diff_picker.add_item("Brutal")
	diff_picker.selected = current_difficulty
	diff_picker.item_selected.connect(func(idx: int) -> void:
		difficulty_changed.emit(idx)
	)
	diff_row.add_child(diff_picker)

	# Buttons
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)
	vbox.add_child(button_row)

	var rematch_button := Button.new()
	rematch_button.text = "Rematch"
	rematch_button.custom_minimum_size = Vector2(120, 44)
	rematch_button.pressed.connect(func() -> void:
		_game_over_panel.queue_free()
		_game_over_panel = null
		rematch_requested.emit()
	)
	button_row.add_child(rematch_button)

	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.custom_minimum_size = Vector2(120, 44)
	menu_button.pressed.connect(func() -> void:
		menu_requested.emit()
	)
	button_row.add_child(menu_button)

	# Add to overlay and center using anchors
	_overlay_layer.add_child(_game_over_panel)
	var panel_size := _game_over_panel.custom_minimum_size
	_game_over_panel.anchor_left = 0.5
	_game_over_panel.anchor_top = 0.5
	_game_over_panel.anchor_right = 0.5
	_game_over_panel.anchor_bottom = 0.5
	_game_over_panel.offset_left = -panel_size.x * 0.5
	_game_over_panel.offset_top = -panel_size.y * 0.5
	_game_over_panel.offset_right = panel_size.x * 0.5
	_game_over_panel.offset_bottom = panel_size.y * 0.5


# --- Reload button ---

func _create_reload_button() -> void:
	if CaromSettings.auto_reload:
		return
	_reload_button = CaromReloadButton.new()
	_reload_button.reload_requested.connect(func() -> void:
		reload_requested.emit()
	)
	_overlay_layer.add_child(_reload_button)
	_position_reload_button()


func _position_reload_button() -> void:
	if not _reload_button:
		return
	var insets := SafeAreaManager.get_insets()
	var bottom_inset: float = insets["bottom"]
	var left_inset: float = insets["left"]
	var right_inset: float = insets["right"]
	# Use anchors for positioning — bottom-left or bottom-right
	_reload_button.anchor_top = 1.0
	_reload_button.anchor_bottom = 1.0
	if CaromSettings.reload_button_side == CaromSettings.ReloadButtonSide.LEFT:
		_reload_button.anchor_left = 0.0
		_reload_button.anchor_right = 0.0
		_reload_button.offset_left = 16.0 + left_inset
		_reload_button.offset_top = -210.0 - bottom_inset
		_reload_button.offset_right = 116.0 + left_inset
		_reload_button.offset_bottom = -110.0 - bottom_inset
	else:
		_reload_button.anchor_left = 1.0
		_reload_button.anchor_right = 1.0
		_reload_button.offset_left = -116.0 - right_inset
		_reload_button.offset_top = -210.0 - bottom_inset
		_reload_button.offset_right = -16.0 - right_inset
		_reload_button.offset_bottom = -110.0 - bottom_inset


## Show or hide the reload button based on auto_reload setting.
func _sync_reload_button_visibility() -> void:
	if CaromSettings.auto_reload:
		if _reload_button:
			_reload_button.queue_free()
			_reload_button = null
	else:
		if not _reload_button:
			_create_reload_button()
		else:
			_position_reload_button()


# --- Settings gear button ---

func _create_gear_button() -> void:
	_gear_button = Button.new()
	_gear_button.text = "⚙"
	_gear_button.custom_minimum_size = Vector2(44, 44)
	_gear_button.add_theme_font_size_override("font_size", 22)
	_gear_button.pressed.connect(_toggle_settings_panel)
	_overlay_layer.add_child(_gear_button)
	# Top-right corner via anchors (safe area applied in _apply_safe_area_offsets)
	_gear_button.anchor_left = 1.0
	_gear_button.anchor_right = 1.0
	_gear_button.anchor_top = 0.0
	_gear_button.anchor_bottom = 0.0


func _toggle_settings_panel() -> void:
	if _settings_panel and is_instance_valid(_settings_panel):
		_settings_panel.queue_free()
		_settings_panel = null
		return

	_settings_panel = CaromSettings.new()
	# Center using anchors
	_settings_panel.anchor_left = 0.5
	_settings_panel.anchor_top = 0.5
	_settings_panel.anchor_right = 0.5
	_settings_panel.anchor_bottom = 0.5
	_settings_panel.offset_left = -150.0
	_settings_panel.offset_top = -170.0
	_settings_panel.offset_right = 150.0
	_settings_panel.offset_bottom = 170.0
	_settings_panel.setting_changed.connect(func() -> void:
		_sync_reload_button_visibility()
		if CaromSettings.camera_mode != _current_camera_mode:
			_current_camera_mode = CaromSettings.camera_mode
			camera_mode_changed.emit(_current_camera_mode)
	)
	_settings_panel.closed.connect(func() -> void:
		_settings_panel = null
		_position_reload_button()
	)
	_overlay_layer.add_child(_settings_panel)


# --- Pause button + overlay ---

func _create_pause_button() -> void:
	_pause_button = Button.new()
	_pause_button.text = "⏸"
	_pause_button.custom_minimum_size = Vector2(44, 44)
	_pause_button.size = Vector2(44, 44)
	_pause_button.add_theme_font_size_override("font_size", 20)
	_pause_button.pressed.connect(func() -> void:
		pause_requested.emit()
	)
	_overlay_layer.add_child(_pause_button)


## Applies safe area insets to all overlay buttons so they don't overlap
## the notch, Dynamic Island, or home indicator on mobile devices.
func _apply_safe_area_offsets() -> void:
	var insets := SafeAreaManager.get_insets()
	var top: float = insets["top"]
	var right: float = insets["right"]
	var left: float = insets["left"]

	# Pause button — top-left
	if _pause_button:
		_pause_button.position = Vector2(8.0 + left, 8.0 + top)

	# Gear button — top-right
	if _gear_button:
		_gear_button.offset_left = -52.0 - right
		_gear_button.offset_top = 8.0 + top
		_gear_button.offset_right = -8.0 - right
		_gear_button.offset_bottom = 52.0 + top

	# Reload button respects safe area via _position_reload_button
	_position_reload_button()


func show_pause_overlay() -> void:
	if _pause_overlay:
		return

	_pause_overlay = Control.new()
	_pause_overlay.anchor_right = 1.0
	_pause_overlay.anchor_bottom = 1.0
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dimmer := ColorRect.new()
	dimmer.anchor_right = 1.0
	dimmer.anchor_bottom = 1.0
	dimmer.color = Color(0.0, 0.0, 0.0, 0.6)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.add_child(dimmer)

	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -80.0
	vbox.offset_top = -80.0
	vbox.offset_right = 80.0
	vbox.offset_bottom = 80.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	_pause_overlay.add_child(vbox)

	var paused_label := Label.new()
	paused_label.text = "PAUSED"
	paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paused_label.add_theme_font_size_override("font_size", 32)
	paused_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	vbox.add_child(paused_label)

	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.custom_minimum_size = Vector2(140, 48)
	resume_btn.pressed.connect(func() -> void:
		resume_requested.emit()
	)
	vbox.add_child(resume_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Quit to Menu"
	menu_btn.custom_minimum_size = Vector2(140, 48)
	menu_btn.pressed.connect(func() -> void:
		hide_pause_overlay()
		menu_requested.emit()
	)
	vbox.add_child(menu_btn)

	_overlay_layer.add_child(_pause_overlay)


func hide_pause_overlay() -> void:
	if _pause_overlay:
		_pause_overlay.queue_free()
		_pause_overlay = null


# --- Disconnect overlay ---

func show_disconnect_overlay(message: String = "Opponent disconnected") -> void:
	if _disconnect_overlay:
		return

	_disconnect_overlay = Control.new()
	_disconnect_overlay.anchor_right = 1.0
	_disconnect_overlay.anchor_bottom = 1.0
	_disconnect_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dimmer := ColorRect.new()
	dimmer.anchor_right = 1.0
	dimmer.anchor_bottom = 1.0
	dimmer.color = Color(0.0, 0.0, 0.0, 0.7)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disconnect_overlay.add_child(dimmer)

	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -120.0
	vbox.offset_top = -60.0
	vbox.offset_right = 120.0
	vbox.offset_bottom = 60.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	_disconnect_overlay.add_child(vbox)

	var title_label := Label.new()
	title_label.text = message
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	vbox.add_child(title_label)

	_disconnect_countdown_label = Label.new()
	_disconnect_countdown_label.text = "Waiting to reconnect..."
	_disconnect_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_disconnect_countdown_label.add_theme_font_size_override("font_size", 18)
	_disconnect_countdown_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(_disconnect_countdown_label)

	_overlay_layer.add_child(_disconnect_overlay)


func update_disconnect_countdown(seconds_remaining: int) -> void:
	if _disconnect_countdown_label:
		_disconnect_countdown_label.text = "Forfeit in %ds..." % seconds_remaining


func hide_disconnect_overlay() -> void:
	if _disconnect_overlay:
		_disconnect_overlay.queue_free()
		_disconnect_overlay = null
		_disconnect_countdown_label = null


func set_pause_button_visible(visible: bool) -> void:
	if _pause_button:
		_pause_button.visible = visible


# --- Debug overlay ---

func toggle_debug_overlay() -> void:
	_debug_visible = not _debug_visible
	if _debug_visible:
		if not _debug_label:
			_debug_label = Label.new()
			_debug_label.position = Vector2(10, 10)
			_debug_label.add_theme_font_size_override("font_size", 14)
			_debug_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.8, 0.9))
			_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
			_debug_label.add_theme_constant_override("shadow_offset_x", 1)
			_debug_label.add_theme_constant_override("shadow_offset_y", 1)
			_overlay_layer.add_child(_debug_label)
		_debug_label.visible = true
		if not _touch_debug_draw:
			_touch_debug_draw = TouchDebugDraw.new()
			_touch_debug_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
			_touch_debug_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_overlay_layer.add_child(_touch_debug_draw)
		_touch_debug_draw.visible = true
	else:
		if _debug_label:
			_debug_label.visible = false
		if _touch_debug_draw:
			_touch_debug_draw.visible = false


func update_debug_overlay(ai_turret: CaromTurret, player_turret: CaromTurret = null) -> void:
	if not _debug_visible:
		return

	# Update touch debug draw from the player turret's input state
	if _touch_debug_draw and player_turret and player_turret.input is CaromHumanInput:
		var human_input := player_turret.input as CaromHumanInput
		_touch_debug_draw.update_touch_state(
			human_input._active_touches,
			human_input.debug_total_input,
			human_input.debug_last_fire
		)

	if not _debug_label:
		return
	if not ai_turret or not ai_turret.ai_controller:
		_debug_label.text = "AI: no controller"
		return

	var ai = ai_turret.ai_controller
	var state_name: String = AI_STATE_NAMES[ai.current_state] if ai.current_state < AI_STATE_NAMES.size() else "UNKNOWN"
	var puck_pos_text := "N/A"
	var puck_vel_text := "N/A"
	if ai.puck:
		puck_pos_text = "%.1f, %.1f" % [ai.puck.global_position.x, ai.puck.global_position.z]
		puck_vel_text = "%.1f, %.1f" % [ai._puck_velocity_estimate.x, ai._puck_velocity_estimate.z]

	_debug_label.text = "=== AI DEBUG (F3) ===\n" \
		+ "State: %s\n" % state_name \
		+ "Difficulty: %s\n" % ai.difficulty.difficulty_name \
		+ "Aim offset: %.1f°\n" % ai_turret.aim_offset_degrees \
		+ "Target aim: %.1f°\n" % ai._target_aim_degrees \
		+ "Ammo: %d/%d%s\n" % [ai_turret.current_ammo, ai_turret.clip_size, " (reloading)" if ai_turret.is_reloading else ""] \
		+ "Puck pos: %s\n" % puck_pos_text \
		+ "Puck vel: %s\n" % puck_vel_text \
		+ "Threatening: %s" % str(ai._is_puck_threatening())
