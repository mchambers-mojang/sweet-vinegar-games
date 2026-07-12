extends GutTest

## Tests for CaromSimBridge — verifies that the bridge advances the sim,
## provides interpolated positions, and emits zone events correctly.
## All tests use pure-code sim setup (no scene instantiation) to stay fast
## and headless-friendly.

const PuckScene := preload("res://carom/scenes/carom_puck.tscn")

const CaromTestHarness := preload("res://test/helpers/carom_test_harness.gd")


# ---------------------------------------------------------------------------
# Helper — build a harness with arena and bridge wired up
# ---------------------------------------------------------------------------

func _make_harness() -> CaromTestHarness:
	var h := CaromTestHarness.new()
	await h.setup_arena(self)
	h.setup_bridge()
	return h


# ---------------------------------------------------------------------------
# 1. Bridge instantiates and sets up without errors
# ---------------------------------------------------------------------------

func test_bridge_setup_arena_does_not_crash() -> void:
	var h := await _make_harness()
	assert_not_null(h.bridge)


# ---------------------------------------------------------------------------
# 2. Registering a puck gives it a sim body and calls setup_sim_bridge
# ---------------------------------------------------------------------------

func test_register_puck_sets_bridge_on_puck() -> void:
	var h := await _make_harness()

	var puck := PuckScene.instantiate() as CaromPuck
	h.arena.get_node("Actors").add_child(puck)
	await get_tree().process_frame

	h.bridge.register_puck(puck, puck.global_position)
	assert_eq(puck._bridge, h.bridge, "Puck should hold a reference to the bridge after registration")


# ---------------------------------------------------------------------------
# 3. After advancing one tick, the puck position changes (it was nudged by
#    the stall force toward a goal — start from centre with no velocity)
# ---------------------------------------------------------------------------

func test_puck_position_changes_after_tick() -> void:
	var h := await _make_harness()

	var puck := PuckScene.instantiate() as CaromPuck
	h.arena.get_node("Actors").add_child(puck)
	await get_tree().process_frame

	var start_pos := Vector3(0.0, 0.0, 12.0)
	puck.global_position = start_pos
	puck.configure(h.arena.get_goal_targets(), start_pos)
	h.bridge.register_puck(puck, start_pos)

	# Force at least one sim tick by advancing time.
	# Simulate process(delta) manually.
	h.bridge._process(1.0 / 30.0)

	var new_pos := h.get_puck_position(puck, 1.0)
	# Stall nudge must have moved the puck at least a tiny amount.
	var moved := start_pos.distance_to(new_pos)
	assert_gt(moved, 0.0, "Puck should move after sim tick")


# ---------------------------------------------------------------------------
# 4. get_render_alpha returns 0 before any delta, ~0.5 after half tick
# ---------------------------------------------------------------------------

func test_render_alpha_interpolates_between_zero_and_one() -> void:
	var h := await _make_harness()

	# No time has passed — accumulator is 0
	assert_almost_eq(h.bridge.get_render_alpha(), 0.0, 0.01)

	# Advance half a tick
	h.bridge._process(1.0 / 60.0)
	var alpha := h.bridge.get_render_alpha()
	assert_gt(alpha, 0.0, "Alpha should be > 0 after half-tick delta")
	assert_lt(alpha, 1.0, "Alpha should be < 1 before full tick completes")


# ---------------------------------------------------------------------------
# 5. Zone event fires when puck body enters a goal zone
# ---------------------------------------------------------------------------

func test_puck_zone_event_fires_when_puck_enters_goal() -> void:
	var h := await _make_harness()

	var puck := PuckScene.instantiate() as CaromPuck
	h.arena.get_node("Actors").add_child(puck)
	await get_tree().process_frame

	# Place puck just above the north goal (z ≈ -0.4 in world space) so that
	# a single tick with velocity -5 u/s carries it inside the zone.
	var north_goal_z: float = h.arena.north_goal.global_position.z  # ≈ -0.4
	var start_pos := Vector3(0.0, 0.0, north_goal_z + 0.6)  # 0.6 units north of the goal line
	puck.global_position = start_pos
	puck.configure(h.arena.get_goal_targets(), start_pos)
	h.bridge.register_puck(puck, start_pos)

	# Give the puck a velocity aimed into the goal zone.
	var body := h.get_sim_body_for_puck(puck)
	body.velocity = FP.FPVec2.make(0, FP.from_int(-5))  # moving toward z = negative

	watch_signals(h.bridge)

	# Run enough ticks to cross into the goal zone.
	h.run_ticks(10)

	assert_signal_emitted(h.bridge, "puck_zone_entered",
		"puck_zone_entered should fire when puck crosses into ZONE_NORTH_GOAL")
	var params: Array = get_signal_parameters(h.bridge, "puck_zone_entered")
	var puck_body_id := h.get_puck_body_id(puck)
	assert_eq(params[0], puck_body_id, "Signal body_id should match the registered puck")
	assert_eq(params[1], CaromSimBridge.ZONE_NORTH_GOAL, "Signal zone_id should be ZONE_NORTH_GOAL")


# ---------------------------------------------------------------------------
# 6. reset_puck_to teleports sim body and zeroes velocity
# ---------------------------------------------------------------------------

func test_reset_puck_to_zeroes_velocity_and_sets_position() -> void:
	var h := await _make_harness()

	var puck := PuckScene.instantiate() as CaromPuck
	h.arena.get_node("Actors").add_child(puck)
	await get_tree().process_frame

	h.bridge.register_puck(puck, Vector3(0, 0, 12))

	var body := h.get_sim_body_for_puck(puck)
	# Give it some velocity
	body.velocity = FP.FPVec2.make(FP.from_int(3), FP.from_int(3))

	h.bridge.reset_puck_to(puck, Vector3(1.0, 0.0, 12.0))

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
