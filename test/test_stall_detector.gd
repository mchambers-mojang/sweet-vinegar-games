extends GutTest

## Tests for StallDetector — verifies nudge logic in isolation from CaromSimBridge.
## Uses pure-code sim setup (no full scene required) to stay fast and headless-friendly.

const StallDetectorScript := preload("res://carom/scripts/stall_detector.gd")
const SimWorldScript       := preload("res://carom/scripts/sim/sim_world.gd")
const SimBodyScript        := preload("res://carom/scripts/sim/sim_body.gd")
const PuckScene            := preload("res://carom/scenes/carom_puck.tscn")
const ArenaScene           := preload("res://carom/scenes/carom_arena.tscn")

const TICK: float = 1.0 / 30.0


# ---------------------------------------------------------------------------
# Helper — build a minimal sim world with one body at the given position
# ---------------------------------------------------------------------------

func _make_sim_with_body(pos_x: float, pos_z: float) -> Dictionary:
	var sim := SimWorldScript.new()
	var body := SimBodyScript.new()
	body.shape    = SimBodyScript.Shape.CIRCLE
	body.radius   = FP.from_float(0.5)
	body.position = FP.FPVec2.make(FP.from_float(pos_x), FP.from_float(pos_z))
	body.velocity = FP.FPVec2.make(0, 0)
	body.mass     = FP.from_int(3)
	body.damping  = 0
	sim.add_body(body)
	return {sim = sim, body = body}


# ---------------------------------------------------------------------------
# 1. No nudge when stall_nudge_force == 0
# ---------------------------------------------------------------------------

func test_no_nudge_when_force_is_zero() -> void:
	var result := _make_sim_with_body(0.0, 12.0)
	var sim: SimWorld = result.sim
	var body = result.body

	var arena := ArenaScene.instantiate() as CaromArena
	add_child_autofree(arena)

	var puck := PuckScene.instantiate() as CaromPuck
	arena.get_node("Actors").add_child(puck)
	await get_tree().process_frame

	puck.stall_nudge_force = 0.0
	puck.stall_speed_threshold = 99.0
	var start_pos := Vector3(0.0, 0.0, 12.0)
	puck.configure(arena.get_goal_targets(), start_pos)

	var detector := StallDetectorScript.new()
	detector.apply_to_all(sim, [body.id] as Array[int], [puck], TICK)

	assert_almost_eq(FP.to_float(body.velocity.x), 0.0, 0.0001,
		"velocity.x must stay zero when force is zero")
	assert_almost_eq(FP.to_float(body.velocity.y), 0.0, 0.0001,
		"velocity.y must stay zero when force is zero")


# ---------------------------------------------------------------------------
# 2. No nudge when body is already moving fast enough
# ---------------------------------------------------------------------------

func test_no_nudge_above_threshold() -> void:
	var result := _make_sim_with_body(0.0, 12.0)
	var sim: SimWorld = result.sim
	var body = result.body

	# Give the body a speed well above the threshold.
	body.velocity = FP.FPVec2.make(FP.from_float(5.0), 0)

	var arena := ArenaScene.instantiate() as CaromArena
	add_child_autofree(arena)

	var puck := PuckScene.instantiate() as CaromPuck
	arena.get_node("Actors").add_child(puck)
	await get_tree().process_frame

	puck.stall_nudge_force     = 0.18
	puck.stall_speed_threshold = 1.8
	puck.configure(arena.get_goal_targets(), Vector3(0, 0, 12))

	var before_vx: float = FP.to_float(body.velocity.x)
	var before_vy: float = FP.to_float(body.velocity.y)

	var detector := StallDetectorScript.new()
	detector.apply_to_all(sim, [body.id] as Array[int], [puck], TICK)

	assert_almost_eq(FP.to_float(body.velocity.x), before_vx, 0.0001,
		"velocity.x must not change when speed exceeds threshold")
	assert_almost_eq(FP.to_float(body.velocity.y), before_vy, 0.0001,
		"velocity.y must not change when speed exceeds threshold")


# ---------------------------------------------------------------------------
# 3. Nudge is applied when body is stalled and has a goal target
# ---------------------------------------------------------------------------

func test_nudge_applied_when_stalled() -> void:
	var result := _make_sim_with_body(0.0, 12.0)
	var sim: SimWorld = result.sim
	var body = result.body

	# Zero velocity — clearly stalled.
	body.velocity = FP.FPVec2.make(0, 0)

	var arena := ArenaScene.instantiate() as CaromArena
	add_child_autofree(arena)

	var puck := PuckScene.instantiate() as CaromPuck
	arena.get_node("Actors").add_child(puck)
	await get_tree().process_frame

	var start_pos := Vector3(0.0, 0.0, 12.0)
	puck.stall_nudge_force     = 0.18
	puck.stall_speed_threshold = 1.8
	puck.configure(arena.get_goal_targets(), start_pos)

	var detector := StallDetectorScript.new()
	detector.apply_to_all(sim, [body.id] as Array[int], [puck], TICK)

	var vx: float = FP.to_float(body.velocity.x)
	var vy: float = FP.to_float(body.velocity.y)
	var speed_sq: float = vx * vx + vy * vy
	assert_gt(speed_sq, 0.0, "Stalled puck should receive a non-zero nudge velocity")


# ---------------------------------------------------------------------------
# 4. Empty puck array is a no-op (no crash)
# ---------------------------------------------------------------------------

func test_apply_to_all_empty_is_safe() -> void:
	var result := _make_sim_with_body(0.0, 12.0)
	var sim: SimWorld = result.sim

	var detector := StallDetectorScript.new()
	detector.apply_to_all(sim, [] as Array[int], [], TICK)
	pass  # Just verifying no crash
