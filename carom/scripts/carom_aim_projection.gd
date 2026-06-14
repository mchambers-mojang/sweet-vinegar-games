class_name CaromAimProjection
extends MeshInstance3D

## Draws a distance-limited aim projection with wall ricochets.

@export var wall_collision_mask: int = 2
@export var max_bounces: int = 6
@export var line_color: Color = Color(0.16, 0.95, 1.0, 0.55)

const RICOCHET_OFFSET: float = 0.02

var max_distance: float = 0.0
var _immediate_mesh: ImmediateMesh = ImmediateMesh.new()
var _material: StandardMaterial3D = StandardMaterial3D.new()


func _ready() -> void:
	mesh = _immediate_mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.emission_enabled = true
	_material.emission = Color(line_color.r, line_color.g, line_color.b)
	_material.emission_energy_multiplier = 1.0
	material_override = _material
	visible = false


func set_max_distance(distance: float) -> void:
	max_distance = maxf(0.0, distance)
	if max_distance <= 0.0:
		_clear_projection()


func update_projection(origin_global: Vector3, direction_global: Vector3) -> void:
	if max_distance <= 0.0:
		_clear_projection()
		return

	if direction_global.length_squared() <= 0.0:
		_clear_projection()
		return
	var direction := direction_global.normalized()

	var points: Array[Vector3] = [to_local(origin_global)]
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var current_origin := origin_global
	var remaining_distance := max_distance
	var bounces := 0

	while remaining_distance > 0.0:
		if bounces >= max_bounces:
			points.append(to_local(current_origin + direction * remaining_distance))
			break

		var end_point := current_origin + direction * remaining_distance
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(current_origin, end_point, wall_collision_mask)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit: Dictionary = space_state.intersect_ray(query)

		if hit.is_empty():
			points.append(to_local(end_point))
			remaining_distance = 0.0
			break

		var hit_position := hit.get("position", end_point) as Vector3
		var hit_normal := hit.get("normal", Vector3.UP) as Vector3
		points.append(to_local(hit_position))

		var traveled := current_origin.distance_to(hit_position)
		remaining_distance = maxf(0.0, remaining_distance - traveled)
		if remaining_distance <= 0.0:
			break

		var bounced_direction := direction.bounce(hit_normal)
		if bounced_direction.length_squared() <= 0.0:
			break
		direction = bounced_direction.normalized()

		current_origin = hit_position + direction * RICOCHET_OFFSET
		bounces += 1

	_draw_projection(points)


func _draw_projection(points: Array[Vector3]) -> void:
	_immediate_mesh.clear_surfaces()
	if points.size() < 2:
		visible = false
		return

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _material)
	var max_index := points.size() - 1
	for i in points.size():
		var t := float(i) / float(max_index)
		var alpha := lerpf(line_color.a, 0.0, t)
		_immediate_mesh.surface_set_color(Color(line_color.r, line_color.g, line_color.b, alpha))
		_immediate_mesh.surface_add_vertex(points[i])
	_immediate_mesh.surface_end()
	visible = true


func _clear_projection() -> void:
	_immediate_mesh.clear_surfaces()
	visible = false
