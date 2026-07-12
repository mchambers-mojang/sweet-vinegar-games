extends RefCounted

const CaromMuzzleFlashEffect := preload("res://carom/scripts/effects/carom_muzzle_flash.gd")

var _arena: CaromArena = null
var _impact_spawner: CaromImpactSpawner = null
var _screen_shake: CaromScreenShake = null


func setup(arena: CaromArena, impact_spawner: CaromImpactSpawner, screen_shake: CaromScreenShake) -> void:
	_arena = arena
	_impact_spawner = impact_spawner
	_screen_shake = screen_shake


func register_turret(turret: CaromTurret) -> void:
	if turret == null:
		return
	var on_projectile_fired := Callable(self, "_on_projectile_fired").bind(turret.team_color)
	if turret.projectile_fired.is_connected(on_projectile_fired):
		return
	turret.projectile_fired.connect(on_projectile_fired)


func _on_projectile_fired(projectile: CaromProjectile, color: Color) -> void:
	var parent_scene := projectile.get_tree().current_scene
	if parent_scene == null:
		parent_scene = _arena

	CaromMuzzleFlashEffect.spawn(projectile.global_position, color, parent_scene)

	var trail := CaromProjectileTrail.new()
	trail.attach(projectile, color)

	if _impact_spawner != null:
		_impact_spawner.register_projectile(projectile)

	projectile.impact_occurred.connect(_on_projectile_impact.bind(projectile, color))

	FeedbackManager.vibrate_light()

	if DebugFlags.debug_fire_screen_shake and _screen_shake:
		_screen_shake.shake(0.05)


func _on_projectile_impact(pos: Vector3, hit_puck: bool, projectile: CaromProjectile, color: Color) -> void:
	if not is_instance_valid(projectile) or _impact_spawner == null:
		return

	if hit_puck:
		var diff: Vector3 = projectile.global_position - pos
		# Approximate outward normal from the impact point toward the projectile centre.
		var normal: Vector3 = diff.normalized() if diff.length_squared() > 0.0001 else Vector3.FORWARD
		_impact_spawner.spawn_puck_impact(pos, -normal, color, 1.0)
		FeedbackManager.vibrate_medium()
	else:
		# The sim does not expose the wall surface normal in the collision event.
		# Vector3.FORWARD is a cosmetic placeholder; the sparks appear at the
		# correct position even if their spray direction is approximate.
		var normal := Vector3.FORWARD
		_impact_spawner.spawn_wall_impact(pos, normal, color)
