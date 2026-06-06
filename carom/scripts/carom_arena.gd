class_name CaromArena
extends Node3D

## Carom arena root — provides spawn points and goal detection for the match controller.

signal goal_scored(scoring_side: StringName, puck: CaromPuck)

@export var arena_width: float = 20.0
@export var arena_depth: float = 12.0

var _goal_locked: bool = false

@onready var south_goal: Area3D = $SouthGoal
@onready var north_goal: Area3D = $NorthGoal
@onready var south_turret_spawn: Marker3D = $SpawnMarkers/SouthTurretSpawn
@onready var north_turret_spawn: Marker3D = $SpawnMarkers/NorthTurretSpawn
@onready var puck_spawn: Marker3D = $SpawnMarkers/PuckSpawn


func _ready() -> void:
	south_goal.body_entered.connect(_on_south_goal_body_entered)
	north_goal.body_entered.connect(_on_north_goal_body_entered)


func reset_goal_lock() -> void:
	_goal_locked = false


func get_puck_spawn_position() -> Vector3:
	return puck_spawn.global_position


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
	# Cage or Ball RigidBody3D — check if parent is the puck
	var puck_node := _get_puck_from_body(body)
	if _goal_locked or puck_node == null:
		return
	_goal_locked = true
	goal_scored.emit(&"north", puck_node)


func _on_north_goal_body_entered(body: Node) -> void:
	if body is CaromProjectile:
		(body as CaromProjectile).enter_goal()
		return
	var puck_node := _get_puck_from_body(body)
	if _goal_locked or puck_node == null:
		return
	_goal_locked = true
	goal_scored.emit(&"south", puck_node)


func _get_puck_from_body(body: Node) -> CaromPuck:
	var parent := body.get_parent()
	if parent is CaromPuck:
		return parent as CaromPuck
	return null
