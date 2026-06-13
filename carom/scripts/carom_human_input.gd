class_name CaromHumanInput
extends CaromTurretInput

## Human input provider — reads keyboard, mouse, and touch to produce turret commands.

var _aim_target: float = 0.0
var _fire_requested: bool = false
var _reload_requested: bool = false
var _touch_drag_sensitivity: float = 0.12


func process(delta: float, turret_state: Dictionary) -> Dictionary:
	var aim_arc: float = turret_state.get("aim_arc", 160.0)
	var aim_speed: float = turret_state.get("aim_speed", 110.0)

	# Keyboard aim
	var horizontal_input := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	if absf(horizontal_input) > 0.0:
		_aim_target = clampf(
			_aim_target - horizontal_input * aim_speed * delta,
			-aim_arc * 0.5,
			aim_arc * 0.5
		)

	# Keyboard fire
	var fire := _fire_requested
	_fire_requested = false

	if Input.is_action_just_pressed("ui_accept"):
		fire = true

	# Keyboard reload
	var reload := _reload_requested
	_reload_requested = false

	if InputMap.has_action("reload"):
		if Input.is_action_just_pressed("reload"):
			reload = true

	return {
		"aim_target": _aim_target,
		"fire": fire,
		"start_reload": reload,
		"cancel_reload": false,
	}


## Called by turret's _unhandled_input for mouse/touch events.
func handle_input_event(event: InputEvent, aim_arc: float) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			_fire_requested = true
	elif event is InputEventScreenTouch:
		var screen_touch := event as InputEventScreenTouch
		if screen_touch.pressed:
			_fire_requested = true
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_aim_target = clampf(
			_aim_target - drag.relative.x * _touch_drag_sensitivity,
			-aim_arc * 0.5,
			aim_arc * 0.5
		)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_R:
			_reload_requested = true
