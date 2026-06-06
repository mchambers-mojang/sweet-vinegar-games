class_name CaromPuck
extends Node3D

## Crossfire-style puck: triangular prism cage with a ball rolling inside.
## Cage (lock_rotation) provides 3 angled walls that deflect projectiles unpredictably.
## Ball rolls freely inside — its momentum transfers through the cage walls.

@export var max_speed: float = 14.0
@export var stall_nudge_force: float = 0.18
@export var stall_speed_threshold: float = 1.8
@export var reset_height: float = 0.4

var _goal_targets: Array[Vector3] = []
var _reset_position: Vector3 = Vector3.ZERO

@onready var cage: RigidBody3D = $Cage
@onready var ball: RigidBody3D = $Ball


func _ready() -> void:
	cage.can_sleep = false
	ball.can_sleep = false


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
	ball.global_position = pos
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	# Use cage as primary position reference
	var pos := cage.global_position

	# Safety bounds check
	if abs(pos.x) > 8.0 or pos.z < -2.0 or pos.z > 28.0 or abs(pos.y) > 3.0:
		push_warning("Puck escaped bounds at %s — resetting" % str(pos))
		reset_to_center()
		return

	# Speed clamp on both bodies
	var cage_speed := cage.linear_velocity.length()
	if cage_speed > max_speed:
		cage.linear_velocity = cage.linear_velocity.normalized() * max_speed

	var ball_speed := ball.linear_velocity.length()
	if ball_speed > max_speed:
		ball.linear_velocity = ball.linear_velocity.normalized() * max_speed

	# Keep ball Y locked to same height as cage (prevent flying out vertically)
	if abs(ball.global_position.y - cage.global_position.y) > 0.3:
		ball.global_position.y = cage.global_position.y
		ball.linear_velocity.y = 0.0

	# Stall nudge on cage
	if stall_nudge_force > 0.0 and cage_speed <= stall_speed_threshold:
		_apply_goal_nudge()


func get_puck_position() -> Vector3:
	if cage:
		return cage.global_position
	return global_position


func set_puck_position(value: Vector3) -> void:
	if cage:
		cage.global_position = value
	if ball:
		ball.global_position = value


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
