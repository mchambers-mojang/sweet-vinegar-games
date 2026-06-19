class_name CaromSimBridge
extends Node

## Coordinator that owns the deterministic SimWorld and drives render adapters.
##
## Responsibilities:
##   • Runs SimWorld at 30 Hz using a fixed-timestep accumulator in _process.
##   • Provides interpolated positions to CaromPuck / CaromProjectile for smooth rendering.
##   • Emits zone and collision events so the match controller and effects layer
##     can react without coupling to Godot physics signals.
##
## Usage:
##   1. Call setup_arena(arena) once to create walls and goal zones.
##   2. Call register_puck(puck, start_pos) for each puck in the match.
##   3. Call register_turret(turret) so projectiles are auto-registered on fire.
##   4. Connect puck_zone_entered / projectile_zone_entered to respond to goals.

# ---------------------------------------------------------------------------
# Zone IDs (must match how the match controller interprets them)
# ---------------------------------------------------------------------------

## Zone entered by the puck when it reaches the north-side goal (z ≈ -0.4).
## The player ("south") scores when this zone is entered.
const ZONE_NORTH_GOAL: int = 1

## Zone entered by the puck when it reaches the south-side goal (z ≈ 24.4).
## The AI ("north") scores when this zone is entered.
const ZONE_SOUTH_GOAL: int = 2

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TICK_DURATION: float = 1.0 / 30.0

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted once per tick when the puck body centre enters a goal zone.
signal puck_zone_entered(body_id: int, zone_id: int)

## Emitted once per tick when a projectile body centre enters a goal zone.
signal projectile_zone_entered(body_id: int, zone_id: int)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _sim: SimWorld = SimWorld.new()
var _accumulator: float = 0.0

## Puck tracking (parallel arrays — one entry per registered puck).
var _puck_body_ids: Array[int]    = []
var _puck_nodes: Array[CaromPuck] = []
var _puck_prev_pos: Array         = []  ## Array[FPVec2 Dictionary]
var _puck_curr_pos: Array         = []
var _puck_prev_rot: Array[int]    = []
var _puck_curr_rot: Array[int]    = []

## Projectile tracking: body_id → CaromProjectile node.
var _projectile_nodes: Dictionary = {}
## Interpolation state for projectiles.
var _proj_prev_pos: Dictionary = {}
var _proj_curr_pos: Dictionary = {}


func _ready() -> void:
	pass


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Call once after the bridge is added to the scene tree, before registering
## pucks or turrets.  Reads goal positions from the live arena node.
func setup_arena(arena: CaromArena) -> void:
	_sim.max_speed = FP.from_int(20)
	_setup_walls()
	_setup_goal_zones(arena)


func _setup_walls() -> void:
	# Six-segment octagonal arena boundary (walls + angled corners).
	# Coordinate mapping: sim.x = 3D.x,  sim.y = 3D.z
	# SimWall.make(a, b) computes left-hand perpendicular of (b-a) as the
	# inward normal, so endpoints are ordered so the interior is on the left.

	var fp := FP  # alias for readability

	# Left wall  (inner face x = -4)  — normal points +x
	_sim.add_wall(SimWall.make(
		fp.FPVec2.make(fp.from_float(-4.0), fp.from_float(21.0)),
		fp.FPVec2.make(fp.from_float(-4.0), fp.from_float(3.0))))

	# Right wall (inner face x = +4)  — normal points -x
	_sim.add_wall(SimWall.make(
		fp.FPVec2.make(fp.from_float(4.0), fp.from_float(3.0)),
		fp.FPVec2.make(fp.from_float(4.0), fp.from_float(21.0))))

	# SouthWest corner (low-z, left side) — normal (+1, +1)/√2
	_sim.add_wall(SimWall.make(
		fp.FPVec2.make(fp.from_float(-4.0), fp.from_float(3.0)),
		fp.FPVec2.make(fp.from_float(-2.0), fp.from_float(1.0))))

	# SouthEast corner (low-z, right side) — normal (-1, +1)/√2
	_sim.add_wall(SimWall.make(
		fp.FPVec2.make(fp.from_float(2.0), fp.from_float(1.0)),
		fp.FPVec2.make(fp.from_float(4.0), fp.from_float(3.0))))

	# NorthWest corner (high-z, left side) — normal (+1, -1)/√2
	_sim.add_wall(SimWall.make(
		fp.FPVec2.make(fp.from_float(-2.0), fp.from_float(23.0)),
		fp.FPVec2.make(fp.from_float(-4.0), fp.from_float(21.0))))

	# NorthEast corner (high-z, right side) — normal (-1, -1)/√2
	_sim.add_wall(SimWall.make(
		fp.FPVec2.make(fp.from_float(4.0), fp.from_float(21.0)),
		fp.FPVec2.make(fp.from_float(2.0), fp.from_float(23.0))))


func _setup_goal_zones(arena: CaromArena) -> void:
	# Goal zones span 3 units each side of centre horizontally.
	# Vertically they extend 2 units past the goal line so the puck centre
	# must clearly cross the line before the zone fires.
	var half_w: int = FP.from_float(3.0)

	var ng_z: int = FP.from_float(arena.north_goal.global_position.z)
	_sim.add_zone(SimZone.make(
		FP.FPVec2.make(-half_w, ng_z - FP.from_float(2.0)),
		FP.FPVec2.make( half_w, ng_z + FP.from_float(0.5)),
		ZONE_NORTH_GOAL))

	var sg_z: int = FP.from_float(arena.south_goal.global_position.z)
	_sim.add_zone(SimZone.make(
		FP.FPVec2.make(-half_w, sg_z - FP.from_float(0.5)),
		FP.FPVec2.make( half_w, sg_z + FP.from_float(2.0)),
		ZONE_SOUTH_GOAL))


# ---------------------------------------------------------------------------
# Puck registration
# ---------------------------------------------------------------------------

## Register a puck render adapter with the sim.  Call once per puck after
## the puck node has been added to the scene tree and positioned.
func register_puck(puck: CaromPuck, start_pos: Vector3) -> void:
	var body := SimBody.new()
	body.shape = SimBody.Shape.POLYGON

	# Equilateral-triangle vertices matching carom_puck.tscn (circumradius 0.5)
	# in local space (sim.x = 3D.x, sim.y = 3D.z).
	body.vertices = [
		FP.FPVec2.make(FP.from_float(0.0),    FP.from_float(0.5)),
		FP.FPVec2.make(FP.from_float(0.433),  FP.from_float(-0.25)),
		FP.FPVec2.make(FP.from_float(-0.433), FP.from_float(-0.25)),
	]
	body.position   = FP.FPVec2.make(FP.from_float(start_pos.x), FP.from_float(start_pos.z))
	body.velocity   = FP.FPVec2.make(0, 0)
	body.mass       = FP.from_int(3)
	body.restitution = FP.from_float(0.75)
	# Jolt linear_damp=0.35 → per-tick factor ≈ 0.35/30
	body.damping    = FP.from_float(0.35 / 30.0)

	_sim.add_body(body)

	_puck_body_ids.append(body.id)
	_puck_nodes.append(puck)
	_puck_prev_pos.append(body.position)
	_puck_curr_pos.append(body.position)
	_puck_prev_rot.append(0)
	_puck_curr_rot.append(0)

	puck.setup_sim_bridge(self)


# ---------------------------------------------------------------------------
# Turret / projectile registration
# ---------------------------------------------------------------------------

## Connect a turret so every projectile it fires is automatically registered
## with the sim.  Call once per turret after setup_arena().
func register_turret(turret: CaromTurret) -> void:
	if turret == null:
		return
	if not turret.projectile_fired.is_connected(_on_turret_projectile_fired):
		turret.projectile_fired.connect(_on_turret_projectile_fired)


func _on_turret_projectile_fired(projectile: CaromProjectile) -> void:
	var body := SimBody.new()
	body.shape       = SimBody.Shape.CIRCLE
	body.radius      = FP.from_float(0.14)
	body.position    = FP.FPVec2.make(
		FP.from_float(projectile.global_position.x),
		FP.from_float(projectile.global_position.z))
	body.velocity    = FP.FPVec2.make(
		FP.from_float(projectile.direction.x * projectile.speed),
		FP.from_float(projectile.direction.z * projectile.speed))
	body.mass        = FP.from_float(0.3)
	body.restitution = FP.ONE  # perfectly elastic
	body.damping     = 0

	_sim.add_body(body)

	_projectile_nodes[body.id] = projectile
	_proj_prev_pos[body.id]    = body.position
	_proj_curr_pos[body.id]    = body.position

	projectile.setup_sim_bridge(self, body.id)
	projectile.tree_exiting.connect(_on_projectile_removed.bind(body.id))


func _on_projectile_removed(body_id: int) -> void:
	_sim.remove_body(body_id)
	_projectile_nodes.erase(body_id)
	_proj_prev_pos.erase(body_id)
	_proj_curr_pos.erase(body_id)


## Return the CaromProjectile node for a given sim body id, or null.
func get_projectile_node(body_id: int) -> CaromProjectile:
	return _projectile_nodes.get(body_id, null) as CaromProjectile


## Return the CaromPuck node for a given sim body id, or null.
func get_puck_node(body_id: int) -> CaromPuck:
	for i in _puck_body_ids.size():
		if _puck_body_ids[i] == body_id:
			return _puck_nodes[i]
	return null


# ---------------------------------------------------------------------------
# Puck state accessors (called by CaromPuck._process)
# ---------------------------------------------------------------------------

## Fraction [0, 1] to use when interpolating between the previous and current
## sim tick for smooth rendering at display refresh rate.
func get_render_alpha() -> float:
	return clampf(_accumulator / TICK_DURATION, 0.0, 1.0)


## Interpolated 3D position for a puck render adapter.
## Returns Vector3.ZERO if the puck is not registered.
func get_puck_position(puck: CaromPuck, alpha: float) -> Vector3:
	var idx := _puck_nodes.find(puck)
	if idx < 0:
		return Vector3.ZERO
	var px: float = lerpf(FP.to_float(_puck_prev_pos[idx].x), FP.to_float(_puck_curr_pos[idx].x), alpha)
	var pz: float = lerpf(FP.to_float(_puck_prev_pos[idx].y), FP.to_float(_puck_curr_pos[idx].y), alpha)
	return Vector3(px, 0.0, pz)


## Interpolated Y-rotation (radians) for a puck render adapter.
func get_puck_rotation(puck: CaromPuck, alpha: float) -> float:
	var idx := _puck_nodes.find(puck)
	if idx < 0:
		return 0.0
	return lerpf(FP.to_float(_puck_prev_rot[idx]), FP.to_float(_puck_curr_rot[idx]), alpha)


## Interpolated 3D position for a projectile render adapter.
func get_projectile_position(body_id: int, alpha: float) -> Vector3:
	if not _proj_prev_pos.has(body_id):
		return Vector3.ZERO
	var prev: Dictionary = _proj_prev_pos[body_id]
	var curr: Dictionary = _proj_curr_pos[body_id]
	var px: float = lerpf(FP.to_float(prev.x), FP.to_float(curr.x), alpha)
	var pz: float = lerpf(FP.to_float(prev.y), FP.to_float(curr.y), alpha)
	return Vector3(px, 0.0, pz)


# ---------------------------------------------------------------------------
# Puck reset (called by CaromPuck.reset_to_center)
# ---------------------------------------------------------------------------

## Teleport the puck's sim body to pos and zero its velocity.
## Also snaps interpolation state so there is no visual jump on the next frame.
func reset_puck_to(puck: CaromPuck, pos: Vector3) -> void:
	var idx := _puck_nodes.find(puck)
	if idx < 0:
		return
	var body := _sim.get_body(_puck_body_ids[idx])
	if body == null:
		return
	body.position        = FP.FPVec2.make(FP.from_float(pos.x), FP.from_float(pos.z))
	body.velocity        = FP.FPVec2.make(0, 0)
	body.angular_velocity = 0
	body.rotation        = 0
	_puck_prev_pos[idx]  = body.position
	_puck_curr_pos[idx]  = body.position
	_puck_prev_rot[idx]  = 0
	_puck_curr_rot[idx]  = 0


# ---------------------------------------------------------------------------
# Fixed-timestep loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= TICK_DURATION:
		_accumulator -= TICK_DURATION
		_tick()


func _tick() -> void:
	# Apply stall nudge to each registered puck before advancing the sim.
	for i in _puck_nodes.size():
		_apply_puck_stall_nudge(i)

	# Snapshot previous positions for interpolation.
	for i in _puck_nodes.size():
		var body := _sim.get_body(_puck_body_ids[i])
		if body != null:
			_puck_prev_pos[i] = body.position
			_puck_prev_rot[i] = body.rotation

	for body_id: int in _proj_curr_pos:
		_proj_prev_pos[body_id] = _proj_curr_pos[body_id]

	# Advance the deterministic simulation one tick.
	_sim.advance()

	# Update current positions after the tick.
	for i in _puck_nodes.size():
		var body := _sim.get_body(_puck_body_ids[i])
		if body != null:
			_puck_curr_pos[i] = body.position
			_puck_curr_rot[i] = body.rotation

	for body_id: int in _projectile_nodes:
		var body := _sim.get_body(body_id)
		if body != null:
			_proj_curr_pos[body_id] = body.position

	# Dispatch zone events.
	for ev: Dictionary in _sim.zone_events:
		var body_id: int = ev.body_id
		var zone_id: int = ev.zone_id
		if _is_puck_body(body_id):
			puck_zone_entered.emit(body_id, zone_id)
		elif _projectile_nodes.has(body_id):
			projectile_zone_entered.emit(body_id, zone_id)

	# Dispatch collision events to projectile render adapters.
	for ev: Dictionary in _sim.collision_events:
		var body_id: int = ev.body_id
		if not _projectile_nodes.has(body_id):
			continue
		var projectile := _projectile_nodes[body_id] as CaromProjectile
		if not is_instance_valid(projectile):
			continue
		var hit_puck: bool = _is_puck_body(ev.other_id)
		var pos := Vector3(FP.to_float(ev.pos_x), 0.0, FP.to_float(ev.pos_y))
		projectile.impact_occurred.emit(pos, hit_puck)


# ---------------------------------------------------------------------------
# Stall nudge (mirrors CaromPuck._apply_goal_nudge in sim space)
# ---------------------------------------------------------------------------

func _apply_puck_stall_nudge(idx: int) -> void:
	var puck := _puck_nodes[idx] as CaromPuck
	if puck.stall_nudge_force <= 0.0:
		return

	var body := _sim.get_body(_puck_body_ids[idx])
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

	var best_dist_sq: int = 0x7FFFFFFFFFFFFFFF
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

	var nudge: int = FP.from_float(puck.stall_nudge_force)
	body.velocity = FP.FPVec2.add(body.velocity, FP.FPVec2.scale(best_dir, nudge))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _is_puck_body(body_id: int) -> bool:
	return _puck_body_ids.has(body_id)
