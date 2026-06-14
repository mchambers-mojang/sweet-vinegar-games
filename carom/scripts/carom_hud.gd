class_name CaromHUD
extends Node

## HUD controller — score labels, ammo display, status text, game-over panel,
## on-screen reload button, Carom settings panel, and debug overlay.

signal rematch_requested
signal menu_requested
signal difficulty_changed(level: int)
signal reload_requested

@onready var player_score_label: Label = %PlayerScoreLabel
@onready var ai_score_label: Label = %AIScoreLabel
@onready var status_label: Label = %StatusLabel

var _game_over_panel: Control = null
var _debug_label: Label = null
var _debug_visible: bool = false
var _reload_button: CaromReloadButton = null
var _settings_panel: CaromSettings = null
var _gear_button: Button = null

const AI_STATE_NAMES := ["ATTACK", "DEFEND", "RELOAD_PRESSURE", "TRICK_SHOT"]


func _ready() -> void:
	CaromSettings.ensure_loaded()
	_create_reload_button()
	_create_gear_button()


func update_scores(player_score: int, ai_score: int) -> void:
	player_score_label.text = "%d" % player_score
	ai_score_label.text = "%d" % ai_score


func update_status(text: String) -> void:
	status_label.text = text


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

	# Add to parent HUD CanvasLayer and center it
	get_parent().add_child(_game_over_panel)
	var vp_size := get_viewport().get_visible_rect().size
	_game_over_panel.size = _game_over_panel.custom_minimum_size
	_game_over_panel.position = (vp_size - _game_over_panel.size) * 0.5


# --- Reload button ---

func _create_reload_button() -> void:
	_reload_button = CaromReloadButton.new()
	_reload_button.size = _reload_button.custom_minimum_size
	_reload_button.reload_requested.connect(func() -> void:
		reload_requested.emit()
	)
	get_parent().add_child(_reload_button)
	# Defer positioning to ensure viewport has final size
	get_viewport().size_changed.connect(_position_reload_button)
	call_deferred("_position_reload_button")


func _position_reload_button() -> void:
	if not _reload_button:
		return
	var btn_size := _reload_button.custom_minimum_size
	var margin := Vector2(16.0, 24.0)
	var vp_size := get_viewport().get_visible_rect().size
	if CaromSettings.reload_button_side == CaromSettings.ReloadButtonSide.LEFT:
		_reload_button.position = Vector2(margin.x, vp_size.y - btn_size.y - margin.y)
	else:
		_reload_button.position = Vector2(vp_size.x - btn_size.x - margin.x, vp_size.y - btn_size.y - margin.y)


# --- Settings gear button ---

func _create_gear_button() -> void:
	_gear_button = Button.new()
	_gear_button.text = "⚙"
	_gear_button.custom_minimum_size = Vector2(44, 44)
	var vp_size := get_viewport().get_visible_rect().size
	_gear_button.position = Vector2(vp_size.x - 52.0, 8.0)
	_gear_button.add_theme_font_size_override("font_size", 22)
	_gear_button.pressed.connect(_toggle_settings_panel)
	get_parent().add_child(_gear_button)


func _toggle_settings_panel() -> void:
	if _settings_panel and is_instance_valid(_settings_panel):
		_settings_panel.queue_free()
		_settings_panel = null
		return

	_settings_panel = CaromSettings.new()
	var vp_size := get_viewport().get_visible_rect().size
	_settings_panel.position = (vp_size - Vector2(300.0, 240.0)) * 0.5
	_settings_panel.setting_changed.connect(func() -> void:
		_position_reload_button()
	)
	_settings_panel.closed.connect(func() -> void:
		_settings_panel = null
		_position_reload_button()
	)
	get_parent().add_child(_settings_panel)


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
			get_parent().add_child(_debug_label)
		_debug_label.visible = true
	elif _debug_label:
		_debug_label.visible = false


func update_debug_overlay(ai_turret: CaromTurret) -> void:
	if not _debug_visible or not _debug_label:
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
