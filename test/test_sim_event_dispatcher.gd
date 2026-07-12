extends GutTest

## Tests for SimEventDispatcher — verifies that zone and collision events are
## routed to the correct signals/callbacks without needing a full bridge or scene.

const DispatcherScript := preload("res://carom/scripts/sim_event_dispatcher.gd")
const SimWorldScript   := preload("res://carom/scripts/sim/sim_world.gd")
const SimBodyScript    := preload("res://carom/scripts/sim/sim_body.gd")
const SimWallScript    := preload("res://carom/scripts/sim/sim_wall.gd")
const SimZoneScript    := preload("res://carom/scripts/sim/sim_zone.gd")
const ArenaScene       := preload("res://carom/scenes/carom_arena.tscn")
const PuckScene        := preload("res://carom/scenes/carom_puck.tscn")


# ---------------------------------------------------------------------------
# Helper — build a minimal SimWorld with one puck body inside a goal zone
# ---------------------------------------------------------------------------

func _make_sim_with_zone(body_pos_x: float, body_pos_z: float) -> Dictionary:
	var sim := SimWorldScript.new()
	var body := SimBodyScript.new()
	body.shape    = SimBodyScript.Shape.CIRCLE
	body.radius   = FP.from_float(0.5)
	body.position = FP.FPVec2.make(FP.from_float(body_pos_x), FP.from_float(body_pos_z))
	body.velocity = FP.FPVec2.make(0, 0)
	body.mass     = FP.from_int(3)
	body.damping  = 0
	sim.add_body(body)
	return {sim = sim, body = body}


# ---------------------------------------------------------------------------
# 1. puck_zone_entered fires when a puck body is in zone_events
# ---------------------------------------------------------------------------

func test_puck_zone_entered_emitted_for_puck_body() -> void:
	var dispatcher := DispatcherScript.new()

	var puck_body_ids: Array[int] = [42]
	var projectile_nodes: Dictionary = {}

	# Synthesise a zone event list (same structure SimWorld produces).
	var zone_events: Array = [{body_id = 42, zone_id = 1}]

	watch_signals(dispatcher)
	dispatcher.dispatch_zone_events(zone_events, puck_body_ids, projectile_nodes)

	assert_signal_emitted(dispatcher, "puck_zone_entered",
		"puck_zone_entered should fire for a puck body")
	var params: Array = get_signal_parameters(dispatcher, "puck_zone_entered")
	assert_eq(params[0], 42, "body_id should match")
	assert_eq(params[1], 1,  "zone_id should match")


# ---------------------------------------------------------------------------
# 2. projectile_zone_entered fires when a projectile body is in zone_events
# ---------------------------------------------------------------------------

func test_projectile_zone_entered_emitted_for_projectile_body() -> void:
	var dispatcher := DispatcherScript.new()

	var puck_body_ids: Array[int] = [1]
	# Use a dummy value so the dictionary has the key, without needing a real node.
	var projectile_nodes: Dictionary = {99: null}

	var zone_events: Array = [{body_id = 99, zone_id = 2}]

	watch_signals(dispatcher)
	dispatcher.dispatch_zone_events(zone_events, puck_body_ids, projectile_nodes)

	assert_signal_emitted(dispatcher, "projectile_zone_entered",
		"projectile_zone_entered should fire for a projectile body")
	var params: Array = get_signal_parameters(dispatcher, "projectile_zone_entered")
	assert_eq(params[0], 99, "body_id should match")
	assert_eq(params[1], 2,  "zone_id should match")


# ---------------------------------------------------------------------------
# 3. Neither signal fires for an unknown body_id
# ---------------------------------------------------------------------------

func test_no_signal_for_unknown_body() -> void:
	var dispatcher := DispatcherScript.new()

	var puck_body_ids: Array[int] = [1]
	var projectile_nodes: Dictionary = {}  # 99 not registered

	var zone_events: Array = [{body_id = 99, zone_id = 1}]

	watch_signals(dispatcher)
	dispatcher.dispatch_zone_events(zone_events, puck_body_ids, projectile_nodes)

	assert_signal_not_emitted(dispatcher, "puck_zone_entered",
		"puck_zone_entered must not fire for an unregistered body")
	assert_signal_not_emitted(dispatcher, "projectile_zone_entered",
		"projectile_zone_entered must not fire for an unregistered body")


# ---------------------------------------------------------------------------
# 4. Empty zone_events is a no-op
# ---------------------------------------------------------------------------

func test_dispatch_empty_zone_events_is_safe() -> void:
	var dispatcher := DispatcherScript.new()
	watch_signals(dispatcher)
	dispatcher.dispatch_zone_events([], [] as Array[int], {})
	assert_signal_not_emitted(dispatcher, "puck_zone_entered")
	assert_signal_not_emitted(dispatcher, "projectile_zone_entered")


# ---------------------------------------------------------------------------
# 5. Collision events for unknown body are silently skipped
# ---------------------------------------------------------------------------

func test_dispatch_collision_events_skips_unknown_body() -> void:
	var dispatcher := DispatcherScript.new()
	var puck_body_ids: Array[int] = [1]
	var projectile_nodes: Dictionary = {}

	# Should not crash even if body_id is not in projectile_nodes.
	var collision_events: Array = [{body_id = 77, other_id = 1, pos_x = 0, pos_y = 0}]
	dispatcher.dispatch_collision_events(collision_events, puck_body_ids, projectile_nodes)
	pass  # Verifying no crash
