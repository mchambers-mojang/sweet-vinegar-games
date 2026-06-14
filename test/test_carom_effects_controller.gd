extends GutTest

const ArenaScene := preload("res://carom/scenes/carom_arena.tscn")
const PuckScene := preload("res://carom/scenes/carom_puck.tscn")


func test_goal_celebration_spawns_burst_fragments_and_flare() -> void:
	var arena := ArenaScene.instantiate() as CaromArena
	add_child_autofree(arena)

	var effects := CaromEffectsController.new()
	arena.add_child(effects)

	var puck := PuckScene.instantiate() as CaromPuck
	arena.get_node("Actors").add_child(puck)
	puck.global_position = arena.south_goal.global_position + Vector3(0.0, 0.0, 0.15)

	var celebration := effects.play_goal_celebration(
		arena.south_goal.global_position,
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
