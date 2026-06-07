class_name CaromPuck
extends RigidBody3D

## Triangular prism puck — spins freely on Y axis, locked on X/Z.
## The 3 angled faces create unpredictable deflections when hit.

@export var max_speed: float = 14.0
@export var stall_nudge_force: float = 0.18
@export var stall_speed_threshold: float = 1.8
@export var reset_height: float = 0.0

var _goal_targets: Array[Vector3] = []
var _reset_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	can_sleep = false
	# Lock X and Z rotation, allow Y spin
	axis_lock_angular_x = true
	axis_lock_angular_z = true


func configure(goal_targets: Array[Vector3], reset_position: Vector3) -> void:
	_goal_targets = goal_targets.duplicate()
	_reset_position = reset_position


func reset_to_center(reset_position: Vector3 = Vector3.ZERO) -> void:
	if reset_position == Vector3.ZERO:
		reset_position = _reset_position
	global_position = Vector3(reset_position.x, reset_height, reset_position.z)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	# Safety bounds check
	if abs(global_position.x) > 8.0 or global_position.z < -2.0 or global_position.z > 28.0 or abs(global_position.y) > 3.0:
		push_warning("Puck escaped bounds at %s — resetting" % str(global_position))
		reset_to_center()
		return

	# Speed clamp
	var speed := linear_velocity.length()
	if speed > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed

	# Stall nudge
	if stall_nudge_force > 0.0 and speed <= stall_speed_threshold:
		_apply_goal_nudge()


func _apply_goal_nudge() -> void:
	if _goal_targets.is_empty():
		return

	var nearest_goal := _goal_targets[0]
	var nearest_distance: float = 1e20
	for goal_target in _goal_targets:
		var flat_distance := Vector2(goal_target.x - global_position.x, goal_target.z - global_position.z).length_squared()
		if flat_distance < nearest_distance:
			nearest_distance = flat_distance
			nearest_goal = goal_target

	var direction := nearest_goal - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return

	apply_central_force(direction.normalized() * stall_nudge_force)
