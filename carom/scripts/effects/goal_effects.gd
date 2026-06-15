extends RefCounted

const GOAL_BURST_PARTICLE_COUNT: int = 30
const GOAL_BURST_LIFETIME: float = 0.5
const GOAL_BURST_Y_OFFSET: float = 0.12
const GOAL_FRAGMENT_MIN_COUNT: int = 5
const GOAL_FRAGMENT_MAX_COUNT: int = 8
const GOAL_FRAGMENT_LIFETIME: float = 1.0
const GOAL_FRAGMENT_EMISSION_ENERGY: float = 3.5
const GOAL_FRAGMENT_Y_OFFSET: float = 0.14
const GOAL_FRAGMENT_LINEAR_DAMP: float = 2.4
const GOAL_FLARE_EMISSION_ENERGY: float = 5.0
const GOAL_CELEBRATION_LIFETIME: float = 1.2

var _arena: CaromArena = null


func setup(arena: CaromArena) -> void:
	_arena = arena


func play_goal_celebration(
	goal_position: Vector3,
	scoring_side: StringName,
	color: Color,
	goal_puck: CaromPuck = null,
	goal_zone: Area3D = null
) -> Node3D:
	return _spawn_goal_celebration(goal_position, scoring_side, color, goal_puck, goal_zone)


func _spawn_goal_celebration(
	goal_position: Vector3,
	scoring_side: StringName,
	color: Color,
	goal_puck: CaromPuck = null,
	goal_zone: Area3D = null
) -> Node3D:
	if _arena == null:
		return null

	var celebration := Node3D.new()
	celebration.name = "GoalCelebration"
	_arena.add_child(celebration)

	_spawn_radial_burst(celebration, goal_position, color)
	_spawn_puck_fragments(celebration, goal_puck, goal_position, color)
	_spawn_goal_flare(celebration, goal_zone, scoring_side, color)

	var cleanup_tween := celebration.create_tween()
	cleanup_tween.tween_interval(GOAL_CELEBRATION_LIFETIME)
	cleanup_tween.tween_callback(celebration.queue_free)
	return celebration


func _spawn_radial_burst(parent: Node3D, goal_position: Vector3, color: Color) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "Burst"
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = GOAL_BURST_PARTICLE_COUNT
	particles.lifetime = GOAL_BURST_LIFETIME

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 180.0
	process_material.initial_velocity_min = 4.5
	process_material.initial_velocity_max = 8.5
	process_material.gravity = Vector3.ZERO
	process_material.damping_min = 1.5
	process_material.damping_max = 3.0
	process_material.scale_min = 0.03
	process_material.scale_max = 0.08
	process_material.color = Color(color.r, color.g, color.b, 0.95)
	particles.process_material = process_material

	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.035
	spark_mesh.height = 0.07
	particles.draw_pass_1 = spark_mesh
	particles.material_override = _make_emissive_material(color, 4.0, 0.95)

	parent.add_child(particles)
	particles.global_position = goal_position + Vector3(0.0, GOAL_BURST_Y_OFFSET, 0.0)
	particles.emitting = true


func _spawn_puck_fragments(parent: Node3D, goal_puck: CaromPuck, goal_position: Vector3, color: Color) -> void:
	var fragments_root := Node3D.new()
	fragments_root.name = "Fragments"
	parent.add_child(fragments_root)

	var origin := goal_position + Vector3(0.0, GOAL_FRAGMENT_Y_OFFSET, 0.0)
	if is_instance_valid(goal_puck) and goal_puck.is_inside_tree():
		origin = goal_puck.global_position + Vector3(0.0, GOAL_FRAGMENT_Y_OFFSET, 0.0)

	var rng := RandomNumberGenerator.new()
	var fragment_count := rng.randi_range(GOAL_FRAGMENT_MIN_COUNT, GOAL_FRAGMENT_MAX_COUNT)

	for i in fragment_count:
		var fragment := RigidBody3D.new()
		fragment.name = "Fragment%d" % i
		fragment.mass = 0.05
		fragment.gravity_scale = 0.0
		fragment.linear_damp = GOAL_FRAGMENT_LINEAR_DAMP
		fragment.angular_damp = 0.1
		fragment.collision_layer = 0
		fragment.collision_mask = 0

		var collision := CollisionShape3D.new()
		var collision_shape := BoxShape3D.new()
		collision_shape.size = Vector3(0.12, 0.06, 0.12)
		collision.shape = collision_shape
		fragment.add_child(collision)

		var mesh_instance := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(
			rng.randf_range(0.09, 0.16),
			rng.randf_range(0.04, 0.08),
			rng.randf_range(0.12, 0.2)
		)
		mesh_instance.mesh = mesh
		var material := _make_emissive_material(color, GOAL_FRAGMENT_EMISSION_ENERGY, 1.0)
		mesh_instance.material_override = material
		fragment.add_child(mesh_instance)

		fragments_root.add_child(fragment)
		var angle := rng.randf_range(0.0, TAU)
		var direction := Vector3(cos(angle), 0.0, sin(angle)).normalized()
		fragment.global_position = origin + direction * rng.randf_range(0.04, 0.16)
		fragment.rotation = Vector3(
			rng.randf_range(-0.6, 0.6),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.6, 0.6)
		)
		fragment.linear_velocity = direction * rng.randf_range(2.5, 5.5)
		fragment.angular_velocity = Vector3(
			rng.randf_range(-8.0, 8.0),
			rng.randf_range(-10.0, 10.0),
			rng.randf_range(-8.0, 8.0)
		)

		var tween := fragment.create_tween()
		tween.set_parallel(true)
		tween.tween_property(mesh_instance, "scale", Vector3.ONE * 0.18, GOAL_FRAGMENT_LIFETIME)
		tween.tween_method(
			Callable(self, "_set_material_alpha").bind(material, color, GOAL_FRAGMENT_EMISSION_ENERGY),
			1.0,
			0.0,
			GOAL_FRAGMENT_LIFETIME
		)
		tween.finished.connect(fragment.queue_free)


func _spawn_goal_flare(parent: Node3D, goal_zone: Area3D, scoring_side: StringName, color: Color) -> void:
	var goal_mesh := _resolve_goal_mesh(goal_zone, scoring_side)
	if goal_mesh == null or goal_mesh.mesh == null:
		return

	var flare := MeshInstance3D.new()
	flare.name = "GoalFlare"
	flare.mesh = goal_mesh.mesh
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var material := _make_emissive_material(color, GOAL_FLARE_EMISSION_ENERGY, 0.85)
	material.albedo_color = Color(color.r * 0.35, color.g * 0.35, color.b * 0.35, 0.85)
	flare.material_override = material
	parent.add_child(flare)
	flare.global_transform = goal_mesh.global_transform.translated_local(Vector3(0.0, 0.03, 0.0))

	var tween := flare.create_tween()
	tween.set_parallel(true)
	tween.tween_method(Callable(self, "_set_flare_state").bind(material, color), 1.0, 0.0, 0.45)
	tween.tween_property(flare, "scale", Vector3(1.28, 1.1, 1.28), 0.16)
	tween.chain().tween_property(flare, "scale", Vector3.ONE, 0.29)
	tween.finished.connect(flare.queue_free)


func _resolve_goal_mesh(goal_zone: Area3D, scoring_side: StringName) -> MeshInstance3D:
	var target_zone: Area3D = goal_zone
	if target_zone == null and _arena != null:
		target_zone = _arena.south_goal if scoring_side == &"north" else _arena.north_goal
	if target_zone == null:
		return null
	return target_zone.get_node_or_null("MeshInstance3D") as MeshInstance3D


func _make_emissive_material(color: Color, emission_energy: float, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	return material


func _set_material_alpha(alpha: float, material: StandardMaterial3D, color: Color, emission_energy: float) -> void:
	if material == null:
		return
	var clamped_alpha := clampf(alpha, 0.0, 1.0)
	material.albedo_color = Color(color.r, color.g, color.b, clamped_alpha)
	material.emission = color
	material.emission_energy_multiplier = emission_energy * clamped_alpha


func _set_flare_state(amount: float, material: StandardMaterial3D, color: Color) -> void:
	if material == null:
		return
	var clamped_amount := clampf(amount, 0.0, 1.0)
	material.albedo_color = Color(
		color.r * 0.35,
		color.g * 0.35,
		color.b * 0.35,
		clamped_amount * 0.85
	)
	material.emission = color
	material.emission_energy_multiplier = GOAL_FLARE_EMISSION_ENERGY * clamped_amount
