extends CanvasLayer

## Cosmetic drag effect: water-like ripple + fading ribbon trail.
## Activates on unhandled drag input (when no game element consumes it).
## Register as autoload or add to scene tree.

const RIPPLE_SHADER := preload("res://shaders/water_ripple.gdshader")
const TRAIL_LIFETIME := 0.5
const MAX_TRAIL_POINTS := 30
const MAX_RINGS := 6
const RING_SPAWN_DISTANCE := 40.0  # Pixels between ring spawns
const RING_LIFETIME := 1.2

const DRAG_THRESHOLD := 20.0  # Pixels of drag before ripple activates

var _ripple_rect: ColorRect
var _ripple_material: ShaderMaterial
var _trail_points: Array[Dictionary] = []
var _trail_canvas: Control
var _dragging := false
var _drag_active := false  # Only true after threshold met
var _last_pos := Vector2.ZERO
var _release_time := 0.0
var _released := false
var _drag_start_pos := Vector2.ZERO

# Ring management
var _rings: Array[Dictionary] = []  # {center_uv: Vector2, spawn_time: float}
var _last_ring_pos := Vector2.ZERO


func _ready() -> void:
	layer = 90
	_setup()


func _setup() -> void:
	# Ripple distortion overlay (hidden until drag starts)
	_ripple_rect = ColorRect.new()
	_ripple_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ripple_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ripple_rect.visible = false
	_ripple_material = ShaderMaterial.new()
	_ripple_material.shader = RIPPLE_SHADER
	var viewport := get_viewport()
	var vp_size := viewport.get_visible_rect().size
	_ripple_material.set_shader_parameter("aspect_ratio", vp_size.x / vp_size.y)
	_ripple_material.set_shader_parameter("viewport_size", vp_size)
	_ripple_material.set_shader_parameter("active_rings", 0)
	_ripple_rect.material = _ripple_material
	add_child(_ripple_rect)

	# Trail drawing canvas (hidden until drag starts)
	_trail_canvas = Control.new()
	_trail_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_trail_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trail_canvas.z_index = 50
	_trail_canvas.visible = false
	add_child(_trail_canvas)
	_trail_canvas.draw.connect(_draw_trail)


var _suppressed := false


## Call to prevent ripple/trail while game elements handle their own drag.
func suppress() -> void:
	_suppressed = true


## Call when game element drag ends to re-enable ripple/trail.
func unsuppress() -> void:
	_suppressed = false


func _input(event: InputEvent) -> void:
	if not PlatformSettings.particle_effects_enabled:
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
		_drag_active = false
		_released = false
		_suppressed = false
		_last_pos = pos
		_drag_start_pos = pos
		_last_ring_pos = pos
	elif released:
		_dragging = false
		_drag_active = false
		_suppressed = false
		_released = true
		_release_time = Time.get_ticks_msec() / 1000.0


func _on_drag(pos: Vector2) -> void:
	if not _dragging or _suppressed:
		return

	# Don't activate until drag exceeds threshold
	if not _drag_active:
		if pos.distance_to(_drag_start_pos) < DRAG_THRESHOLD:
			return
		_drag_active = true
		_last_ring_pos = pos
		_ripple_rect.visible = true
		_trail_canvas.visible = true

	_last_pos = pos

	# Spawn new ring when moved enough distance
	if pos.distance_to(_last_ring_pos) >= RING_SPAWN_DISTANCE:
		_spawn_ring(pos)
		_last_ring_pos = pos

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


func _spawn_ring(pos: Vector2) -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var center_uv := pos / vp_size
	var now := Time.get_ticks_msec() / 1000.0
	_rings.append({"center_uv": center_uv, "spawn_time": now})
	if _rings.size() > MAX_RINGS:
		_rings.pop_front()


func _update_ripple_center(_pos: Vector2) -> void:
	pass  # No longer needed, rings managed separately


func _process(_delta: float) -> void:
	# Expire old rings
	var now := Time.get_ticks_msec() / 1000.0
	while _rings.size() > 0 and (now - _rings[0]["spawn_time"]) > RING_LIFETIME:
		_rings.pop_front()

	# Update shader ring uniforms
	var centers: Array = []
	var ages: Array = []
	for ring in _rings:
		centers.append(ring["center_uv"])
		ages.append(now - ring["spawn_time"])
	# Pad to MAX_RINGS
	while centers.size() < MAX_RINGS:
		centers.append(Vector2.ZERO)
		ages.append(-1.0)

	_ripple_material.set_shader_parameter("ring_centers", centers)
	_ripple_material.set_shader_parameter("ring_ages", ages)
	_ripple_material.set_shader_parameter("active_rings", mini(_rings.size(), MAX_RINGS))

	# Fade out old trail points
	var changed := false
	while _trail_points.size() > 0 and (now - _trail_points[0]["time"]) > TRAIL_LIFETIME:
		_trail_points.pop_front()
		changed = true
	if changed or (_released and _trail_points.size() > 0):
		_trail_canvas.queue_redraw()

	# Hide overlays when nothing is active (saves GPU memory)
	if not _dragging and _rings.size() == 0 and _trail_points.size() == 0:
		if _ripple_rect.visible:
			_ripple_rect.visible = false
			_trail_canvas.visible = false


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
