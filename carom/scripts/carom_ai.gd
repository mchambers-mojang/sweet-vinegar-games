class_name CaromAI
extends CaromTurretInput

## AI controller that drives a CaromTurret based on game state.
## Uses a state machine with puck awareness and difficulty-scaled behavior.

enum State {
	ATTACK,
	DEFEND,
	RELOAD_PRESSURE,
	TRICK_SHOT,
}

var difficulty: CaromAIDifficulty
var puck: CaromPuck = null
var opponent_turret: CaromTurret = null

var current_state: int = State.ATTACK
var _reaction_timer: float = 0.0
var _fire_timer: float = 0.0
var _retarget_timer: float = 0.0
var _target_aim_degrees: float = 0.0
var _last_puck_position: Vector3 = Vector3.ZERO
var _puck_velocity_estimate: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()

# Arena midfield Z position (turrets are at opposite ends along Z)
var _midfield_z: float = 0.0
var _own_goal_z: float = 0.0


func _init(p_difficulty = null) -> void:
	if p_difficulty:
		difficulty = p_difficulty
	_rng.randomize()
	if difficulty:
		_fire_timer = difficulty.base_fire_interval * difficulty.fire_interval_multiplier
		_retarget_timer = difficulty.reaction_delay


func configure_arena(midfield_z: float, own_goal_z: float) -> void:
	_midfield_z = midfield_z
	_own_goal_z = own_goal_z


func set_puck(p_puck: CaromPuck) -> void:
	puck = p_puck
	if puck:
		_last_puck_position = puck.global_position


func set_opponent(p_opponent: CaromTurret) -> void:
	opponent_turret = p_opponent


func reset() -> void:
	current_state = State.ATTACK
	_reaction_timer = difficulty.reaction_delay
	_fire_timer = difficulty.base_fire_interval * difficulty.fire_interval_multiplier
	_retarget_timer = 0.0
	_target_aim_degrees = 0.0


func process(delta: float, turret_state: Dictionary) -> Dictionary:
	var is_active: bool = turret_state.get("is_active", true)
	if not is_active:
		return {}

	var ammo: int = turret_state.get("ammo", 0)
	var clip_size: int = turret_state.get("clip_size", 8)
	var is_reloading: bool = turret_state.get("is_reloading", false)
	var aim_offset: float = turret_state.get("aim_offset", 0.0)
	var aim_arc: float = turret_state.get("aim_arc", 160.0)
	var aim_speed: float = turret_state.get("aim_speed", 110.0)
	var base_yaw: float = turret_state.get("base_yaw", 180.0)
	var turret_position: Vector3 = turret_state.get("global_position", Vector3.ZERO)

	_update_puck_tracking(delta)
	_update_state_transitions(ammo, clip_size)

	# Update aim
	_update_aim_target(delta, aim_arc, base_yaw, turret_position)
	var new_aim := move_toward(aim_offset, _target_aim_degrees, aim_speed * delta * difficulty.aim_tracking_speed)

	# Update firing
	var fire := false
	var start_reload := false
	var cancel_reload := false

	_fire_timer -= delta
	if _fire_timer <= 0.0:
		match current_state:
			State.ATTACK, State.DEFEND, State.TRICK_SHOT:
				if ammo > 0:
					fire = true
					var interval := difficulty.base_fire_interval * difficulty.fire_interval_multiplier
					if current_state == State.DEFEND:
						interval *= 0.6
					_fire_timer = interval * _rng.randf_range(0.8, 1.2)
				else:
					start_reload = true
					_fire_timer = difficulty.base_fire_interval
			State.RELOAD_PRESSURE:
				_fire_timer = 0.3

	# Reload decision
	if is_reloading:
		if current_state == State.DEFEND and ammo > 0:
			if _rng.randf() < difficulty.reload_timing_quality:
				cancel_reload = true
	else:
		if current_state == State.RELOAD_PRESSURE:
			if ammo < clip_size:
				start_reload = true
		elif ammo <= 0:
			start_reload = true
		elif ammo <= difficulty.reload_threshold:
			var safe_to_reload := current_state == State.ATTACK and not _is_puck_threatening()
			if safe_to_reload and _rng.randf() < difficulty.reload_timing_quality:
				start_reload = true

	return {
		"aim_target": new_aim,
		"fire": fire,
		"start_reload": start_reload,
		"cancel_reload": cancel_reload,
	}


func _update_puck_tracking(delta: float) -> void:
	if not puck:
		return

	# Estimate puck velocity from position changes (with reaction delay)
	_reaction_timer -= delta
	if _reaction_timer <= 0.0:
		var current_pos := puck.global_position
		if _last_puck_position != Vector3.ZERO:
			_puck_velocity_estimate = (current_pos - _last_puck_position) / maxf(difficulty.reaction_delay, 0.01)
		_last_puck_position = current_pos
		_reaction_timer = difficulty.reaction_delay


func _update_state_transitions(ammo: int, clip_size: int) -> void:
	if not puck:
		current_state = State.ATTACK
		return

	# Roll decision quality — sometimes make suboptimal choices
	if _rng.randf() > difficulty.decision_quality:
		var roll := _rng.randf()
		if roll < 0.6:
			current_state = State.ATTACK
		elif roll < 0.85:
			current_state = State.DEFEND
		else:
			current_state = State.RELOAD_PRESSURE
		return

	# Optimal decision based on game state
	var puck_z := puck.global_position.z
	var puck_moving_toward_goal := false

	if _own_goal_z > _midfield_z:
		puck_moving_toward_goal = _puck_velocity_estimate.z > 1.0
	else:
		puck_moving_toward_goal = _puck_velocity_estimate.z < -1.0

	var puck_in_our_half := false
	if _own_goal_z > _midfield_z:
		puck_in_our_half = puck_z > _midfield_z
	else:
		puck_in_our_half = puck_z < _midfield_z

	# State selection
	if puck_moving_toward_goal and puck_in_our_half:
		current_state = State.DEFEND
	elif ammo <= difficulty.reload_threshold and not puck_in_our_half:
		current_state = State.RELOAD_PRESSURE
	elif difficulty.bank_shots_enabled and _should_try_bank_shot():
		current_state = State.TRICK_SHOT
	else:
		current_state = State.ATTACK


func _update_aim_target(_delta: float, aim_arc: float, base_yaw: float, turret_position: Vector3) -> void:
	_retarget_timer -= _delta
	if _retarget_timer > 0.0:
		return

	# Recalculate target aim
	match current_state:
		State.ATTACK:
			_target_aim_degrees = _calculate_attack_aim(base_yaw, aim_arc, turret_position)
		State.DEFEND:
			_target_aim_degrees = _calculate_defend_aim(base_yaw, aim_arc, turret_position)
		State.TRICK_SHOT:
			_target_aim_degrees = _calculate_bank_shot_aim(base_yaw, aim_arc, turret_position)
		State.RELOAD_PRESSURE:
			_target_aim_degrees = _rng.randf_range(
				-aim_arc * 0.3,
				aim_arc * 0.3
			)

	# Apply aim spread (inaccuracy)
	_target_aim_degrees += _rng.randf_range(
		-difficulty.aim_spread_degrees,
		difficulty.aim_spread_degrees
	)

	# Clamp to arc
	_target_aim_degrees = clampf(
		_target_aim_degrees,
		-aim_arc * 0.5,
		aim_arc * 0.5
	)

	_retarget_timer = difficulty.reaction_delay * _rng.randf_range(0.8, 1.4)


func _calculate_attack_aim(base_yaw: float, aim_arc: float, turret_position: Vector3) -> float:
	if not puck:
		return 0.0

	var to_puck := puck.global_position - turret_position
	var aim_angle := _vector_to_aim_degrees(to_puck, base_yaw, aim_arc)
	return aim_angle


func _calculate_defend_aim(base_yaw: float, aim_arc: float, turret_position: Vector3) -> float:
	if not puck:
		return 0.0

	# Predict where puck will be and aim to intercept
	var predicted_pos := puck.global_position + _puck_velocity_estimate * difficulty.reaction_delay * 2.0
	var to_predicted := predicted_pos - turret_position
	return _vector_to_aim_degrees(to_predicted, base_yaw, aim_arc)


func _calculate_bank_shot_aim(base_yaw: float, aim_arc: float, turret_position: Vector3) -> float:
	if not puck:
		return _calculate_attack_aim(base_yaw, aim_arc, turret_position)

	# Simple bank shot: aim at wall reflection point
	var puck_pos := puck.global_position
	var arena_half_width := 10.0

	var mirror_x: float
	if puck_pos.x > 0:
		mirror_x = arena_half_width * 2.0 - puck_pos.x
	else:
		mirror_x = -arena_half_width * 2.0 - puck_pos.x

	var bank_target := Vector3(mirror_x, 0.0, puck_pos.z)
	var to_target := bank_target - turret_position
	return _vector_to_aim_degrees(to_target, base_yaw, aim_arc)


func _should_try_bank_shot() -> bool:
	if not puck:
		return false
	# Try bank shots when puck is near a side wall and direct shot is blocked
	var puck_x := absf(puck.global_position.x)
	return puck_x > 6.0 and _rng.randf() < 0.3


## Returns a snapshot of AI debug state for the HUD overlay.
## Callers receive data, not internal object references.
func get_debug_info() -> Dictionary:
	var puck_pos := "N/A"
	var puck_vel := "N/A"
	if puck:
		puck_pos = "%.1f, %.1f" % [puck.global_position.x, puck.global_position.z]
		puck_vel = "%.1f, %.1f" % [_puck_velocity_estimate.x, _puck_velocity_estimate.z]
	const STATE_NAMES := ["ATTACK", "DEFEND", "RELOAD_PRESSURE", "TRICK_SHOT"]
	return {
		"state": STATE_NAMES[current_state] if current_state < STATE_NAMES.size() else "UNKNOWN",
		"difficulty": difficulty.difficulty_name if difficulty else "?",
		"target_aim": _target_aim_degrees,
		"puck_pos": puck_pos,
		"puck_vel": puck_vel,
		"puck_threatening": _is_puck_threatening(),
	}


func _is_puck_threatening() -> bool:
	if not puck:
		return false

	var puck_in_our_half: bool
	if _own_goal_z > _midfield_z:
		puck_in_our_half = puck.global_position.z > _midfield_z
	else:
		puck_in_our_half = puck.global_position.z < _midfield_z

	if not puck_in_our_half:
		return false

	# Check if moving toward our goal
	if _own_goal_z > _midfield_z:
		return _puck_velocity_estimate.z > 0.5
	else:
		return _puck_velocity_estimate.z < -0.5


func _vector_to_aim_degrees(direction: Vector3, base_yaw: float, aim_arc: float) -> float:
	# Convert a world-space direction vector into aim_offset_degrees
	var flat_dir := Vector2(direction.x, direction.z).normalized()
	if flat_dir.length_squared() < 0.001:
		return 0.0

	var world_angle := rad_to_deg(atan2(-flat_dir.x, -flat_dir.y))
	var offset := world_angle - base_yaw

	while offset > 180.0:
		offset -= 360.0
	while offset < -180.0:
		offset += 360.0

	return clampf(offset, -aim_arc * 0.5, aim_arc * 0.5)
