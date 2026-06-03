class_name NeonRing
extends CanvasLayer

## Screen-space shockwave distortion effect
## Usage: NeonRing.create(parent, world_pos, color, max_radius, duration)

const SHOCKWAVE_SHADER := preload("res://shaders/shockwave.gdshader")

static func create(parent: Node, world_pos: Vector2, _color: Color, max_radius: float = 80.0, duration: float = 0.4, amplitude: float = 1.0) -> void:
	if not SettingsManager.shockwave_enabled:
		return
	var ring := NeonRing.new()
	ring.layer = 100
	parent.add_child(ring)
	ring._setup(parent, world_pos, max_radius, duration, amplitude)


var _rect: ColorRect
var _material: ShaderMaterial
var _duration: float
var _elapsed: float = 0.0
var _max_radius_uv: float
var _center_uv: Vector2
var _amplitude: float


func _setup(parent: Node, world_pos: Vector2, max_radius: float, duration: float, amplitude: float) -> void:
	_duration = duration
	_amplitude = amplitude

	# Convert world position to screen UV (0-1)
	var viewport := get_viewport()
	var vp_size := viewport.get_visible_rect().size
	var ci := parent as CanvasItem
	var screen_pos := ci.get_global_transform_with_canvas() * world_pos
	_center_uv = screen_pos / vp_size
	# Max radius in UV space (use height as reference for aspect-correct radius)
	_max_radius_uv = max_radius / vp_size.y

	_material = ShaderMaterial.new()
	_material.shader = SHOCKWAVE_SHADER
	_material.set_shader_parameter("center", _center_uv)
	_material.set_shader_parameter("radius", 0.0)
	_material.set_shader_parameter("thickness", _max_radius_uv * 0.35)
	_material.set_shader_parameter("intensity", 1.0)
	_material.set_shader_parameter("aspect_ratio", vp_size.x / vp_size.y)

	_rect = ColorRect.new()
	_rect.material = _material
	_rect.position = Vector2.ZERO
	_rect.size = vp_size
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func _process(delta: float) -> void:
	_elapsed += delta
	var t := _elapsed / _duration

	if t >= 1.0:
		queue_free()
		return

	var radius := _max_radius_uv * t
	var intensity := (1.0 - t) * (1.0 - t) * _amplitude  # Quadratic fade scaled by amplitude
	var thickness := _max_radius_uv * 0.25 * (1.0 - t * 0.5)

	_material.set_shader_parameter("radius", radius)
	_material.set_shader_parameter("intensity", intensity)
	_material.set_shader_parameter("thickness", thickness)
