extends GutTest

const ArenaScene := preload("res://carom/scenes/carom_arena.tscn")
const PuckScene := preload("res://carom/scenes/carom_puck.tscn")
const TurretScene := preload("res://carom/scenes/carom_turret.tscn")


func _find_trail(node: Node) -> CaromProjectileTrail:
	if node is CaromProjectileTrail:
		return node as CaromProjectileTrail
	for child in node.get_children():
		var trail := _find_trail(child)
		if trail != null:
			return trail
	return null


func _find_projectile(node: Node) -> CaromProjectile:
	if node is CaromProjectile:
		return node as CaromProjectile
	for child in node.get_children():
		var projectile := _find_projectile(child)
		if projectile != null:
			return projectile
	return null


func test_play_goal_scored_spawns_burst_fragments_and_flare() -> void:
	var arena := ArenaScene.instantiate() as CaromArena
	add_child_autofree(arena)

	var effects := CaromEffectsController.new()
	arena.add_child(effects)

	var puck := PuckScene.instantiate() as CaromPuck
	arena.get_node("Actors").add_child(puck)
	puck.global_position = arena.south_goal.global_position + Vector3(0.0, 0.0, 0.15)

	var celebration := effects.play_goal_scored(
		puck.global_position,
		&"north",
		Color(0.2, 0.6, 1.0),
		puck,
		arena.south_goal
	)

	assert_not_null(celebration)
	assert_not_null(celebration.get_node_or_null("Burst"))
	assert_not_null(celebration.get_node_or_null("Fragments"))
	assert_not_null(celebration.get_node_or_null("GoalFlare"))

	var fragments := celebration.get_node("Fragments")
	assert_gte(fragments.get_child_count(), 5)
	assert_lte(fragments.get_child_count(), 8)

	var flare := celebration.get_node("GoalFlare") as MeshInstance3D
	var goal_mesh := arena.south_goal.get_node("MeshInstance3D") as MeshInstance3D
	assert_true(flare.material_override is StandardMaterial3D)
	assert_ne(flare.material_override, goal_mesh.material_override)

	var burst := celebration.get_node("Burst") as GPUParticles3D
	var burst_material := burst.process_material as ParticleProcessMaterial
	assert_eq(burst_material.gravity, Vector3.ZERO)

	for fragment_node in fragments.get_children():
		var fragment := fragment_node as RigidBody3D
		assert_eq(fragment.gravity_scale, 0.0)
		assert_gt(Vector2(fragment.linear_velocity.x, fragment.linear_velocity.z).length(), 0.0)
		assert_almost_eq(fragment.linear_velocity.y, 0.0, 0.001)
		assert_almost_eq(
			fragment.global_position.y,
			puck.global_position.y + CaromEffectsController.GOAL_FRAGMENT_Y_OFFSET,
			0.001
		)


func test_register_turret_attaches_trail_and_impact_spawner() -> void:
	var arena := ArenaScene.instantiate() as CaromArena
	add_child_autofree(arena)

	var effects := CaromEffectsController.new()
	arena.add_child(effects)

	var turret := TurretScene.instantiate() as CaromTurret
	arena.get_node("Actors").add_child(turret)
	await get_tree().process_frame
	effects.register_turret(turret)

	assert_not_null(effects.get_node_or_null("ImpactSpawner"))
	assert_true(turret.try_fire())
	await get_tree().process_frame
	var projectile := _find_projectile(get_tree().root)
	var trail := _find_trail(get_tree().root)
	assert_not_null(projectile)
	assert_not_null(trail)

	if projectile != null:
		projectile.queue_free()
	if trail != null:
		trail.queue_free()
	var ammo_ring := arena.get_node("Actors").get_node_or_null("AmmoRing")
	if ammo_ring != null:
		ammo_ring.queue_free()


func test_play_match_win_uses_camera_screen_shake() -> void:
	var arena := ArenaScene.instantiate() as CaromArena
	add_child_autofree(arena)

	var effects := CaromEffectsController.new()
	arena.add_child(effects)

	var camera := arena.get_viewport().get_camera_3d()
	assert_not_null(camera)

	effects.play_match_win(arena.south_goal.global_position)

	assert_not_null(camera.get_node_or_null("ScreenShake"))
