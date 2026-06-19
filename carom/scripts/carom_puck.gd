class_name CaromPuck
extends Node3D

## Triangular prism puck — render adapter.
## Position and rotation are driven by CaromSimBridge each frame via
## interpolation between deterministic sim ticks (30 Hz → display rate).
## All visual logic (tension pulse, material effects) reads from node state
## but never writes to the physics simulation.

@export var max_speed: float = 14.0
@export var stall_nudge_force: float = 0.18
@export var stall_speed_threshold: float = 1.8
@export var reset_height: float = 0.0

const EMISSION_BASE: float = 2.0
const EMISSION_PEAK: float = 10.0
const PULSE_FREQ_FAR: float = 0.5
const PULSE_FREQ_MID: float = 2.0
const PULSE_FREQ_NEAR: float = 4.0

var _player_goal: Vector3 = Vector3.ZERO
var _goal_targets: Array[Vector3] = []
var _arena_length: float = 30.0
var _reset_position: Vector3 = Vector3.ZERO
var _puck_material: StandardMaterial3D = null
var _pulse_time: float = 0.0

## Set by CaromSimBridge.register_puck() — null until registered.
var _bridge: CaromSimBridge = null


func _ready() -> void:
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
	# Player turret is at the bottom (south spawn, Z=22) defending the SouthGoal (Z=24.4).
	# Puck entering SouthGoal = AI scores. Player's danger zone is NorthGoal (Z=-0.4) direction.
	_goal_targets = goal_targets.duplicate()
	if goal_targets.size() >= 2:
		_player_goal = goal_targets[0]  # [south_goal, north_goal] — south is player's danger zone
		_arena_length = goal_targets[0].distance_to(goal_targets[1])
	elif goal_targets.size() == 1:
		_player_goal = goal_targets[0]
	_reset_position = reset_position


## Called by CaromSimBridge.register_puck() to give this adapter access to the sim.
func setup_sim_bridge(bridge: CaromSimBridge) -> void:
	_bridge = bridge


func reset_to_center(reset_position: Vector3 = Vector3.ZERO) -> void:
	if reset_position == Vector3.ZERO:
		reset_position = _reset_position
	var target := Vector3(reset_position.x, reset_height, reset_position.z)
	global_position = target
	if _bridge != null:
		_bridge.reset_puck_to(self, target)


func _process(delta: float) -> void:
	# Drive position from sim interpolation if registered with the bridge.
	if _bridge != null:
		var alpha := _bridge.get_render_alpha()
		global_position = _bridge.get_puck_position(self, alpha)
		rotation.y      = _bridge.get_puck_rotation(self, alpha)

	_update_pulse(delta)

	# Safety bounds check — reset if escaped arena (e.g. after a severe sim error).
	if abs(global_position.x) > 8.0 or global_position.z < -3.0 or global_position.z > 28.0:
		push_warning("Puck escaped bounds at %s — resetting" % str(global_position))
		reset_to_center()


func _update_pulse(delta: float) -> void:
	if _puck_material == null:
		return

	# Only pulse when puck is near the PLAYER's goal (danger zone)
	var dist := _get_player_goal_distance()
	var fraction := dist / _arena_length if _arena_length > 0.0 else 1.0

	if fraction >= 0.4:
		# Far from player's goal — static cyan
		_puck_material.emission_energy_multiplier = EMISSION_BASE
		_puck_material.albedo_color = Color(0.01, 0.06, 0.08, 1.0)
		_puck_material.emission = Color(0.1, 0.7, 0.8, 1.0)
		_pulse_time = 0.0
		return

	var freq := _get_pulse_frequency(fraction)
	_pulse_time = fmod(_pulse_time + delta * freq * TAU, TAU)
	var t := (sin(_pulse_time) + 1.0) * 0.5
	_puck_material.emission_energy_multiplier = lerpf(EMISSION_BASE, EMISSION_PEAK, t)
	var albedo_t := lerpf(0.02, 0.12, t)
	_puck_material.albedo_color = Color(albedo_t * 0.5, albedo_t * 3.5, albedo_t * 4.0, 1.0)
	_puck_material.emission = Color(0.1 + t * 0.7, 0.7 + t * 0.3, 0.8 + t * 0.2, 1.0)


func _get_pulse_frequency(fraction: float) -> float:
	if fraction <= 0.15:
		return PULSE_FREQ_NEAR
	elif fraction <= 0.3:
		return lerpf(PULSE_FREQ_NEAR, PULSE_FREQ_MID, (fraction - 0.15) / 0.15)
	else:
		return lerpf(PULSE_FREQ_MID, PULSE_FREQ_FAR, (fraction - 0.3) / 0.1)


func _get_player_goal_distance() -> float:
	if _player_goal == Vector3.ZERO:
		return INF
	return Vector2(_player_goal.x - global_position.x, _player_goal.z - global_position.z).length()
