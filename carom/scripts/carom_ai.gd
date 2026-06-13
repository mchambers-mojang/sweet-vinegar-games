class_name CaromAI
extends RefCounted

## AI controller that drives a CaromTurret based on game state.
## Uses a state machine with puck awareness and difficulty-scaled behavior.

enum State {
	ATTACK,
	DEFEND,
	RELOAD_PRESSURE,
	TRICK_SHOT,
}

var turret: CaromTurret
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


func _init(p_turret = null, p_difficulty = null) -> void:
	if p_turret:
		turret = p_turret
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


func process(delta: float) -> void:
	if not turret or not turret.is_active:
		return

	_update_puck_tracking(delta)
	_update_state_transitions()
	_update_aim(delta)
	_update_firing(delta)
	_update_reload_decision()


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


func _update_state_transitions() -> void:
	if not puck:
		current_state = State.ATTACK
		return

	# Roll decision quality — sometimes make suboptimal choices
	if _rng.randf() > difficulty.decision_quality:
		# Random state with bias toward attack
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

	# Determine if puck is heading toward our goal
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
	elif turret.current_ammo <= difficulty.reload_threshold and not puck_in_our_half:
		current_state = State.RELOAD_PRESSURE
	elif difficulty.bank_shots_enabled and _should_try_bank_shot():
		current_state = State.TRICK_SHOT
	else:
		current_state = State.ATTACK


func _update_aim(delta: float) -> void:
	_retarget_timer -= delta
	if _retarget_timer > 0.0:
		# Smoothly move toward current target
		turret.aim_offset_degrees = move_toward(
			turret.aim_offset_degrees,
			_target_aim_degrees,
			turret.aim_speed_degrees * delta * difficulty.aim_tracking_speed
		)
		return

	# Recalculate target aim
	match current_state:
		State.ATTACK:
			_target_aim_degrees = _calculate_attack_aim()
		State.DEFEND:
			_target_aim_degrees = _calculate_defend_aim()
		State.TRICK_SHOT:
			_target_aim_degrees = _calculate_bank_shot_aim()
		State.RELOAD_PRESSURE:
			# Sweep randomly while reloading
			_target_aim_degrees = _rng.randf_range(
				-turret.aim_arc_degrees * 0.3,
				turret.aim_arc_degrees * 0.3
			)

	# Apply aim spread (inaccuracy)
	_target_aim_degrees += _rng.randf_range(
		-difficulty.aim_spread_degrees,
		difficulty.aim_spread_degrees
	)

	# Clamp to arc
	_target_aim_degrees = clampf(
		_target_aim_degrees,
		-turret.aim_arc_degrees * 0.5,
		turret.aim_arc_degrees * 0.5
	)

	_retarget_timer = difficulty.reaction_delay * _rng.randf_range(0.8, 1.4)

	# Apply aim movement
	turret.aim_offset_degrees = move_toward(
		turret.aim_offset_degrees,
		_target_aim_degrees,
		turret.aim_speed_degrees * delta * difficulty.aim_tracking_speed
	)


func _update_firing(delta: float) -> void:
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return

	match current_state:
		State.ATTACK, State.DEFEND, State.TRICK_SHOT:
			if turret.current_ammo > 0:
				# In DEFEND, fire more aggressively
				turret.try_fire()
				var interval := difficulty.base_fire_interval * difficulty.fire_interval_multiplier
				if current_state == State.DEFEND:
					interval *= 0.6
				_fire_timer = interval * _rng.randf_range(0.8, 1.2)
			else:
				turret.start_reload()
				_fire_timer = difficulty.base_fire_interval
		State.RELOAD_PRESSURE:
			# Don't fire, focus on reloading
			_fire_timer = 0.3


func _update_reload_decision() -> void:
	if turret.is_reloading:
		# Interrupt reload to fire if puck is threatening
		if current_state == State.DEFEND and turret.current_ammo > 0:
			if _rng.randf() < difficulty.reload_timing_quality:
				turret.cancel_reload()
		return

	if current_state == State.RELOAD_PRESSURE:
		if turret.current_ammo < turret.clip_size:
			turret.start_reload()
	elif turret.current_ammo <= 0:
		turret.start_reload()
	elif turret.current_ammo <= difficulty.reload_threshold:
		# Reload early if safe to do so
		var safe_to_reload := current_state == State.ATTACK and not _is_puck_threatening()
		if safe_to_reload and _rng.randf() < difficulty.reload_timing_quality:
			turret.start_reload()


func _calculate_attack_aim() -> float:
	if not puck:
		return 0.0

	# Aim at puck position, offset to push toward opponent's goal
	var to_puck := puck.global_position - turret.global_position
	var aim_angle := _vector_to_aim_degrees(to_puck)
	return aim_angle


func _calculate_defend_aim() -> float:
	if not puck:
		return 0.0

	# Predict where puck will be and aim to intercept
	var predicted_pos := puck.global_position + _puck_velocity_estimate * difficulty.reaction_delay * 2.0
	var to_predicted := predicted_pos - turret.global_position
	return _vector_to_aim_degrees(to_predicted)


func _calculate_bank_shot_aim() -> float:
	if not puck:
		return _calculate_attack_aim()

	# Simple bank shot: aim at wall reflection point
	# Mirror puck position across nearest side wall to find bank target
	var puck_pos := puck.global_position
	var arena_half_width := 10.0  # Approximate half-width

	# Choose the wall closest to the puck's X position
	var mirror_x: float
	if puck_pos.x > 0:
		mirror_x = arena_half_width * 2.0 - puck_pos.x
	else:
		mirror_x = -arena_half_width * 2.0 - puck_pos.x

	var bank_target := Vector3(mirror_x, 0.0, puck_pos.z)
	var to_target := bank_target - turret.global_position
	return _vector_to_aim_degrees(to_target)


func _should_try_bank_shot() -> bool:
	if not puck:
		return false
	# Try bank shots when puck is near a side wall and direct shot is blocked
	var puck_x := absf(puck.global_position.x)
	return puck_x > 6.0 and _rng.randf() < 0.3


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


func _vector_to_aim_degrees(direction: Vector3) -> float:
	# Convert a world-space direction vector into aim_offset_degrees
	# relative to the turret's base yaw
	var flat_dir := Vector2(direction.x, direction.z).normalized()
	if flat_dir.length_squared() < 0.001:
		return 0.0

	# Angle of direction in world space (0 = +Z, clockwise)
	var world_angle := rad_to_deg(atan2(-flat_dir.x, -flat_dir.y))

	# Offset from turret's base facing
	var offset := world_angle - turret.base_yaw_degrees

	# Normalize to [-180, 180]
	while offset > 180.0:
		offset -= 360.0
	while offset < -180.0:
		offset += 360.0

	return clampf(offset, -turret.aim_arc_degrees * 0.5, turret.aim_arc_degrees * 0.5)
