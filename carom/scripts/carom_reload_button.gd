class_name CaromReloadButton
extends Control

## On-screen reload button for Carom.
## Draws a circular button with a radial ammo ring (one arc segment per bullet).
## Filled/glowing segment = loaded bullet; dim segment = spent.
## When a bullet reloads (via tween), its segment animates from dim to lit.
## Pulses when ammo is empty to hint at reloading.

signal reload_requested

const BUTTON_RADIUS: float = 38.0
const RING_RADIUS: float = 52.0
const RING_THICKNESS: float = 8.0
## Fraction of the per-segment arc used as a gap between segments.
const GAP_FRACTION: float = 0.15

var current_ammo: int = 8
var max_ammo: int = 8
var is_reloading: bool = false
var reload_rate: float = 0.5

## Per-segment brightness (0.0 = spent, 1.0 = fully loaded).
var _segment_brightness: Array[float] = []
var _is_pressed: bool = false
var _pulse_time: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(120, 120)
	pivot_offset = custom_minimum_size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	_reset_segments()


func _reset_segments() -> void:
	_segment_brightness.resize(max_ammo)
	for i in max_ammo:
		_segment_brightness[i] = 1.0 if i < current_ammo else 0.0


## Called by the HUD whenever ammo state changes (mirrors the label update).
func update_ammo(new_ammo: int, new_max: int, new_is_reloading: bool, rate: float = 0.5) -> void:
	reload_rate = rate
	var old_ammo := current_ammo
	current_ammo = new_ammo

	if new_max != max_ammo:
		max_ammo = new_max
		_reset_segments()
	else:
		max_ammo = new_max
		if new_ammo > old_ammo:
			# Bullet(s) added — animate each one lighting up in sequence.
			for i in range(old_ammo, min(new_ammo, max_ammo)):
				_animate_segment_on(i)
		elif new_ammo < old_ammo:
			# Bullet(s) fired — dim those segments immediately.
			for i in range(new_ammo, min(old_ammo, max_ammo)):
				if i < _segment_brightness.size():
					_segment_brightness[i] = 0.0

	is_reloading = new_is_reloading
	queue_redraw()


func _animate_segment_on(idx: int) -> void:
	if idx < 0 or idx >= max_ammo:
		return
	if idx >= _segment_brightness.size():
		return
	_segment_brightness[idx] = 0.0
	var tween := create_tween()
	# Use a captured copy of idx so the lambda always refers to the correct segment.
	var captured_idx := idx
	var on_update := func(v: float) -> void:
		if captured_idx < _segment_brightness.size():
			_segment_brightness[captured_idx] = v
		queue_redraw()
	tween.tween_method(on_update, 0.0, 1.0, reload_rate * 0.75)


func _process(delta: float) -> void:
	# Pulse glow when empty and not reloading — visual hint to reload.
	if current_ammo <= 0 and not is_reloading:
		_pulse_time += delta * 2.5
		queue_redraw()
	elif _pulse_time != 0.0:
		_pulse_time = 0.0
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5

	# Outer pulse glow when empty.
	if current_ammo <= 0 and not is_reloading:
		var pulse := (sin(_pulse_time) * 0.5 + 0.5)
		draw_circle(center, BUTTON_RADIUS + 8.0 + pulse * 6.0, Color(1.0, 0.3, 0.2, 0.18 * pulse))

	# Press highlight.
	if _is_pressed:
		draw_circle(center, BUTTON_RADIUS + 5.0, Color(0.3, 0.8, 1.0, 0.28))

	# Button background.
	var bg_alpha := 0.88
	var bg_color: Color
	if current_ammo <= 0 and not is_reloading:
		var p := sin(_pulse_time) * 0.5 + 0.5
		bg_color = Color(0.18 + p * 0.12, 0.04, 0.04 + p * 0.04, bg_alpha)
	else:
		bg_color = Color(0.06, 0.10, 0.18, bg_alpha)
	draw_circle(center, BUTTON_RADIUS, bg_color)

	# Button border ring.
	var border_bright := 0.55 + (0.45 if _is_pressed else 0.0)
	draw_arc(center, BUTTON_RADIUS, 0.0, TAU, 64,
		Color(0.2, 0.55 * border_bright, 1.0 * border_bright, 0.7), 1.5, true)

	# "R" label.
	var font := ThemeDB.fallback_font
	var font_size := 22
	var text := "R"
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_pos := center - ts * 0.5 + Vector2(0.0, ts.y * 0.25)
	draw_string(font, label_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(0.85, 0.92, 1.0, 0.92))

	# Radial ammo ring.
	_draw_ammo_ring(center)


func _draw_ammo_ring(center: Vector2) -> void:
	if max_ammo <= 0:
		return

	var arc_per_slot := TAU / float(max_ammo)
	var gap := arc_per_slot * GAP_FRACTION
	var seg := arc_per_slot - gap
	var start_offset := -PI * 0.5  # Top of circle.
	var pts := maxi(6, 32 / max_ammo)

	for i in max_ammo:
		var sa := start_offset + float(i) * arc_per_slot
		var ea := sa + seg
		var b: float = _segment_brightness[i] if i < _segment_brightness.size() else 0.0
		var color := Color(
			0.18 + b * 0.50,
			0.60 + b * 0.35,
			1.0,
			0.25 + b * 0.70
		)
		draw_arc(center, RING_RADIUS, sa, ea, pts, color, RING_THICKNESS, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_is_pressed = true
			queue_redraw()
			get_viewport().set_input_as_handled()
		else:
			if _is_pressed:
				_is_pressed = false
				queue_redraw()
				reload_requested.emit()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_pressed = true
				queue_redraw()
				get_viewport().set_input_as_handled()
			else:
				if _is_pressed:
					_is_pressed = false
					queue_redraw()
					reload_requested.emit()
				get_viewport().set_input_as_handled()
