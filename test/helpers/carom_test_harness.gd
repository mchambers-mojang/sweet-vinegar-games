class_name CaromTestHarness
extends RefCounted

## Shared test helper for Carom GUT tests.
##
## Owns the CaromArena lifecycle and exposes typed accessors so tests do not
## need to reach past module interfaces (internal arrays, private fields, etc.).
##
## Typical usage (bridge + arena tests):
##
##   var h := CaromTestHarness.new()
##   await h.setup_arena(self)
##   h.setup_bridge()
##   ...
##
## Typical usage (full match round tests):
##
##   var h := CaromTestHarness.new()
##   await h.setup_arena(self)
##   await h.spawn_entities(self)
##   var round := MatchRoundScript.new()
##   round.configure(h.arena, h.setup)

const ArenaScene := preload("res://carom/scenes/carom_arena.tscn")
const BridgeScript := preload("res://carom/scripts/carom_sim_bridge.gd")

## Live arena node. Available after setup_arena().
var arena: CaromArena = null

## SimBridge attached to the arena. Available after setup_bridge().
var bridge: CaromSimBridge = null

## Entity-spawn record. Available after spawn_entities().
var setup: CaromMatchSetup = null

var _sim_tick_count: int = 0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Instantiate the arena, register it for auto-free with the given GUT test,
## and wait one process frame so @onready vars are populated.
## Must be called with await.
func setup_arena(test: GutTest) -> void:
	arena = ArenaScene.instantiate() as CaromArena
	test.add_child_autofree(arena)
	await test.get_tree().process_frame


## Create a CaromSimBridge, add it to the arena, and initialise it.
## Call after setup_arena().
func setup_bridge() -> void:
	bridge = BridgeScript.new() as CaromSimBridge
	bridge.name = "TestBridge"
	arena.add_child(bridge)
	bridge.setup_arena(arena)


## Spawn turrets and pucks for a full match, then wait one process frame.
## Reads CaromMatchSetup from the arena scene and stores it in setup.
## Must be called with await.
func spawn_entities(test: GutTest, ai_difficulty: int = 1) -> void:
	setup = arena.get_node("MatchSetup") as CaromMatchSetup
	setup.spawn_entities(arena, arena.get_node("Actors"), ai_difficulty)
	await test.get_tree().process_frame


# ---------------------------------------------------------------------------
# Typed accessors — arena state
# ---------------------------------------------------------------------------

## Returns whether the arena goal is currently locked.
## Wraps the private arena._goal_locked field so tests do not reach into it.
func is_goal_locked() -> bool:
	return arena._goal_locked


# ---------------------------------------------------------------------------
# Typed accessors — bridge / sim state
# ---------------------------------------------------------------------------

## Returns the interpolated 3D world position of puck at the given alpha.
## Delegates to CaromSimBridge.get_puck_position().
func get_puck_position(puck: CaromPuck, alpha: float) -> Vector3:
	return bridge.get_puck_position(puck, alpha)


## Returns the SimBody for the given puck without exposing bridge internals.
## Returns null if the puck is not registered.
func get_sim_body_for_puck(puck: CaromPuck) -> SimBody:
	var idx := _get_puck_index(puck)
	if idx < 0:
		return null
	return bridge._sim.get_body(bridge._puck_body_ids[idx])


## Returns the sim body-ID for the given puck (used in signal assertions).
## Returns -1 if the puck is not registered.
func get_puck_body_id(puck: CaromPuck) -> int:
	var idx := _get_puck_index(puck)
	if idx < 0:
		return -1
	return bridge._puck_body_ids[idx]


func _get_puck_index(puck: CaromPuck) -> int:
	return bridge._puck_nodes.find(puck)


## Returns the number of sim ticks executed via run_ticks() since setup.
func get_sim_tick_count() -> int:
	return _sim_tick_count


## Execute count bridge ticks and accumulate the tick counter.
func run_ticks(count: int) -> void:
	for _i in range(count):
		bridge._tick()
	_sim_tick_count += count


# ---------------------------------------------------------------------------
# Typed accessors — match setup
# ---------------------------------------------------------------------------

## Returns the player turret from the match setup, or null if not spawned.
func get_player_turret() -> CaromTurret:
	return setup.player_turret if setup else null


## Returns the AI turret from the match setup, or null if not spawned.
func get_ai_turret() -> CaromTurret:
	return setup.ai_turret if setup else null
