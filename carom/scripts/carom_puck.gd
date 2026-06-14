class_name CaromPuck
extends RigidBody3D

## Triangular prism puck — spins freely on Y axis, locked on X/Z.
## The 3 angled faces create unpredictable deflections when hit.

@export var max_speed: float = 14.0
@export var stall_nudge_force: float = 0.18
@export var stall_speed_threshold: float = 1.8
@export var reset_height: float = 0.0

const EMISSION_BASE: float = 2.0
const EMISSION_PEAK: float = 10.0
const PULSE_FREQ_FAR: float = 0.5
const PULSE_FREQ_MID: float = 2.0
const PULSE_FREQ_NEAR: float = 4.0

var _goal_targets: Array[Vector3] = []
var _reset_position: Vector3 = Vector3.ZERO
var _puck_material: StandardMaterial3D = null
var _pulse_time: float = 0.0


func _ready() -> void:
	can_sleep = false
	# Lock X and Z rotation, allow Y spin
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	_setup_emission_material()


func _setup_emission_material() -> void:
	# Grab the existing material from the first mesh (shared SubResource in .tscn)
	# and modify it in place — creating a new one doesn't reliably override the scene material.
	for child in get_children():
		if child is MeshInstance3D:
			var mesh_inst := child as MeshInstance3D
			if _puck_material == null and mesh_inst.material_override != null:
				_puck_material = mesh_inst.material_override.duplicate() as StandardMaterial3D
				_puck_material.emission_enabled = true
				_puck_material.emission = Color(0.8, 1.0, 1.0, 1)
				_puck_material.emission_energy_multiplier = EMISSION_BASE
			if _puck_material != null:
				mesh_inst.material_override = _puck_material
	if _puck_material == null:
		_puck_material = StandardMaterial3D.new()
		_puck_material.albedo_color = Color(0.02, 0.08, 0.1, 1)
		_puck_material.emission_enabled = true
		_puck_material.emission = Color(0.8, 1.0, 1.0, 1)
		_puck_material.emission_energy_multiplier = EMISSION_BASE
		_puck_material.roughness = 0.2
		for child in get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).material_override = _puck_material


func configure(goal_targets: Array[Vector3], reset_position: Vector3) -> void:
	_goal_targets = goal_targets.duplicate()
	_reset_position = reset_position


func reset_to_center(reset_position: Vector3 = Vector3.ZERO) -> void:
	if reset_position == Vector3.ZERO:
		reset_position = _reset_position
	global_position = Vector3(reset_position.x, reset_height, reset_position.z)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO





func _update_pulse(delta: float) -> void:
	if _puck_material == null:
		return

	# Only pulse when near a goal (fraction < 0.4), otherwise stay static cyan
	var fraction := 1.0
	if not _goal_targets.is_empty():
		var arena_length := _get_arena_length()
		if arena_length > 0.0:
			fraction = _get_nearest_goal_distance() / arena_length

	if fraction >= 0.4:
		# Far from goal — static cyan
		_puck_material.emission_energy_multiplier = EMISSION_BASE
		_puck_material.albedo_color = Color(0.01, 0.06, 0.08, 1.0)
		_puck_material.emission = Color(0.1, 0.7, 0.8, 1.0)
		_pulse_time = 0.0
		return

	var freq := _get_pulse_frequency()
	_pulse_time = fmod(_pulse_time + delta * freq * TAU, TAU)
	var t := (sin(_pulse_time) + 1.0) * 0.5
	_puck_material.emission_energy_multiplier = lerpf(EMISSION_BASE, EMISSION_PEAK, t)
	var albedo_t := lerpf(0.02, 0.12, t)
	_puck_material.albedo_color = Color(albedo_t * 0.5, albedo_t * 3.5, albedo_t * 4.0, 1.0)
	_puck_material.emission = Color(0.1 + t * 0.7, 0.7 + t * 0.3, 0.8 + t * 0.2, 1.0)


func _get_pulse_frequency() -> float:
	if _goal_targets.is_empty():
		return PULSE_FREQ_FAR

	var nearest_dist := _get_nearest_goal_distance()
	var arena_length := _get_arena_length()
	if arena_length <= 0.0:
		return PULSE_FREQ_FAR

	var fraction := nearest_dist / arena_length

	if fraction >= 0.6:
		return PULSE_FREQ_FAR
	elif fraction <= 0.3:
		# Near zone: lerp 3.0 Hz → 1.5 Hz as puck moves away from goal
		return lerpf(PULSE_FREQ_NEAR, PULSE_FREQ_MID, fraction / 0.3)
	else:
		# Mid zone: lerp 1.5 Hz → 0.5 Hz as puck moves further away
		return lerpf(PULSE_FREQ_MID, PULSE_FREQ_FAR, (fraction - 0.3) / 0.3)


func _get_nearest_goal_distance() -> float:
	var nearest: float = INF
	for goal in _goal_targets:
		var d := Vector2(goal.x - global_position.x, goal.z - global_position.z).length()
		if d < nearest:
			nearest = d
	return nearest


func _get_arena_length() -> float:
	if _goal_targets.size() < 2:
		return 30.0
	return _goal_targets[0].distance_to(_goal_targets[1])


func _physics_process(_delta: float) -> void:
	_update_pulse(_delta)

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
