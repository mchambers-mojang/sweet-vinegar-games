extends GutTest

## Unit tests for CaromAI — difficulty presets, state transitions, and aim calculations.

const AIDifficultyScript := preload("res://carom/scripts/carom_ai_difficulty.gd")
const TurretScript := preload("res://carom/scripts/carom_turret.gd")
const PuckScript := preload("res://carom/scripts/carom_puck.gd")

var AIScript: GDScript


func before_all() -> void:
	AIScript = load("res://carom/scripts/carom_ai.gd") as GDScript


# --- Difficulty Presets ---

func test_easy_preset_values() -> void:
	var d = AIDifficultyScript.easy()
	assert_eq(d.difficulty_name, "Easy")
	assert_gt(d.reaction_delay, 0.4, "Easy should have slow reactions")
	assert_gt(d.aim_spread_degrees, 20.0, "Easy should have high spread")
	assert_eq(d.bank_shots_enabled, false)


func test_hard_preset_values() -> void:
	var d = AIDifficultyScript.hard()
	assert_eq(d.difficulty_name, "Hard")
	assert_lt(d.reaction_delay, 0.2, "Hard should have fast reactions")
	assert_lt(d.aim_spread_degrees, 10.0, "Hard should have low spread")
	assert_eq(d.bank_shots_enabled, true)


func test_brutal_preset_values() -> void:
	var d = AIDifficultyScript.brutal()
	assert_eq(d.difficulty_name, "Brutal")
	assert_lt(d.aim_spread_degrees, 5.0)
	assert_gt(d.decision_quality, 0.95)


func test_get_preset_returns_correct_tier() -> void:
	assert_eq(AIDifficultyScript.get_preset(0).difficulty_name, "Easy")
	assert_eq(AIDifficultyScript.get_preset(1).difficulty_name, "Medium")
	assert_eq(AIDifficultyScript.get_preset(2).difficulty_name, "Hard")
	assert_eq(AIDifficultyScript.get_preset(3).difficulty_name, "Brutal")


func test_get_preset_invalid_returns_medium() -> void:
	assert_eq(AIDifficultyScript.get_preset(99).difficulty_name, "Medium")
	assert_eq(AIDifficultyScript.get_preset(-1).difficulty_name, "Medium")


# --- Difficulty scaling consistency ---

func test_difficulty_tiers_scale_monotonically() -> void:
	var presets: Array = [
		AIDifficultyScript.easy(),
		AIDifficultyScript.medium(),
		AIDifficultyScript.hard(),
		AIDifficultyScript.brutal(),
	]
	# Reaction delay should decrease with difficulty
	for i in range(1, presets.size()):
		assert_lt(presets[i].reaction_delay, presets[i - 1].reaction_delay,
			"Reaction delay should decrease: %s < %s" % [presets[i].difficulty_name, presets[i - 1].difficulty_name])

	# Aim spread should decrease with difficulty
	for i in range(1, presets.size()):
		assert_lt(presets[i].aim_spread_degrees, presets[i - 1].aim_spread_degrees,
			"Aim spread should decrease: %s < %s" % [presets[i].difficulty_name, presets[i - 1].difficulty_name])

	# Decision quality should increase with difficulty
	for i in range(1, presets.size()):
		assert_gt(presets[i].decision_quality, presets[i - 1].decision_quality,
			"Decision quality should increase: %s > %s" % [presets[i].difficulty_name, presets[i - 1].difficulty_name])


# --- AI State Machine ---

func _create_turret() -> Node3D:
	var turret = Node3D.new()
	turret.set_script(TurretScript)
	turret.clip_size = 8
	turret.current_ammo = 8
	turret.aim_arc_degrees = 90.0
	turret.base_yaw_degrees = 180.0
	turret.aim_speed_degrees = 110.0
	turret.control_mode = 1  # AI
	turret.is_active = true
	# Add a Marker3D as ProjectileSpawn
	var marker := Marker3D.new()
	marker.name = "ProjectileSpawn"
	turret.add_child(marker)
	return turret


func _create_ai(turret, difficulty = null):
	if difficulty == null:
		difficulty = AIDifficultyScript.medium()
	var ai = AIScript.new(turret, difficulty)
	ai.configure_arena(13.0, 26.0)  # midfield=13, own_goal=26 (south end)
	return ai


func test_ai_starts_in_attack_state() -> void:
	var turret = _create_turret()
	add_child_autofree(turret)
	var ai = _create_ai(turret)
	assert_eq(ai.current_state, 0)  # ATTACK = 0


func test_ai_reset_restores_attack_state() -> void:
	var turret = _create_turret()
	add_child_autofree(turret)
	var ai = _create_ai(turret)
	ai.current_state = 1  # DEFEND
	ai.reset()
	assert_eq(ai.current_state, 0)  # ATTACK


func test_ai_defends_when_puck_approaches_goal() -> void:
	var turret = _create_turret()
	add_child_autofree(turret)
	var difficulty = AIDifficultyScript.brutal()
	var ai = _create_ai(turret, difficulty)

	var puck = RigidBody3D.new()
	puck.set_script(PuckScript)
	add_child_autofree(puck)
	puck.global_position = Vector3(0, 0, 20)  # In AI's half (past midfield 13)

	ai.set_puck(puck)
	ai._puck_velocity_estimate = Vector3(0, 0, 5.0)
	ai._last_puck_position = puck.global_position

	ai._update_state_transitions()
	assert_eq(ai.current_state, 1,  # DEFEND
		"AI should defend when puck is in its half and moving toward goal")


func test_ai_reloads_when_low_ammo_and_puck_far() -> void:
	var turret = _create_turret()
	add_child_autofree(turret)
	var difficulty = AIDifficultyScript.brutal()
	difficulty.reload_threshold = 3
	var ai = _create_ai(turret, difficulty)

	turret.current_ammo = 2  # Below threshold

	var puck = RigidBody3D.new()
	puck.set_script(PuckScript)
	add_child_autofree(puck)
	puck.global_position = Vector3(0, 0, 5)  # Opponent's half

	ai.set_puck(puck)
	ai._puck_velocity_estimate = Vector3(0, 0, -2.0)

	ai._update_state_transitions()
	assert_eq(ai.current_state, 2,  # RELOAD_PRESSURE
		"AI should reload when low ammo and puck is far from goal")


func test_ai_attacks_when_puck_in_opponent_half() -> void:
	var turret = _create_turret()
	add_child_autofree(turret)
	var difficulty = AIDifficultyScript.brutal()
	var ai = _create_ai(turret, difficulty)

	turret.current_ammo = 6

	var puck = RigidBody3D.new()
	puck.set_script(PuckScript)
	add_child_autofree(puck)
	puck.global_position = Vector3(0, 0, 5)  # Opponent's half

	ai.set_puck(puck)
	ai._puck_velocity_estimate = Vector3(0, 0, -1.0)

	ai._update_state_transitions()
	assert_eq(ai.current_state, 0,  # ATTACK
		"AI should attack when puck is in opponent's half and ammo is fine")


# --- Aim Calculation ---

func test_vector_to_aim_degrees_straight_ahead() -> void:
	var turret = _create_turret()
	add_child_autofree(turret)
	turret.base_yaw_degrees = 180.0
	var ai = _create_ai(turret)

	var aim = ai._vector_to_aim_degrees(Vector3(0, 0, 1))
	assert_almost_eq(aim, 0.0, 5.0, "Straight-ahead aim should be near 0 offset")


func test_vector_to_aim_degrees_clamped_to_arc() -> void:
	var turret = _create_turret()
	add_child_autofree(turret)
	turret.aim_arc_degrees = 90.0
	turret.base_yaw_degrees = 180.0
	var ai = _create_ai(turret)

	var aim = ai._vector_to_aim_degrees(Vector3(100, 0, 0.01))
	assert_lte(absf(aim), turret.aim_arc_degrees * 0.5,
		"Aim should be clamped within arc")
