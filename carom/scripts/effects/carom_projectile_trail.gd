class_name CaromProjectileTrail
extends MeshInstance3D

## 3D ribbon trail that follows a projectile.
## On projectile destruction, orphans itself and fades out over FADE_DURATION.

const MAX_POINTS: int = 16
const MIN_SEGMENT_DISTANCE: float = 0.15
const TRAIL_WIDTH: float = 0.05
const FADE_DURATION: float = 0.3

var _points: Array[Vector3] = []
var _color: Color = Color(0.16, 0.95, 1.0)
var _fading: bool = false
var _fade_timer: float = 0.0
var _target: Node3D = null
var _mesh: ImmediateMesh = null


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	mesh = _mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	material_override = mat


## Attach to a projectile. Call once after instantiation.
func attach(projectile: CaromProjectile, color: Color) -> void:
	_target = projectile
	_color = color
	_points.clear()
	# Start detached from the projectile's scene so we can outlive it
	projectile.get_parent().add_child(self)
	top_level = true


func _process(delta: float) -> void:
	if _fading:
		_fade_timer += delta
		if _fade_timer >= FADE_DURATION:
			queue_free()
			return
		_rebuild_mesh()
		return

	if not is_instance_valid(_target):
		_begin_fade()
		return

	_record_point(_target.global_position)
	_rebuild_mesh()


func _record_point(pos: Vector3) -> void:
	if _points.size() > 0:
		var last := _points[_points.size() - 1]
		if pos.distance_squared_to(last) < MIN_SEGMENT_DISTANCE * MIN_SEGMENT_DISTANCE:
			return
	_points.append(pos)
	if _points.size() > MAX_POINTS:
		_points.pop_front()


func _begin_fade() -> void:
	_fading = true
	_fade_timer = 0.0


func _rebuild_mesh() -> void:
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return

	var fade_alpha := 1.0
	if _fading:
		fade_alpha = clampf(1.0 - _fade_timer / FADE_DURATION, 0.0, 1.0)

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	var point_count := _points.size()
	for i in point_count:
		var pos := _points[i]
		var t := float(i) / float(point_count - 1)  # 0=tail, 1=head

		# Width tapers toward tail
		var width := TRAIL_WIDTH * t

		# Alpha: position-based fade + overall fade during destruction
		var alpha := t * fade_alpha
		var color := Color(_color.r, _color.g, _color.b, alpha)

		# Get perpendicular direction (use camera up as cross reference)
		var forward: Vector3
		if i < point_count - 1:
			forward = (_points[i + 1] - pos).normalized()
		else:
			forward = (pos - _points[i - 1]).normalized()

		var right := forward.cross(Vector3.UP).normalized() * width

		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(pos + right)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(pos - right)

	_mesh.surface_end()
