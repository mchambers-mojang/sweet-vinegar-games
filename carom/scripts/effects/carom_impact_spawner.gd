class_name CaromImpactSpawner
extends Node

## Listens for projectile collisions and spawns impact effects.
## Attach as child of the arena or match controller.
## Call register_projectile() for each new projectile.

const WALL_PARTICLE_COUNT: int = 8
const PUCK_PARTICLE_COUNT: int = 20
const SPARK_LIFETIME: float = 0.4
const SPARK_SPEED: float = 6.0
const PUCK_SPARK_SPEED: float = 10.0

var _screen_shake: CaromScreenShake = null
var _registered: Array[CaromProjectile] = []


## Provide the screen shake node so puck impacts can trigger it.
func set_screen_shake(shake: CaromScreenShake) -> void:
	_screen_shake = shake


## Register a projectile to monitor for collisions.
func register_projectile(projectile: CaromProjectile) -> void:
	if not is_instance_valid(projectile):
		return
	_registered.append(projectile)
	projectile.tree_exiting.connect(_on_projectile_removed.bind(projectile))


func _physics_process(_delta: float) -> void:
	for projectile in _registered:
		if not is_instance_valid(projectile):
			continue
		_check_collisions(projectile)


func _check_collisions(projectile: CaromProjectile) -> void:
	# RigidBody3D contact monitoring
	var contact_count := projectile.get_contact_count()
	for i in contact_count:
		var collider := projectile.get_colliding_bodies()
		break  # We use body_entered signal approach instead


func _on_projectile_removed(projectile: CaromProjectile) -> void:
	_registered.erase(projectile)


## Spawn a wall-hit spark effect at position, spraying in the given direction.
func spawn_wall_impact(pos: Vector3, normal: Vector3, color: Color) -> void:
	_spawn_sparks(pos, normal, color, WALL_PARTICLE_COUNT, SPARK_SPEED, 0.6)


## Spawn a puck-hit burst at position with screen shake.
func spawn_puck_impact(pos: Vector3, normal: Vector3, color: Color, force: float = 1.0) -> void:
	_spawn_sparks(pos, normal, color, PUCK_PARTICLE_COUNT, PUCK_SPARK_SPEED, 1.0)
	if _screen_shake:
		_screen_shake.shake(clampf(force * 0.3, 0.1, 0.6))


func _spawn_sparks(pos: Vector3, direction: Vector3, color: Color, count: int, speed: float, spread: float) -> void:
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = count
	particles.lifetime = SPARK_LIFETIME
	particles.finished.connect(particles.queue_free)

	var mat := ParticleProcessMaterial.new()
	mat.direction = direction
	mat.spread = spread * 45.0  # degrees
	mat.initial_velocity_min = speed * 0.5
	mat.initial_velocity_max = speed
	mat.gravity = Vector3(0.0, -9.8, 0.0)
	mat.damping_min = 2.0
	mat.damping_max = 4.0
	mat.scale_min = 0.03
	mat.scale_max = 0.06
	mat.color = color
	particles.process_material = mat

	# Simple sphere mesh for sparks
	var draw_pass := SphereMesh.new()
	draw_pass.radius = 0.03
	draw_pass.height = 0.06
	particles.draw_pass_1 = draw_pass

	# Unshaded emissive material
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.albedo_color = color
	mesh_mat.emission_enabled = true
	mesh_mat.emission = color
	mesh_mat.emission_energy_multiplier = 3.0
	particles.material_override = mesh_mat

	particles.global_position = pos
	get_tree().current_scene.add_child(particles)
