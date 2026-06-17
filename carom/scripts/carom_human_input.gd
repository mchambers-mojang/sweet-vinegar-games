class_name CaromHumanInput
extends CaromTurretInput

## Human input provider — reads keyboard, mouse, and touch to produce turret commands.
## Supports three aim modes (configured in CaromSettings):
##   Drag      — drag anywhere to aim; tap (< 10 px movement) to fire.
##   HoldZones — hold left/right half of screen to steer; speed scales with
##               distance from center; any tap fires.
##   Gyroscope — device tilt steers aim; tap to fire.
## Multitouch: one dragging finger aims; a second finger tap fires.
## Multiple simultaneous drags are summed (opposing drags cancel out).

## Touch movement below this threshold is treated as a tap (fire trigger).
## Higher on mobile to account for finger imprecision on high-DPI screens.
const TAP_THRESHOLD_PIXELS: float = 24.0
## Drag-to-degrees sensitivity (pixels → degrees of aim offset per frame).
const TOUCH_DRAG_SENSITIVITY: float = 0.12

var _aim_target: float = 0.0
var _fire_requested: bool = false
var _reload_requested: bool = false

## Auto-reload: time remaining before triggering reload after last shot.
const AUTO_RELOAD_DELAY: float = 0.5
var _auto_reload_timer: float = -1.0

## Active touches keyed by finger index.
## Each value: {start_pos: Vector2, current_pos: Vector2, total_movement: float, is_drag: bool}
var _active_touches: Dictionary = {}

## Accumulated horizontal drag pixels from all drag events in the current frame.
## Reset to 0 after being consumed in process().
var _pending_drag_x: float = 0.0

## Debug state — exposed for TouchDebugDraw overlay.
var debug_total_input: float = 0.0
var debug_last_fire: bool = false


func process(delta: float, turret_state: Dictionary) -> Dictionary:
	CaromSettings.ensure_loaded()
	var aim_arc: float = turret_state.get("aim_arc", 160.0)
	var aim_speed: float = turret_state.get("aim_speed", 110.0)
	var aim_mode: int = CaromSettings.aim_mode

	# Keyboard / gamepad aim (works in all aim modes).
	var horizontal_input := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	if absf(horizontal_input) > 0.0:
		_aim_target = clampf(
			_aim_target - horizontal_input * aim_speed * delta,
			-aim_arc * 0.5,
			aim_arc * 0.5
		)

	# Touch aim by mode.
	match aim_mode:
		CaromSettings.AimMode.DRAG:
			# Apply the accumulated drag delta, capped to max aim speed.
			if _pending_drag_x != 0.0:
				var max_delta := aim_speed * delta / TOUCH_DRAG_SENSITIVITY
				var clamped_drag := clampf(_pending_drag_x, -max_delta, max_delta)
				_aim_target = clampf(
					_aim_target - clamped_drag * TOUCH_DRAG_SENSITIVITY,
					-aim_arc * 0.5,
					aim_arc * 0.5
				)

		CaromSettings.AimMode.HOLD_ZONES:
			_process_hold_zones(delta, aim_arc, aim_speed)

		CaromSettings.AimMode.GYROSCOPE:
			_process_gyroscope(delta, aim_arc, aim_speed)

	# Always reset accumulated drag so stale deltas don't bleed into other modes.
	_pending_drag_x = 0.0

	# Keyboard fire.
	var fire := _fire_requested
	_fire_requested = false

	if Input.is_action_just_pressed("ui_accept"):
		fire = true

	# Auto-reload: start countdown when we fire, trigger reload when it expires.
	var is_reloading: bool = turret_state.get("is_reloading", false)
	var current_ammo: int = turret_state.get("ammo", 0)
	var clip_size: int = turret_state.get("clip_size", 8)
	if fire:
		debug_last_fire = true
		# Reset the auto-reload timer on every shot.
		if CaromSettings.auto_reload:
			_auto_reload_timer = AUTO_RELOAD_DELAY
	else:
		debug_last_fire = false

	# Keyboard reload.
	var reload := _reload_requested
	_reload_requested = false

	if InputMap.has_action("reload") and Input.is_action_just_pressed("reload"):
		reload = true

	# Tick auto-reload timer.
	if CaromSettings.auto_reload and _auto_reload_timer > 0.0:
		_auto_reload_timer -= delta
		if _auto_reload_timer <= 0.0:
			_auto_reload_timer = -1.0
			if not is_reloading and current_ammo < clip_size:
				reload = true

	return {
		"aim_target": _aim_target,
		"fire": fire,
		"start_reload": reload,
		"cancel_reload": false,
	}


## Called by the turret's _unhandled_input for all mouse/touch/key events.
func handle_input_event(event: InputEvent, _aim_arc: float) -> void:
	CaromSettings.ensure_loaded()
	var aim_mode: int = CaromSettings.aim_mode

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_fire_requested = true

	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_active_touches[touch.index] = {
				"start_pos": touch.position,
				"current_pos": touch.position,
				"total_movement": 0.0,
				"is_drag": false,
			}
		else:
			if _active_touches.has(touch.index):
				var data: Dictionary = _active_touches[touch.index]
				# Tap: total movement below threshold → fire.
				if data["total_movement"] < TAP_THRESHOLD_PIXELS:
					_fire_requested = true
				_active_touches.erase(touch.index)

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _active_touches.has(drag.index):
			var data: Dictionary = _active_touches[drag.index]
			data["current_pos"] = drag.position
			data["total_movement"] += drag.relative.length()
			if data["total_movement"] >= TAP_THRESHOLD_PIXELS:
				data["is_drag"] = true
			_active_touches[drag.index] = data
		# In Drag mode accumulate horizontal delta (all fingers summed).
		if aim_mode == CaromSettings.AimMode.DRAG:
			_pending_drag_x += drag.relative.x

	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_R:
			_reload_requested = true


## Hold Zones: each active touch contributes a turning force proportional to its
## horizontal distance from the screen centre.  Multiple touches are summed and
## clamped to [-1, 1] so opposing drags cancel out.
func _process_hold_zones(delta: float, aim_arc: float, aim_speed: float) -> void:
	if _active_touches.is_empty():
		return
	# Touch positions are in viewport coordinates, so use the viewport size
	# (NOT DisplayServer.window_get_size() which returns physical pixels).
	var viewport_width: float = ProjectSettings.get_setting(
		"display/window/size/viewport_width", 390
	)
	var insets := SafeAreaManager.get_insets()
	var left_inset: float = insets["left"]
	var right_inset: float = insets["right"]
	var usable_width: float = viewport_width - left_inset - right_inset
	var half_usable: float = usable_width * 0.5

	var total_input: float = 0.0
	for data: Dictionary in _active_touches.values():
		var touch_x: float = (data["current_pos"] as Vector2).x
		# Offset by left inset so centre of usable area maps to 0.
		var adjusted_x: float = touch_x - left_inset - half_usable
		total_input += adjusted_x / half_usable

	# Clamp so opposing touches cancel.
	total_input = clampf(total_input, -1.0, 1.0)
	debug_total_input = total_input

	# Negative aim = barrel swings right on screen (matching keyboard convention).
	# Touch right → total_input positive → aim decreases → turns right.
	_aim_target = clampf(
		_aim_target - total_input * aim_speed * delta,
		-aim_arc * 0.5,
		aim_arc * 0.5
	)


## Gyroscope: use the device rotation rate around Y to steer.
## Gracefully skipped when the device is not mobile / gyro not supported.
func _process_gyroscope(delta: float, aim_arc: float, aim_speed: float) -> void:
	if not CaromSettings.is_gyroscope_supported():
		return
	var gyro := Input.get_gyroscope()
	# Y-axis rotation rate in rad/s → deg/s.  On a landscape device this axis
	# corresponds to rolling the phone left/right.
	var rate_dps := rad_to_deg(gyro.y)
	# Scale by aim_speed so the sensitivity feels consistent with other modes.
	var scaled := clampf(rate_dps, -aim_speed, aim_speed)
	_aim_target = clampf(
		_aim_target - scaled * delta,
		-aim_arc * 0.5,
		aim_arc * 0.5
	)
