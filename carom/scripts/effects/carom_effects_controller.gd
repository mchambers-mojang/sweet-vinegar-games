class_name CaromEffectsController
extends Node

## Wires up all visual effects for a Carom match.
## Add as child of CaromArena. Listens for turret fire events and projectile collisions.

var _screen_shake: CaromScreenShake = null
var _impact_spawner: CaromImpactSpawner = null
var _arena: CaromArena = null

const MATCH_WIN_ZOOM_RATIO: float = 0.8
const MATCH_WIN_CAMERA_SHIFT_RATIO: float = 0.2
const MATCH_WIN_ZOOM_IN_SECONDS: float = 0.3
const MATCH_WIN_ZOOM_OUT_SECONDS: float = 0.5
const MATCH_WIN_SHAKE_INTENSITY: float = 0.7
const MIN_TIME_SCALE_CLAMP: float = 0.001


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
	# Muzzle flash at the barrel tip
	CaromMuzzleFlash.spawn(projectile.global_position, color, get_tree().current_scene)

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


func play_match_win(goal_position: Vector3) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	_setup_screen_shake()
	if _screen_shake:
		_screen_shake.shake(MATCH_WIN_SHAKE_INTENSITY)

	var start_position: Vector3 = camera.global_position
	var target_position: Vector3 = Vector3(goal_position.x, start_position.y, goal_position.z)
	var zoom_position: Vector3 = start_position.lerp(target_position, MATCH_WIN_CAMERA_SHIFT_RATIO)

	var zoom_tween := create_tween()
	zoom_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	zoom_tween.set_speed_scale(1.0 / maxf(Engine.time_scale, MIN_TIME_SCALE_CLAMP))

	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		var start_size: float = camera.size
		zoom_tween.tween_property(camera, "size", start_size * MATCH_WIN_ZOOM_RATIO, MATCH_WIN_ZOOM_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		zoom_tween.parallel().tween_property(camera, "global_position", zoom_position, MATCH_WIN_ZOOM_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		zoom_tween.tween_property(camera, "size", start_size, MATCH_WIN_ZOOM_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		zoom_tween.parallel().tween_property(camera, "global_position", start_position, MATCH_WIN_ZOOM_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	else:
		var start_fov: float = camera.fov
		zoom_tween.tween_property(camera, "fov", start_fov * MATCH_WIN_ZOOM_RATIO, MATCH_WIN_ZOOM_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		zoom_tween.parallel().tween_property(camera, "global_position", zoom_position, MATCH_WIN_ZOOM_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		zoom_tween.tween_property(camera, "fov", start_fov, MATCH_WIN_ZOOM_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		zoom_tween.parallel().tween_property(camera, "global_position", start_position, MATCH_WIN_ZOOM_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
