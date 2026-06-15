class_name CaromMatchRound
extends RefCounted

## Coordinates round lifecycle operations between arena and actors.
## Encapsulates puck reset, goal locking, and turret activation/deactivation.
## CaromMatchController delegates all physical round setup to this class.

signal round_ready

var _arena: CaromArena = null
var _setup: CaromMatchSetup = null


## Configure with arena and setup references. Must be called after spawn_entities.
func configure(arena: CaromArena, setup: CaromMatchSetup) -> void:
	_arena = arena
	_setup = setup


## Unlock goals, reset pucks to spawn positions, and activate turrets for a new round.
## Emits round_ready when complete.
func start_round() -> void:
	_arena.reset_goal_lock()

	var spawn_positions := _arena.get_puck_spawn_positions()
	for i in _setup.pucks.size():
		if is_instance_valid(_setup.pucks[i]):
			var reset_pos: Vector3 = spawn_positions[i] if i < spawn_positions.size() else _arena.get_puck_spawn_position()
			_setup.pucks[i].reset_to_center(reset_pos)

	_setup.player_turret.reset_for_round()
	_setup.ai_turret.reset_for_round()
	_setup.player_turret.set_active(true)
	_setup.ai_turret.set_active(true)

	round_ready.emit()


## Deactivate turrets and lock goals to end the current round.
func end_round() -> void:
	_setup.player_turret.set_active(false)
	_setup.ai_turret.set_active(false)
	_arena.lock_goals()


## Unlock goals to allow the next scoring opportunity (used after a mid-round goal).
func unlock_goals() -> void:
	_arena.reset_goal_lock()


## Read-only access to the player turret for effects and haptics.
func get_player_turret() -> CaromTurret:
	if _setup == null:
		return null
	return _setup.player_turret


## Read-only access to the AI turret for effects and debug overlay.
func get_ai_turret() -> CaromTurret:
	if _setup == null:
		return null
	return _setup.ai_turret
