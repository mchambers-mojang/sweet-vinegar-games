class_name CaromPuck
extends Node3D

## Crossfire-style puck: cage (RigidBody3D with fins) + visual ball mesh.
## The cage is the physics body. The ball mesh just visually rolls inside.

@export var max_speed: float = 14.0
@export var stall_nudge_force: float = 0.18
@export var stall_speed_threshold: float = 1.8
@export var reset_height: float = 0.4
@export var ball_visual_radius: float = 0.28

var _goal_targets: Array[Vector3] = []
var _reset_position: Vector3 = Vector3.ZERO

@onready var cage: RigidBody3D = $Cage
@onready var ball_mesh: MeshInstance3D = $BallMesh


func _ready() -> void:
	cage.can_sleep = false


func configure(goal_targets: Array[Vector3], reset_position: Vector3) -> void:
	_goal_targets = goal_targets.duplicate()
	_reset_position = reset_position


func reset_to_center(reset_position: Vector3 = Vector3.ZERO) -> void:
	if reset_position == Vector3.ZERO:
		reset_position = _reset_position
	var pos := Vector3(reset_position.x, reset_height, reset_position.z)
	cage.global_position = pos
	cage.linear_velocity = Vector3.ZERO
	cage.angular_velocity = Vector3.ZERO
	if ball_mesh:
		ball_mesh.global_position = pos
		ball_mesh.rotation = Vector3.ZERO


func _physics_process(delta: float) -> void:
	var pos := cage.global_position

	# Safety: if puck escapes bounds, reset
	if abs(pos.x) > 8.0 or pos.z < -2.0 or pos.z > 28.0 or abs(pos.y) > 3.0:
		push_warning("Puck escaped bounds at %s — resetting" % str(pos))
		reset_to_center()
		return

	# Speed clamp
	var speed := cage.linear_velocity.length()
	if speed > max_speed:
		cage.linear_velocity = cage.linear_velocity.normalized() * max_speed

	# Visual ball follows cage and rolls based on movement
	if ball_mesh:
		ball_mesh.global_position = pos
		if speed > 0.1:
			var vel_flat := Vector3(cage.linear_velocity.x, 0.0, cage.linear_velocity.z).normalized()
			var roll_axis := vel_flat.cross(Vector3.UP).normalized()
			if roll_axis.length_squared() > 0.001:
				ball_mesh.rotate(roll_axis, speed / ball_visual_radius * delta)

	# Stall nudge
	if stall_nudge_force > 0.0 and speed <= stall_speed_threshold:
		_apply_goal_nudge()


func get_puck_position() -> Vector3:
	if cage:
		return cage.global_position
	return global_position


func set_puck_position(value: Vector3) -> void:
	if cage:
		cage.global_position = value
	if ball_mesh:
		ball_mesh.global_position = value


func apply_impulse(impulse: Vector3, position: Vector3 = Vector3.ZERO) -> void:
	cage.apply_impulse(impulse, position)


func _apply_goal_nudge() -> void:
	if _goal_targets.is_empty():
		return

	var pos := cage.global_position
	var nearest_goal := _goal_targets[0]
	var nearest_distance: float = 1e20
	for goal_target in _goal_targets:
		var flat_distance := Vector2(goal_target.x - pos.x, goal_target.z - pos.z).length_squared()
		if flat_distance < nearest_distance:
			nearest_distance = flat_distance
			nearest_goal = goal_target

	var direction := nearest_goal - pos
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return

	cage.apply_central_force(direction.normalized() * stall_nudge_force)
