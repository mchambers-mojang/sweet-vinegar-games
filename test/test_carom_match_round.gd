extends GutTest

## Unit tests for CaromMatchRound — round lifecycle coordination.

const MatchRoundScript := preload("res://carom/scripts/carom_match_round.gd")
const ArenaScene := preload("res://carom/scenes/carom_arena.tscn")
const MatchSetupScript := preload("res://carom/scripts/carom_match_setup.gd")


func _make_configured_round() -> CaromMatchRound:
	var arena := ArenaScene.instantiate() as CaromArena
	add_child_autofree(arena)
	await get_tree().process_frame

	var setup := arena.get_node("MatchSetup") as CaromMatchSetup
	setup.spawn_entities(arena, arena.get_node("Actors"), 1)
	await get_tree().process_frame

	var round: CaromMatchRound = MatchRoundScript.new()
	round.configure(arena, setup)
	return round


# --- configure ---

func test_get_player_turret_returns_null_before_configure() -> void:
	var round: CaromMatchRound = MatchRoundScript.new()
	assert_null(round.get_player_turret())


func test_get_ai_turret_returns_null_before_configure() -> void:
	var round: CaromMatchRound = MatchRoundScript.new()
	assert_null(round.get_ai_turret())


func test_get_player_turret_returns_turret_after_configure() -> void:
	var round := await _make_configured_round()
	assert_not_null(round.get_player_turret())
	assert_true(round.get_player_turret() is CaromTurret)


func test_get_ai_turret_returns_turret_after_configure() -> void:
	var round := await _make_configured_round()
	assert_not_null(round.get_ai_turret())
	assert_true(round.get_ai_turret() is CaromTurret)


# --- start_round ---

func test_start_round_activates_player_turret() -> void:
	var round := await _make_configured_round()
	round.get_player_turret().set_active(false)
	round.start_round()
	assert_true(round.get_player_turret().is_active)


func test_start_round_activates_ai_turret() -> void:
	var round := await _make_configured_round()
	round.get_ai_turret().set_active(false)
	round.start_round()
	assert_true(round.get_ai_turret().is_active)


func test_start_round_emits_round_ready() -> void:
	var round := await _make_configured_round()
	var emitted := false
	round.round_ready.connect(func() -> void:
		emitted = true
	)
	round.start_round()
	assert_true(emitted)


# --- end_round ---

func test_end_round_deactivates_player_turret() -> void:
	var round := await _make_configured_round()
	round.start_round()
	round.end_round()
	assert_false(round.get_player_turret().is_active)


func test_end_round_deactivates_ai_turret() -> void:
	var round := await _make_configured_round()
	round.start_round()
	round.end_round()
	assert_false(round.get_ai_turret().is_active)


# --- unlock_goals ---

func test_unlock_goals_clears_goal_lock() -> void:
	var arena := ArenaScene.instantiate() as CaromArena
	add_child_autofree(arena)
	await get_tree().process_frame

	var setup := arena.get_node("MatchSetup") as CaromMatchSetup
	setup.spawn_entities(arena, arena.get_node("Actors"), 1)
	await get_tree().process_frame

	var round: CaromMatchRound = MatchRoundScript.new()
	round.configure(arena, setup)

	arena.lock_goals()
	assert_true(arena._goal_locked, "Goal should be locked before unlock_goals()")
	round.unlock_goals()
	assert_false(arena._goal_locked, "unlock_goals() must clear the goal lock")
