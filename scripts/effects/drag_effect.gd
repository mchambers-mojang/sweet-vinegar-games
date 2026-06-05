class_name DragEffect
extends CanvasLayer

## Cosmetic drag effect: water-like ripple + fading ribbon trail.
## Activates on unhandled drag input (when no game element consumes it).
## Register as autoload or add to scene tree.

const RIPPLE_SHADER := preload("res://shaders/water_ripple.gdshader")
const TRAIL_LIFETIME := 0.5
const MAX_TRAIL_POINTS := 30

var _ripple_rect: ColorRect
var _ripple_material: ShaderMaterial
var _trail_points: Array[Dictionary] = []  # {pos: Vector2, time: float, color: Color}
var _trail_canvas: Control
var _dragging := false
var _last_pos := Vector2.ZERO
var _release_time := 0.0  # When drag ended (for fade-out)
var _released := false


static func create(parent: Node) -> DragEffect:
	var effect := DragEffect.new()
	effect.layer = 90
	parent.add_child(effect)
	effect._setup()
	return effect


func _setup() -> void:
	# Ripple distortion overlay
	_ripple_rect = ColorRect.new()
	_ripple_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ripple_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ripple_material = ShaderMaterial.new()
	_ripple_material.shader = RIPPLE_SHADER
	_ripple_material.set_shader_parameter("intensity", 0.0)
	_ripple_material.set_shader_parameter("center", Vector2(0.5, 0.5))
	_ripple_material.set_shader_parameter("velocity", Vector2.ZERO)
	var viewport := get_viewport()
	var vp_size := viewport.get_visible_rect().size
	_ripple_material.set_shader_parameter("aspect_ratio", vp_size.x / vp_size.y)
	_ripple_rect.material = _ripple_material
	add_child(_ripple_rect)

	# Trail drawing canvas
	_trail_canvas = Control.new()
	_trail_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_trail_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trail_canvas.z_index = 50
	add_child(_trail_canvas)
	_trail_canvas.draw.connect(_draw_trail)


func _input(event: InputEvent) -> void:
	if not SettingsManager.particle_effects_enabled:
		return

	var pos := Vector2.ZERO
	var pressed := false
	var released := false

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		pos = st.position
		pressed = st.pressed
		released = not st.pressed
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		pos = sd.position
		_on_drag(pos)
		return
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pos = mb.position
			pressed = mb.pressed
			released = not mb.pressed
	elif event is InputEventMouseMotion:
		if _dragging:
			var mm := event as InputEventMouseMotion
			_on_drag(mm.position)
		return
	else:
		return

	if pressed:
		_dragging = true
		_released = false
		_last_pos = pos
		_update_ripple_center(pos)
		_ripple_material.set_shader_parameter("intensity", 0.8)
		_ripple_material.set_shader_parameter("velocity", Vector2.ZERO)
	elif released:
		_dragging = false
		_released = true
		_release_time = Time.get_ticks_msec() / 1000.0
		_ripple_material.set_shader_parameter("intensity", 0.0)


func _on_drag(pos: Vector2) -> void:
	if not _dragging:
		return
	# Calculate velocity for shader wake direction
	var vp_size := get_viewport().get_visible_rect().size
	var vel := (pos - _last_pos) / vp_size * 60.0  # Scale for visibility
	_ripple_material.set_shader_parameter("velocity", vel)
	_update_ripple_center(pos)
	_last_pos = pos

	# Add trail point
	var trail_color: Color
	if ThemeManager.is_neon:
		trail_color = Color(0.0, 1.2, 1.2, 0.7)
	else:
		trail_color = Color(0.5, 0.7, 1.0, 0.5)
	_trail_points.append({"pos": pos, "time": Time.get_ticks_msec() / 1000.0, "color": trail_color})
	if _trail_points.size() > MAX_TRAIL_POINTS:
		_trail_points.pop_front()
	_trail_canvas.queue_redraw()


func _update_ripple_center(pos: Vector2) -> void:
	var vp_size := get_viewport().get_visible_rect().size
	_ripple_material.set_shader_parameter("center", pos / vp_size)


func _process(_delta: float) -> void:
	# Fade out old trail points
	var now := Time.get_ticks_msec() / 1000.0
	var changed := false
	while _trail_points.size() > 0 and (now - _trail_points[0]["time"]) > TRAIL_LIFETIME:
		_trail_points.pop_front()
		changed = true
	if changed or (_released and _trail_points.size() > 0):
		_trail_canvas.queue_redraw()


func _draw_trail() -> void:
	if _trail_points.size() < 2:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var total_points := _trail_points.size()

	# On release, apply a uniform fade-out over 0.3s
	var release_fade := 1.0
	if _released:
		var since_release := now - _release_time
		release_fade = clampf(1.0 - since_release / 0.3, 0.0, 1.0)
		if release_fade <= 0.0:
			_trail_points.clear()
			return

	for i in range(1, total_points):
		var p0: Vector2 = _trail_points[i - 1]["pos"]
		var p1: Vector2 = _trail_points[i]["pos"]

		# Position-based alpha: tail (0) fades, head (1) is solid
		var position_alpha := float(i) / float(total_points - 1)

		# Age-based fade for natural decay while dragging
		var age := now - (_trail_points[i]["time"] as float)
		var age_alpha := clampf(1.0 - age / TRAIL_LIFETIME, 0.0, 1.0)

		var alpha := position_alpha * age_alpha * release_fade
		var width := 4.0 * position_alpha * release_fade + 1.0
		var color: Color = _trail_points[i]["color"]
		color.a *= alpha
		_trail_canvas.draw_line(p0, p1, color, width, true)
