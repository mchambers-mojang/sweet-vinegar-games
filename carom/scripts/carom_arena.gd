class_name CaromArena
extends Node3D

## Carom arena root — provides spawn points and goal detection for the match controller.

const CaromAmbientParticlesScene := preload("res://carom/scripts/effects/carom_ambient_particles.gd")
const CAMERA_MODE_TOP_DOWN: String = "top_down"
const CAMERA_MODE_ISOMETRIC: String = "isometric"
const CAMERA_TRANSITION_SECONDS: float = 0.5
const TOP_DOWN_POSITION: Vector3 = Vector3(0.0, 20.0, 12.0)
const TOP_DOWN_ROTATION: Vector3 = Vector3(-90.0, 0.0, 0.0)
const ISOMETRIC_POSITION: Vector3 = Vector3(0.0, 16.0, 24.0)
const ISOMETRIC_ROTATION: Vector3 = Vector3(-45.0, 0.0, 0.0)

signal goal_scored(scoring_side: StringName, puck: CaromPuck)

@export var arena_width: float = 20.0
@export var arena_depth: float = 12.0

var _goal_locked: bool = false
var _camera_mode_tween: Tween = null

@onready var south_goal: Area3D = $SouthGoal
@onready var north_goal: Area3D = $NorthGoal
@onready var south_turret_spawn: Marker3D = $SpawnMarkers/SouthTurretSpawn
@onready var north_turret_spawn: Marker3D = $SpawnMarkers/NorthTurretSpawn
@onready var puck_spawn: Marker3D = $SpawnMarkers/PuckSpawn
@onready var puck_spawn_2: Marker3D = $SpawnMarkers/PuckSpawn2
@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	south_goal.body_entered.connect(_on_south_goal_body_entered)
	north_goal.body_entered.connect(_on_north_goal_body_entered)
	_setup_ambient_particles()
	CaromSettings.ensure_loaded()
	set_camera_mode(CaromSettings.camera_mode, false)


func set_camera_mode(mode: String, animate: bool = true) -> void:
	if _camera == null:
		return

	var target_mode := mode
	if target_mode != CAMERA_MODE_TOP_DOWN and target_mode != CAMERA_MODE_ISOMETRIC:
		target_mode = CAMERA_MODE_TOP_DOWN

	var target_position := TOP_DOWN_POSITION
	var target_rotation := TOP_DOWN_ROTATION
	if target_mode == CAMERA_MODE_ISOMETRIC:
		target_position = ISOMETRIC_POSITION
		target_rotation = ISOMETRIC_ROTATION

	if _camera_mode_tween and _camera_mode_tween.is_valid():
		_camera_mode_tween.kill()
		_camera_mode_tween = null

	if not animate:
		_camera.position = target_position
		_camera.rotation_degrees = target_rotation
		return

	_camera_mode_tween = create_tween()
	_camera_mode_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_camera_mode_tween.tween_property(_camera, "position", target_position, CAMERA_TRANSITION_SECONDS)
	_camera_mode_tween.parallel().tween_property(_camera, "rotation_degrees", target_rotation, CAMERA_TRANSITION_SECONDS)


func _setup_ambient_particles() -> void:
	var ambient := CaromAmbientParticlesScene.new()
	ambient.name = "AmbientParticles"
	add_child(ambient)
	ambient.setup(arena_width, arena_depth)


func reset_goal_lock() -> void:
	_goal_locked = false


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
