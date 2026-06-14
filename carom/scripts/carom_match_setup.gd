class_name CaromMatchSetup
extends Node

## Entity spawning and configuration for a Carom match.

@export var player_turret_scene: PackedScene = preload("res://carom/scenes/carom_turret.tscn")
@export var ai_turret_scene: PackedScene = preload("res://carom/scenes/carom_turret.tscn")
@export var puck_scene: PackedScene = preload("res://carom/scenes/carom_puck.tscn")

var player_turret: CaromTurret = null
var ai_turret: CaromTurret = null
var pucks: Array[CaromPuck] = []


## Spawn all actors into the arena. Cleans up any existing actors first.
func spawn_entities(arena: CaromArena, actors_parent: Node3D, ai_difficulty_level: int) -> void:
	_cleanup()

	player_turret = player_turret_scene.instantiate() as CaromTurret
	ai_turret = ai_turret_scene.instantiate() as CaromTurret

	actors_parent.add_child(player_turret)
	actors_parent.add_child(ai_turret)

	# Spawn pucks at off-center positions
	var spawn_positions := arena.get_puck_spawn_positions()
	for i in spawn_positions.size():
		var p := puck_scene.instantiate() as CaromPuck
		actors_parent.add_child(p)
		p.name = "Puck%d" % (i + 1)
		p.global_position = spawn_positions[i]
		p.configure(arena.get_goal_targets(), spawn_positions[i])
		pucks.append(p)

	player_turret.name = "PlayerTurret"
	ai_turret.name = "AITurret"

	player_turret.global_position = arena.get_turret_spawn_position(&"south")
	ai_turret.global_position = arena.get_turret_spawn_position(&"north")

	player_turret.configure(&"south", CaromTurret.ControlMode.HUMAN, 0.0, Color(0.2, 0.6, 1.0))
	ai_turret.configure(&"north", CaromTurret.ControlMode.AI, 180.0, Color(1.0, 0.25, 0.2))

	# Set up AI controller
	var midfield_z := arena.get_puck_spawn_position().z
	var ai_goal_z := arena.get_turret_spawn_position(&"north").z
	var ai_difficulty := CaromAIDifficulty.get_preset(ai_difficulty_level)
	ai_turret.setup_ai(ai_difficulty, pucks[0], player_turret, midfield_z, ai_goal_z)

	var arena_length := absf(arena.north_goal.global_position.z - arena.south_goal.global_position.z)
	player_turret.set_aim_projection_distance(arena_length * ai_difficulty.aim_projection_distance)
	ai_turret.set_aim_projection_distance(0.0)


func _cleanup() -> void:
	if player_turret:
		player_turret.queue_free()
		player_turret = null
	if ai_turret:
		ai_turret.queue_free()
		ai_turret = null
	for p in pucks:
		if is_instance_valid(p):
			p.queue_free()
	pucks.clear()
