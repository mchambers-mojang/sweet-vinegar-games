class_name StallDetector
extends RefCounted

## Gameplay policy: detects stalled pucks and nudges them toward the nearest goal.
##
## Runs once per sim tick, before SimWorld.advance(), so the nudge is included
## in the deterministic tick result.  Extracted from CaromSimBridge so that stall
## logic can be tested and reasoned about independently of the sync layer.

## Sentinel — "no best distance found yet" in nearest-goal search.
const _DIST_SQ_INIT: int = 0x7FFFFFFFFFFFFFFF  # max int64


## Apply a stall nudge to every registered puck whose speed falls below its
## stall_speed_threshold.  Mutates the corresponding SimBody velocity in place.
## Call this before SimWorld.advance() each tick.
func apply_to_all(
		sim: SimWorld,
		puck_body_ids: Array[int],
		puck_nodes: Array,
		tick_duration: float) -> void:
	for i in puck_nodes.size():
		_apply_nudge(sim, puck_body_ids[i], puck_nodes[i] as CaromPuck, tick_duration)


func _apply_nudge(sim: SimWorld, body_id: int, puck: CaromPuck, tick_duration: float) -> void:
	if puck.stall_nudge_force <= 0.0:
		return

	var body := sim.get_body(body_id)
	if body == null:
		return

	var speed: int = FP.FPVec2.length(body.velocity)
	var threshold: int = FP.from_float(puck.stall_speed_threshold)
	if speed > threshold:
		return

	# Find nearest goal target (uses CaromPuck's configured goal positions).
	var goal_targets: Array[Vector3] = puck._goal_targets
	if goal_targets.is_empty():
		return

	var best_dist_sq: int = _DIST_SQ_INIT
	var best_dir: Dictionary = FP.FPVec2.make(FP.ONE, 0)

	for goal_pos: Vector3 in goal_targets:
		var gx: int = FP.from_float(goal_pos.x)
		var gy: int = FP.from_float(goal_pos.z)
		var dx: int = gx - body.position.x
		var dy: int = gy - body.position.y
		var d2: int = FP.mul(dx, dx) + FP.mul(dy, dy)
		if d2 < best_dist_sq:
			best_dist_sq = d2
			var raw: Dictionary = FP.FPVec2.make(dx, dy)
			var len: int = FP.FPVec2.length(raw)
			if len > 0:
				best_dir = FP.FPVec2.normalize(raw)

	# Scale force → velocity change: Δv = F * dt / m  (mirrors apply_central_force semantics)
	var nudge: int = FP.from_float(puck.stall_nudge_force * tick_duration / FP.to_float(body.mass))
	body.velocity = FP.FPVec2.add(body.velocity, FP.FPVec2.scale(best_dir, nudge))
