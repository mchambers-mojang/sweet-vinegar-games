class_name CaromConnectionOverlay
extends Control

signal back_requested

const STATE_CONNECTING := "connecting"
const STATE_WAITING := "waiting"
const STATE_CONNECTED := "connected"
const STATE_ERROR := "error"
const STATUS_FONT_SIZE: int = 28
const INDICATOR_FONT_SIZE: int = 36
const ACCENT_COLOR := Color(0.2, 1.0, 0.85)
const SUCCESS_COLOR := Color(0.35, 1.0, 0.65)
const ERROR_COLOR := Color(1.0, 0.35, 0.35)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.8)
const INDICATOR_PULSE_SCALE: float = 1.18
const INDICATOR_PULSE_MIN_ALPHA: float = 0.45
const INDICATOR_PULSE_DURATION: float = 0.45

@onready var _margin: MarginContainer = $MarginContainer
@onready var _status_label: Label = $MarginContainer/VBoxContainer/CenterBox/StatusLabel
@onready var _indicator_label: Label = $MarginContainer/VBoxContainer/CenterBox/IndicatorLabel
@onready var _back_button: Button = $MarginContainer/VBoxContainer/BackButton

var _indicator_tween: Tween = null
var _root_window: Window = null


func _ready() -> void:
	hide()
	_root_window = get_tree().root
	_apply_safe_area()
	_root_window.size_changed.connect(_apply_safe_area)

	_status_label.add_theme_font_size_override("font_size", STATUS_FONT_SIZE)
	_status_label.add_theme_color_override("font_color", ACCENT_COLOR)
	_apply_label_shadow(_status_label)

	_indicator_label.add_theme_font_size_override("font_size", INDICATOR_FONT_SIZE)
	_indicator_label.add_theme_color_override("font_color", ACCENT_COLOR)
	_apply_label_shadow(_indicator_label)

	_back_button.custom_minimum_size = Vector2(180.0, 48.0)
	_back_button.pressed.connect(func() -> void:
		back_requested.emit()
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_stop_indicator_tween()
	elif what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_root_window) and _root_window.size_changed.is_connected(_apply_safe_area):
			_root_window.size_changed.disconnect(_apply_safe_area)


func show_status(state: String, message: String = "") -> void:
	var normalized_state := state.to_lower()
	show()
	_stop_indicator_tween()

	_status_label.text = message if message != "" else _default_message(normalized_state)
	_status_label.add_theme_color_override("font_color", _state_color(normalized_state))

	match normalized_state:
		STATE_CONNECTING:
			_indicator_label.visible = true
			_indicator_label.text = "•"
			_back_button.text = "Cancel"
			_start_indicator_pulse()
		STATE_WAITING:
			_indicator_label.visible = false
			_back_button.text = "Cancel"
		STATE_CONNECTED:
			_indicator_label.visible = true
			_indicator_label.text = "•"
			_back_button.text = "Cancel"
			_start_indicator_pulse()
		STATE_ERROR:
			_indicator_label.visible = false
			_back_button.text = "Back to Menu"
		_:
			_indicator_label.visible = false
			_back_button.text = "Back"


func _apply_safe_area() -> void:
	var insets: Dictionary = SafeAreaManager.get_insets()
	_margin.add_theme_constant_override("margin_left", int(insets["left"]))
	_margin.add_theme_constant_override("margin_top", int(insets["top"]))
	_margin.add_theme_constant_override("margin_right", int(insets["right"]))
	_margin.add_theme_constant_override("margin_bottom", int(insets["bottom"]))


func _apply_label_shadow(label: Label) -> void:
	label.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)


func _start_indicator_pulse() -> void:
	_indicator_label.scale = Vector2.ONE
	_indicator_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_indicator_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE).set_loops()
	_indicator_tween.tween_property(
		_indicator_label,
		"scale",
		Vector2(INDICATOR_PULSE_SCALE, INDICATOR_PULSE_SCALE),
		INDICATOR_PULSE_DURATION
	)
	_indicator_tween.parallel().tween_property(
		_indicator_label,
		"modulate:a",
		INDICATOR_PULSE_MIN_ALPHA,
		INDICATOR_PULSE_DURATION
	)
	_indicator_tween.tween_property(_indicator_label, "scale", Vector2.ONE, INDICATOR_PULSE_DURATION)
	_indicator_tween.parallel().tween_property(_indicator_label, "modulate:a", 1.0, INDICATOR_PULSE_DURATION)


func _stop_indicator_tween() -> void:
	if is_instance_valid(_indicator_tween):
		_indicator_tween.kill()
	_indicator_tween = null
	_indicator_label.scale = Vector2.ONE
	_indicator_label.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _default_message(state: String) -> String:
	match state:
		STATE_CONNECTING:
			return "Connecting to server..."
		STATE_WAITING:
			return "Waiting for opponent..."
		STATE_CONNECTED:
			return "Opponent found!"
		STATE_ERROR:
			return "Connection failed"
		_:
			return ""


func _state_color(state: String) -> Color:
	match state:
		STATE_ERROR:
			return ERROR_COLOR
		STATE_CONNECTED:
			return SUCCESS_COLOR
		_:
			return ACCENT_COLOR
