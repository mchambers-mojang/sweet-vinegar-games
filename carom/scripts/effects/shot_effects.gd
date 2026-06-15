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

	projectile.body_entered.connect(_on_projectile_body_entered.bind(projectile, color))

	HapticManager.vibrate_light()

	if DebugFlags.debug_fire_screen_shake and _screen_shake:
		_screen_shake.shake(0.05)


func _on_projectile_body_entered(body: Node, projectile: CaromProjectile, color: Color) -> void:
	if not is_instance_valid(projectile) or not is_instance_valid(body) or _impact_spawner == null:
		return

	var impact_pos := projectile.global_position
	var velocity := projectile.linear_velocity

	if body is CaromPuck:
		var puck_pos: Vector3 = (body as CaromPuck).global_position
		var diff: Vector3 = puck_pos - impact_pos
		if diff.length_squared() < 0.0001:
			diff = velocity.normalized()
		var normal: Vector3 = diff.normalized()
		var force := velocity.length() / maxf(projectile.speed, 1.0)
		_impact_spawner.spawn_puck_impact(impact_pos, -normal, color, force)
		HapticManager.vibrate_medium()
	elif body is StaticBody3D:
		var normal := -velocity.normalized() if velocity.length_squared() > 0.001 else Vector3.UP
		_impact_spawner.spawn_wall_impact(impact_pos, normal, color)
