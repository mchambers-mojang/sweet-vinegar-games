extends GutTest

## Tests for CaromSimBridge — verifies that the bridge advances the sim,
## provides interpolated positions, and emits zone events correctly.
## All tests use pure-code sim setup (no scene instantiation) to stay fast
## and headless-friendly.

const BridgeScript    := preload("res://carom/scripts/carom_sim_bridge.gd")
const SimWorldScript  := preload("res://carom/scripts/sim/sim_world.gd")
const SimBodyScript   := preload("res://carom/scripts/sim/sim_body.gd")
const SimWallScript   := preload("res://carom/scripts/sim/sim_wall.gd")
const SimZoneScript   := preload("res://carom/scripts/sim/sim_zone.gd")
const PuckScene       := preload("res://carom/scenes/carom_puck.tscn")
const ArenaScene      := preload("res://carom/scenes/carom_arena.tscn")


# ---------------------------------------------------------------------------
# Helper — build a bridge with arena wired up
# ---------------------------------------------------------------------------

func _make_bridge_with_arena() -> Dictionary:
	var arena := ArenaScene.instantiate() as CaromArena
	add_child_autofree(arena)
	var bridge := BridgeScript.new() as CaromSimBridge
	bridge.name = "TestBridge"
	arena.add_child(bridge)
	bridge.setup_arena(arena)
	return {arena = arena, bridge = bridge}


# ---------------------------------------------------------------------------
# 1. Bridge instantiates and sets up without errors
# ---------------------------------------------------------------------------

func test_bridge_setup_arena_does_not_crash() -> void:
	var result := _make_bridge_with_arena()
	assert_not_null(result.bridge)


# ---------------------------------------------------------------------------
# 2. Registering a puck gives it a sim body and calls setup_sim_bridge
# ---------------------------------------------------------------------------

func test_register_puck_sets_bridge_on_puck() -> void:
	var result := _make_bridge_with_arena()
	var bridge: CaromSimBridge = result.bridge
	var arena: CaromArena = result.arena

	var puck := PuckScene.instantiate() as CaromPuck
	arena.get_node("Actors").add_child(puck)
	await get_tree().process_frame

	bridge.register_puck(puck, puck.global_position)
	assert_eq(puck._bridge, bridge, "Puck should hold a reference to the bridge after registration")


# ---------------------------------------------------------------------------
# 3. After advancing one tick, the puck position changes (it was nudged by
#    the stall force toward a goal — start from centre with no velocity)
# ---------------------------------------------------------------------------

func test_puck_position_changes_after_tick() -> void:
	var result := _make_bridge_with_arena()
	var bridge: CaromSimBridge = result.bridge
	var arena: CaromArena = result.arena

	var puck := PuckScene.instantiate() as CaromPuck
	arena.get_node("Actors").add_child(puck)
	await get_tree().process_frame

	var start_pos := Vector3(0.0, 0.0, 12.0)
	puck.global_position = start_pos
	puck.configure(arena.get_goal_targets(), start_pos)
	bridge.register_puck(puck, start_pos)

	# Force at least one sim tick by advancing time.
	# Simulate process(delta) manually.
	bridge._process(1.0 / 30.0)

	var new_pos := bridge.get_puck_position(puck, 1.0)
	# Stall nudge must have moved the puck at least a tiny amount.
	var moved := start_pos.distance_to(new_pos)
	assert_gt(moved, 0.0, "Puck should move after sim tick")


# ---------------------------------------------------------------------------
# 4. get_render_alpha returns 0 before any delta, ~0.5 after half tick
# ---------------------------------------------------------------------------

func test_render_alpha_interpolates_between_zero_and_one() -> void:
	var result := _make_bridge_with_arena()
	var bridge: CaromSimBridge = result.bridge

	# No time has passed — accumulator is 0
	assert_almost_eq(bridge.get_render_alpha(), 0.0, 0.01)

	# Advance half a tick
	bridge._process(1.0 / 60.0)
	var alpha := bridge.get_render_alpha()
	assert_gt(alpha, 0.0, "Alpha should be > 0 after half-tick delta")
	assert_lt(alpha, 1.0, "Alpha should be < 1 before full tick completes")


# ---------------------------------------------------------------------------
# 5. Zone event fires when puck body enters a goal zone
# ---------------------------------------------------------------------------

func test_puck_zone_event_fires_when_puck_enters_goal() -> void:
	var result := _make_bridge_with_arena()
	var bridge: CaromSimBridge = result.bridge
	var arena: CaromArena = result.arena

	var puck := PuckScene.instantiate() as CaromPuck
	arena.get_node("Actors").add_child(puck)
	await get_tree().process_frame

	# Place puck just above the north goal (z ≈ -0.4 in world space) so that
	# a single tick with velocity -5 u/s carries it inside the zone.
	var north_goal_z: float = arena.north_goal.global_position.z  # ≈ -0.4
	var start_pos := Vector3(0.0, 0.0, north_goal_z + 0.6)  # 0.6 units north of the goal line
	puck.global_position = start_pos
	puck.configure(arena.get_goal_targets(), start_pos)
	bridge.register_puck(puck, start_pos)

	# Give the puck a velocity aimed into the goal zone.
	var puck_body_idx := bridge._puck_nodes.find(puck)
	var puck_body_id: int = bridge._puck_body_ids[puck_body_idx]
	var body := bridge._sim.get_body(puck_body_id)
	body.velocity = FP.FPVec2.make(0, FP.from_int(-5))  # moving toward z = negative

	watch_signals(bridge)

	# Run enough ticks to cross into the goal zone.
	for _i in range(10):
		bridge._tick()

	assert_signal_emitted(bridge, "puck_zone_entered",
		"puck_zone_entered should fire when puck crosses into ZONE_NORTH_GOAL")
	var params: Array = get_signal_parameters(bridge, "puck_zone_entered")
	assert_eq(params[0], puck_body_id, "Signal body_id should match the registered puck")
	assert_eq(params[1], CaromSimBridge.ZONE_NORTH_GOAL, "Signal zone_id should be ZONE_NORTH_GOAL")


# ---------------------------------------------------------------------------
# 6. reset_puck_to teleports sim body and zeroes velocity
# ---------------------------------------------------------------------------

func test_reset_puck_to_zeroes_velocity_and_sets_position() -> void:
	var result := _make_bridge_with_arena()
	var bridge: CaromSimBridge = result.bridge
	var arena: CaromArena = result.arena

	var puck := PuckScene.instantiate() as CaromPuck
	arena.get_node("Actors").add_child(puck)
	await get_tree().process_frame

	bridge.register_puck(puck, Vector3(0, 0, 12))

	var idx := bridge._puck_nodes.find(puck)
	var body := bridge._sim.get_body(bridge._puck_body_ids[idx])
	# Give it some velocity
	body.velocity = FP.FPVec2.make(FP.from_int(3), FP.from_int(3))

	bridge.reset_puck_to(puck, Vector3(1.0, 0.0, 12.0))

	assert_almost_eq(FP.to_float(body.velocity.x), 0.0, 0.001, "velocity.x should be zero after reset")
	assert_almost_eq(FP.to_float(body.velocity.y), 0.0, 0.001, "velocity.y should be zero after reset")
	assert_almost_eq(FP.to_float(body.position.x), 1.0, 0.01, "position.x should be reset target")
	assert_almost_eq(FP.to_float(body.position.y), 12.0, 0.01, "position.y should be reset target")


# ---------------------------------------------------------------------------
# 7. CaromMatchSetup.configure_sim_bridge registers all spawned actors
# ---------------------------------------------------------------------------

func test_configure_sim_bridge_registers_pucks() -> void:
	var result := _make_bridge_with_arena()
	var bridge: CaromSimBridge = result.bridge
	var arena: CaromArena = result.arena

	var setup := arena.get_node("MatchSetup") as CaromMatchSetup
	setup.spawn_entities(arena, arena.get_node("Actors"), 1)
	await get_tree().process_frame

	setup.configure_sim_bridge(bridge)

	# The puck should now hold a back-reference to the bridge
	assert_not_null(setup.pucks[0]._bridge,
		"Puck should be registered with the bridge after configure_sim_bridge()")
	assert_eq(setup.pucks[0]._bridge, bridge,
		"Puck _bridge reference should point to the provided bridge")
