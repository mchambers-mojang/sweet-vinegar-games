class_name TouchDebugDraw
extends Control

## Debug overlay that visualizes touch input state for Carom.
## Shows: active touch points, tap threshold circles, hold zone center line,
## safe area boundaries, and computed input values.

const TAP_THRESHOLD: float = 24.0
const TOUCH_COLOR := Color(0.2, 1.0, 0.5, 0.7)
const DRAG_COLOR := Color(1.0, 0.6, 0.2, 0.7)
const FIRE_COLOR := Color(1.0, 0.2, 0.2, 0.9)
const ZONE_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const SAFE_AREA_COLOR := Color(1.0, 0.3, 0.3, 0.2)
const TEXT_COLOR := Color(0.9, 0.95, 1.0, 0.9)

var _active_touches: Dictionary = {}
var _last_total_input: float = 0.0
var _last_fire: bool = false
var _fire_flash_timer: float = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	if _fire_flash_timer > 0.0:
		_fire_flash_timer -= delta
	queue_redraw()


func update_touch_state(touches: Dictionary, total_input: float, fired: bool) -> void:
	_active_touches = touches.duplicate(true)
	_last_total_input = total_input
	if fired:
		_last_fire = true
		_fire_flash_timer = 0.15


func _draw() -> void:
	var viewport_width: float = ProjectSettings.get_setting(
		"display/window/size/viewport_width", 390
	)
	var viewport_height: float = ProjectSettings.get_setting(
		"display/window/size/viewport_height", 844
	)
	var insets := SafeAreaManager.get_insets()
	var left: float = insets["left"]
	var right: float = insets["right"]
	var top: float = insets["top"]
	var bottom: float = insets["bottom"]

	# Draw safe area boundaries
	# Top
	draw_rect(Rect2(0, 0, viewport_width, top), SAFE_AREA_COLOR)
	# Bottom
	draw_rect(Rect2(0, viewport_height - bottom, viewport_width, bottom), SAFE_AREA_COLOR)
	# Left
	draw_rect(Rect2(0, top, left, viewport_height - top - bottom), SAFE_AREA_COLOR)
	# Right
	draw_rect(Rect2(viewport_width - right, top, right, viewport_height - top - bottom), SAFE_AREA_COLOR)

	# Draw hold zone center line
	var usable_width: float = viewport_width - left - right
	var center_x: float = left + usable_width * 0.5
	draw_line(
		Vector2(center_x, top),
		Vector2(center_x, viewport_height - bottom),
		ZONE_LINE_COLOR, 2.0
	)

	# Draw "L" and "R" zone labels
	var font := ThemeDB.fallback_font
	var font_size := 18
	draw_string(font, Vector2(left + 10, viewport_height * 0.5), "L",
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ZONE_LINE_COLOR)
	draw_string(font, Vector2(viewport_width - right - 24, viewport_height * 0.5), "R",
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ZONE_LINE_COLOR)

	# Draw active touches
	for data: Dictionary in _active_touches.values():
		var pos: Vector2 = data.get("current_pos", Vector2.ZERO)
		var start_pos: Vector2 = data.get("start_pos", Vector2.ZERO)
		var total_movement: float = data.get("total_movement", 0.0)
		var is_drag: bool = data.get("is_drag", false)

		var color := DRAG_COLOR if is_drag else TOUCH_COLOR

		# Tap threshold circle around start position
		draw_arc(start_pos, TAP_THRESHOLD, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.3), 1.5)

		# Current touch position
		draw_circle(pos, 16.0, color)

		# Line from start to current
		if is_drag:
			draw_line(start_pos, pos, color, 2.0)

		# Movement label
		draw_string(font, pos + Vector2(20, -5), "%.0fpx" % total_movement,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_COLOR)

	# Fire flash
	if _fire_flash_timer > 0.0:
		var flash_alpha: float = _fire_flash_timer / 0.15
		draw_string(font, Vector2(center_x - 20, viewport_height * 0.5 - 30), "FIRE!",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 24, Color(1.0, 0.2, 0.2, flash_alpha))

	# Input bar (shows total_input as a horizontal bar from center)
	var bar_y: float = viewport_height - bottom - 30.0
	var bar_half_width: float = usable_width * 0.4
	# Background
	draw_line(
		Vector2(center_x - bar_half_width, bar_y),
		Vector2(center_x + bar_half_width, bar_y),
		Color(1.0, 1.0, 1.0, 0.2), 4.0
	)
	# Input indicator
	var bar_end_x: float = center_x + _last_total_input * bar_half_width
	var bar_color := Color(0.3, 0.9, 1.0, 0.8)
	draw_line(Vector2(center_x, bar_y), Vector2(bar_end_x, bar_y), bar_color, 4.0)
	draw_circle(Vector2(bar_end_x, bar_y), 6.0, bar_color)
	# Value label
	draw_string(font, Vector2(center_x - 30, bar_y - 10), "input: %.2f" % _last_total_input,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_COLOR)
