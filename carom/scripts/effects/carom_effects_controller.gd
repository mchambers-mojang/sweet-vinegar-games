class_name CaromEffectsController
extends Node

## Wires up all visual effects for a Carom match.
## Add as child of CaromArena. Listens for turret fire events and projectile collisions.

var _screen_shake: CaromScreenShake = null
var _impact_spawner: CaromImpactSpawner = null
var _arena: CaromArena = null


func _ready() -> void:
	_arena = get_parent() as CaromArena
	if _arena == null:
		push_warning("CaromEffectsController must be a child of CaromArena")
		return

	# Create impact spawner
	_impact_spawner = CaromImpactSpawner.new()
	_impact_spawner.name = "ImpactSpawner"
	add_child(_impact_spawner)

	# Find or create screen shake on the camera
	_setup_screen_shake()

	_impact_spawner.set_screen_shake(_screen_shake)


func _setup_screen_shake() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# Check if shake already exists
	_screen_shake = camera.get_node_or_null("ScreenShake") as CaromScreenShake
	if _screen_shake == null:
		_screen_shake = CaromScreenShake.new()
		_screen_shake.name = "ScreenShake"
		camera.add_child(_screen_shake)


## Register a turret so its projectiles get trails and impact detection.
func register_turret(turret: CaromTurret) -> void:
	if not turret.projectile_fired.is_connected(_on_projectile_fired):
		turret.projectile_fired.connect(_on_projectile_fired.bind(turret.team_color))


func _on_projectile_fired(projectile: CaromProjectile, color: Color) -> void:
	# Attach ribbon trail
	var trail := CaromProjectileTrail.new()
	trail.attach(projectile, color)

	# Register for impact detection
	_impact_spawner.register_projectile(projectile)

	# Wire collision signal for effects
	projectile.body_entered.connect(_on_projectile_body_entered.bind(projectile, color))

	# Fire haptic
	HapticManager.vibrate_light()

	# Fire screen shake (debug only)
	if DebugFlags.debug_fire_screen_shake and _screen_shake:
		_screen_shake.shake(0.05)


func _on_projectile_body_entered(body: Node, projectile: CaromProjectile, color: Color) -> void:
	if not is_instance_valid(projectile) or not is_instance_valid(body):
		return

	var impact_pos := projectile.global_position
	var velocity := projectile.linear_velocity

	if body is CaromPuck:
		print("[DEBUG-fx02] Puck hit at %s" % str(impact_pos))
		var puck_pos: Vector3 = (body as CaromPuck).global_position
		var diff: Vector3 = puck_pos - impact_pos
		if diff.length_squared() < 0.0001:
			diff = velocity.normalized()
		var normal: Vector3 = diff.normalized()
		_impact_spawner.spawn_puck_impact(impact_pos, -normal, color)
		HapticManager.vibrate_medium()
	elif body is StaticBody3D:
		print("[DEBUG-fx02] Wall hit at %s" % str(impact_pos))
		var normal := -velocity.normalized() if velocity.length_squared() > 0.001 else Vector3.UP
		_impact_spawner.spawn_wall_impact(impact_pos, normal, color)
