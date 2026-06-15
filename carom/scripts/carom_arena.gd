class_name CaromArena
extends Node3D

## Carom arena root — provides spawn points and goal detection for the match controller.

const CaromAmbientParticlesScene := preload("res://carom/scripts/effects/carom_ambient_particles.gd")

signal goal_scored(scoring_side: StringName, puck: CaromPuck)

@export var arena_width: float = 20.0
@export var arena_depth: float = 12.0

var _goal_locked: bool = false

@onready var south_goal: Area3D = $SouthGoal
@onready var north_goal: Area3D = $NorthGoal
@onready var south_turret_spawn: Marker3D = $SpawnMarkers/SouthTurretSpawn
@onready var north_turret_spawn: Marker3D = $SpawnMarkers/NorthTurretSpawn
@onready var puck_spawn: Marker3D = $SpawnMarkers/PuckSpawn
@onready var puck_spawn_2: Marker3D = $SpawnMarkers/PuckSpawn2


func _ready() -> void:
	south_goal.body_entered.connect(_on_south_goal_body_entered)
	north_goal.body_entered.connect(_on_north_goal_body_entered)
	_setup_ambient_particles()


func _setup_ambient_particles() -> void:
	var ambient := CaromAmbientParticlesScene.new()
	ambient.name = "AmbientParticles"
	add_child(ambient)
	ambient.setup(arena_width, arena_depth)


func reset_goal_lock() -> void:
	_goal_locked = false


func lock_goals() -> void:
	_goal_locked = true


func get_puck_spawn_positions() -> Array[Vector3]:
	return [puck_spawn.global_position, puck_spawn_2.global_position]


func get_puck_spawn_position() -> Vector3:
	# Legacy — returns midpoint for AI reference
	return (puck_spawn.global_position + puck_spawn_2.global_position) * 0.5


func get_turret_spawn_position(side: StringName) -> Vector3:
	if side == &"south":
		return south_turret_spawn.global_position
	return north_turret_spawn.global_position


func get_goal_targets() -> Array[Vector3]:
	return [south_goal.global_position, north_goal.global_position]


func _on_south_goal_body_entered(body: Node) -> void:
	if body is CaromProjectile:
		(body as CaromProjectile).enter_goal()
		return
	if _goal_locked or not body is CaromPuck:
		return
	_goal_locked = true
	goal_scored.emit(&"north", body as CaromPuck)


func _on_north_goal_body_entered(body: Node) -> void:
	if body is CaromProjectile:
		(body as CaromProjectile).enter_goal()
		return
	if _goal_locked or not body is CaromPuck:
		return
	_goal_locked = true
	goal_scored.emit(&"south", body as CaromPuck)
