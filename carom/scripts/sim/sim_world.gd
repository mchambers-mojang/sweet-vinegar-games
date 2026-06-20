class_name SimWorld
extends RefCounted

## Deterministic physics world — fixed timestep 1/30 s.
## All arithmetic uses the FP (48.16 fixed-point) library.
## No floats, no Godot nodes, no scene-tree dependencies.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Fixed-point representation of 1/30 (one tick duration).
## FP.from_float(1.0/30.0) = round(65536/30) = 2185
const DT: int = 2185

## Maximum speed a body may reach (FP). Clamp applied after integration.
## Default: 30 units/tick  → 900 units/second at 30 Hz
const DEFAULT_MAX_SPEED: int = 30 * FP.ONE

## Max int64 sentinel used to initialise a "smallest depth found so far" accumulator.
const _MAX_INT: int = 0x7FFFFFFFFFFFFFFF

## Fixed-point π constants (48.16 format).
const FP_PI: int      = 205887   # ≈ π   * 65536
const FP_TWO_PI: int  = 411774   # ≈ 2π  * 65536
const FP_HALF_PI: int = 102944   # ≈ π/2 * 65536

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _bodies: Dictionary = {}   ## id -> SimBody
var _walls: Array  = []        ## Array[SimWall]
var _zones: Array  = []        ## Array[SimZone]
var _next_id: int  = 1

## Maximum speed cap applied each tick (can be overridden before a sim starts).
var max_speed: int = DEFAULT_MAX_SPEED

## Bodies that entered a zone during the last advance() call.
## Each entry is {body_id: int, zone_id: int}.
var zone_events: Array = []

## Collision events recorded during the last advance() call.
## Each entry is {body_id: int, other_id: int, pos_x: int, pos_y: int}.
## other_id = -1 for wall collisions. Populated in _resolve_circle_circle and _resolve_circle_wall.
var collision_events: Array = []

# ---------------------------------------------------------------------------
# Body management
# ---------------------------------------------------------------------------

func add_body(body: SimBody) -> void:
	if body.id == 0:
		body.id = _next_id
		_next_id += 1
	_bodies[body.id] = body

func remove_body(id: int) -> void:
	_bodies.erase(id)

func get_body(id: int) -> SimBody:
	return _bodies.get(id, null)

func add_wall(wall: SimWall) -> void:
	_walls.append(wall)

func add_zone(zone: SimZone) -> void:
	_zones.append(zone)

# ---------------------------------------------------------------------------
# Tick
# ---------------------------------------------------------------------------

## Advance the simulation by one fixed tick.
## `inputs` is reserved for future player-input integration and is unused here.
func advance(_inputs: Dictionary = {}) -> void:
	zone_events = []
	collision_events = []
	_integrate()
	_detect_and_resolve()
	_clamp_speed()
	_check_zones()

# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

## Returns a snapshot of body state, _next_id, and max_speed.
## Walls and zones are NOT included — they are static geometry that the
## caller is expected to re-add after calling set_body_state().
## Use this pair for rollback snapshots where geometry never changes.
func get_body_state() -> Dictionary:
	var bodies_state: Dictionary = {}
	for id: int in _bodies:
		bodies_state[str(id)] = (_bodies[id] as SimBody).get_state()
	return {
		bodies   = bodies_state,
		next_id  = _next_id,
		max_speed = max_speed,
	}

## Restores body state from a snapshot produced by get_body_state().
## Walls and zones are cleared and must be re-added by the caller.
func set_body_state(state: Dictionary) -> void:
	_bodies = {}
	_walls  = []
	_zones  = []
	var bodies_dict: Dictionary = state.bodies
	for key: String in bodies_dict:
		var b: SimBody = SimBody.new()
		b.set_state(bodies_dict[key])
		_bodies[b.id] = b
	_next_id  = state.next_id
	max_speed = state.max_speed

# ---------------------------------------------------------------------------
# 1. Integration
# ---------------------------------------------------------------------------

func _integrate() -> void:
	for id: int in _bodies:
		var b: SimBody = _bodies[id]
		# position += velocity * dt
		var dpos: Dictionary = FP.FPVec2.scale(b.velocity, DT)
		b.position = FP.FPVec2.add(b.position, dpos)
		# Damping: velocity *= (ONE - damping)
		if b.damping != 0:
			var keep: int = FP.ONE - b.damping
			b.velocity = FP.FPVec2.scale(b.velocity, keep)
		# Polygon rotation
		if b.shape == SimBody.Shape.POLYGON and b.angular_velocity != 0:
			b.rotation = (b.rotation + b.angular_velocity) % FP_TWO_PI

# ---------------------------------------------------------------------------
# 2 & 3. Collision detection + impulse resolution
# ---------------------------------------------------------------------------

func _detect_and_resolve() -> void:
	var ids: Array = _bodies.keys()
	# Body–body
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a: SimBody = _bodies[ids[i]]
			var b: SimBody = _bodies[ids[j]]
			if a.shape == SimBody.Shape.CIRCLE and b.shape == SimBody.Shape.CIRCLE:
				_resolve_circle_circle(a, b)
			elif a.shape == SimBody.Shape.CIRCLE and b.shape == SimBody.Shape.POLYGON:
				_resolve_polygon_circle(b, a)
			elif a.shape == SimBody.Shape.POLYGON and b.shape == SimBody.Shape.CIRCLE:
				_resolve_polygon_circle(a, b)
	# Body–wall
	for id: int in _bodies:
		var body: SimBody = _bodies[id]
		for wall: SimWall in _walls:
			if body.shape == SimBody.Shape.CIRCLE:
				_resolve_circle_wall(body, wall)
			else:
				_resolve_polygon_wall(body, wall)

# --- Circle–Circle ---

func _resolve_circle_circle(a: SimBody, b: SimBody) -> void:
	var diff: Dictionary = FP.FPVec2.sub(b.position, a.position)
	var dist_sq: int     = FP.FPVec2.length_squared(diff)
	var radii_sum: int   = a.radius + b.radius
	var touch_sq: int    = FP.mul(radii_sum, radii_sum)

	if dist_sq >= touch_sq:
		return  # no collision

	var dist: int = FP.FPVec2.length(diff)
	if dist == 0:
		# Degenerate: push apart along x-axis
		diff = FP.FPVec2.make(radii_sum, 0)
		dist = radii_sum

	# Unit normal from a → b
	var n: Dictionary = FP.FPVec2.normalize(diff)

	# Positional correction (push apart so they just touch)
	var penetration: int = radii_sum - dist
	# Split penetration equally between both bodies.
	# Integer >> 1 may lose the LSB for odd values; the sub-unit rounding is
	# negligible for game physics and preserves determinism.
	var half_pen: int    = penetration >> 1
	a.position = FP.FPVec2.sub(a.position, FP.FPVec2.scale(n, half_pen))
	b.position = FP.FPVec2.add(b.position, FP.FPVec2.scale(n, half_pen))

	# Relative velocity along normal
	var rel_v: Dictionary = FP.FPVec2.sub(b.velocity, a.velocity)
	var vn: int           = FP.FPVec2.dot(rel_v, n)

	if vn > 0:
		return  # already separating

	# Combined restitution (min of the two)
	var e: int = _min_int(a.restitution, b.restitution)

	# Impulse scalar: j = -(1+e)*vn / (1/ma + 1/mb)
	var num: int   = FP.mul(-(FP.ONE + e), vn)
	var inv_ma: int = FP.div(FP.ONE, a.mass)
	var inv_mb: int = FP.div(FP.ONE, b.mass)
	var denom: int  = inv_ma + inv_mb
	var j: int      = FP.div(num, denom)

	var impulse: Dictionary = FP.FPVec2.scale(n, j)
	a.velocity = FP.FPVec2.sub(a.velocity, FP.FPVec2.scale(impulse, FP.div(FP.ONE, a.mass)))
	b.velocity = FP.FPVec2.add(b.velocity, FP.FPVec2.scale(impulse, FP.div(FP.ONE, b.mass)))

	# Record collision event for render adapters (e.g. projectile impact effects)
	var contact_x: int = (a.position.x + b.position.x) >> 1
	var contact_y: int = (a.position.y + b.position.y) >> 1
	collision_events.append({body_id = a.id, other_id = b.id, pos_x = contact_x, pos_y = contact_y})
	collision_events.append({body_id = b.id, other_id = a.id, pos_x = contact_x, pos_y = contact_y})

# --- Circle–Wall ---

func _resolve_circle_wall(body: SimBody, wall: SimWall) -> void:
	# Signed distance from body centre to the wall line
	var to_a: Dictionary = FP.FPVec2.sub(body.position, wall.a)
	var signed_dist: int = FP.FPVec2.dot(to_a, wall.normal)

	if signed_dist >= body.radius:
		return  # not penetrating

	# Project onto segment parameter t ∈ [0,1] to check the segment (not just infinite line)
	var ab: Dictionary  = FP.FPVec2.sub(wall.b, wall.a)
	var ab_len_sq: int  = FP.FPVec2.length_squared(ab)
	if ab_len_sq == 0:
		return  # degenerate wall

	var t_num: int = FP.FPVec2.dot(to_a, ab)
	# t = dot(to_a, ab) / |ab|² in FP — compare before clamping to detect endpoint
	var t: int = FP.div(t_num, ab_len_sq)
	var at_endpoint: bool = t < 0 or t > FP.ONE
	var t_clamped: int = _clamp_fp(t, 0, FP.ONE)

	# Closest point on segment
	var closest: Dictionary = FP.FPVec2.add(wall.a, FP.FPVec2.scale(ab, t_clamped))
	var to_centre: Dictionary = FP.FPVec2.sub(body.position, closest)
	var dist: int = FP.FPVec2.length(to_centre)

	if dist >= body.radius:
		return  # outside radius

	# Choose push direction and penetration depth.
	# At a segment endpoint: push radially away from that endpoint so corner
	# reflections are physically correct (wall.normal is only valid on the face).
	# On the wall face: use wall.normal with the signed depth so that a centre
	# that has already crossed through (signed_dist < 0) is pushed back to
	# radius distance rather than only to the wall surface.
	var push_normal: Dictionary
	var penetration: int
	if at_endpoint and dist > 0:
		push_normal = FP.FPVec2.normalize(to_centre)
		penetration = body.radius - dist
	else:
		push_normal = wall.normal
		penetration = body.radius - signed_dist

	body.position = FP.FPVec2.add(body.position,
		FP.FPVec2.scale(push_normal, penetration))

	# Reflect velocity component along the push normal
	var vn: int = FP.FPVec2.dot(body.velocity, push_normal)
	if vn >= 0:
		return  # moving away from wall

	# v_reflected = v - (1+e)*vn*n
	var e: int = body.restitution
	var delta_vn: int = FP.mul(FP.ONE + e, vn)
	var correction: Dictionary = FP.FPVec2.scale(push_normal, delta_vn)
	body.velocity = FP.FPVec2.sub(body.velocity, correction)

	# Record collision event for render adapters
	collision_events.append({body_id = body.id, other_id = -1, pos_x = body.position.x, pos_y = body.position.y})

# --- Polygon–Circle (SAT nearest-edge approach) ---

func _resolve_polygon_circle(poly: SimBody, circle: SimBody) -> void:
	var verts: Array = _world_vertices(poly)
	if verts.is_empty():
		return

	var min_depth: int = _MAX_INT
	var best_normal: Dictionary = FP.FPVec2.make(0, 0)
	var colliding: bool = false

	var n: int = verts.size()
	for i in range(n):
		var va: Dictionary = verts[i]
		var vb: Dictionary = verts[(i + 1) % n]

		# Edge normal (left-hand perpendicular, normalised)
		var edge: Dictionary   = FP.FPVec2.sub(vb, va)
		var edge_normal: Dictionary = FP.FPVec2.normalize(FP.FPVec2.make(-edge.y, edge.x))

		# Project circle centre onto axis
		var to_circle: Dictionary = FP.FPVec2.sub(circle.position, va)
		var dist_on_axis: int     = FP.FPVec2.dot(to_circle, edge_normal)

		if dist_on_axis >= circle.radius:
			return  # Separating axis found — no collision

		var depth: int = circle.radius - dist_on_axis
		if depth < min_depth:
			min_depth   = depth
			best_normal = edge_normal
			colliding   = true

	if not colliding:
		return

	# Positional correction — mass-weighted split (heavier body moves less)
	var inv_poly: int   = FP.div(FP.ONE, poly.mass)
	var inv_circle: int = FP.div(FP.ONE, circle.mass)
	var total_inv: int  = inv_poly + inv_circle
	poly.position = FP.FPVec2.sub(poly.position,
		FP.FPVec2.scale(best_normal, FP.mul(min_depth, FP.div(inv_poly, total_inv))))
	circle.position = FP.FPVec2.add(circle.position,
		FP.FPVec2.scale(best_normal, FP.mul(min_depth, FP.div(inv_circle, total_inv))))

	# Two-body impulse — transfers momentum from circle (projectile) to poly (puck)
	var rel_v: Dictionary = FP.FPVec2.sub(circle.velocity, poly.velocity)
	var vn: int = FP.FPVec2.dot(rel_v, best_normal)
	if vn >= 0:
		return  # already separating

	var e: int = _min_int(poly.restitution, circle.restitution)
	var j: int = FP.div(FP.mul(-(FP.ONE + e), vn), total_inv)

	var impulse: Dictionary = FP.FPVec2.scale(best_normal, j)
	poly.velocity   = FP.FPVec2.sub(poly.velocity,   FP.FPVec2.scale(impulse, inv_poly))
	circle.velocity = FP.FPVec2.add(circle.velocity, FP.FPVec2.scale(impulse, inv_circle))

	# Record collision event for render adapters (e.g. projectile impact VFX)
	var contact_x: int = (poly.position.x + circle.position.x) >> 1
	var contact_y: int = (poly.position.y + circle.position.y) >> 1
	collision_events.append({body_id = circle.id, other_id = poly.id, pos_x = contact_x, pos_y = contact_y})

# --- Polygon–Wall (vertex penetration checks) ---

func _resolve_polygon_wall(body: SimBody, wall: SimWall) -> void:
	var verts: Array = _world_vertices(body)
	for v: Dictionary in verts:
		var to_a: Dictionary = FP.FPVec2.sub(v, wall.a)
		var signed_dist: int = FP.FPVec2.dot(to_a, wall.normal)
		if signed_dist < 0:
			# Vertex is on the wrong side — push body out
			body.position = FP.FPVec2.add(body.position,
				FP.FPVec2.scale(wall.normal, -signed_dist))
			# Reflect velocity
			var vn: int = FP.FPVec2.dot(body.velocity, wall.normal)
			if vn < 0:
				var e: int = body.restitution
				var delta_vn: int = FP.mul(FP.ONE + e, vn)
				var corr: Dictionary = FP.FPVec2.scale(wall.normal, delta_vn)
				body.velocity = FP.FPVec2.sub(body.velocity, corr)
			break  # one correction per wall per tick keeps it stable

# ---------------------------------------------------------------------------
# 4. Speed cap
# ---------------------------------------------------------------------------

func _clamp_speed() -> void:
	for id: int in _bodies:
		var b: SimBody = _bodies[id]
		var spd_sq: int = FP.FPVec2.length_squared(b.velocity)
		var cap_sq: int = FP.mul(max_speed, max_speed)
		if spd_sq > cap_sq:
			var spd: int = FP.FPVec2.length(b.velocity)
			if spd > 0:
				var scale: int = FP.div(max_speed, spd)
				b.velocity = FP.FPVec2.scale(b.velocity, scale)

# ---------------------------------------------------------------------------
# 5. Zone checks
# ---------------------------------------------------------------------------

func _check_zones() -> void:
	for id: int in _bodies:
		var b: SimBody = _bodies[id]
		for zone: SimZone in _zones:
			if zone.contains(b.position):
				zone_events.append({body_id = b.id, zone_id = zone.id})

# ---------------------------------------------------------------------------
# Polygon helper — world-space vertices using integer trig
# ---------------------------------------------------------------------------

## Transform body-local polygon vertices to world space.
func _world_vertices(body: SimBody) -> Array:
	var out: Array = []
	var cos_r: int = _fp_cos(body.rotation)
	var sin_r: int = _fp_sin(body.rotation)
	for v: Dictionary in body.vertices:
		# Rotate then translate
		var wx: int = FP.mul(v.x, cos_r) - FP.mul(v.y, sin_r) + body.position.x
		var wy: int = FP.mul(v.x, sin_r) + FP.mul(v.y, cos_r) + body.position.y
		out.append(FP.FPVec2.make(wx, wy))
	return out

# ---------------------------------------------------------------------------
# Integer trig (no floats — Taylor series with range reduction)
# ---------------------------------------------------------------------------

## Fixed-point sine.  Input is FP radians.
## Uses: sin(x) ≈ x − x³/6 + x⁵/120 − x⁷/5040  (max absolute error ≤ 0.0002 for |x| ≤ π/2)
##
## Two-step range reduction:
##  1. Normalise to [−π, π] via modulo.
##  2. Reduce to [−π/2, π/2] via sin(π − x) = sin(x), keeping the series
##     in the interval where the 7th-order polynomial is highly accurate.
static func _fp_sin(angle: int) -> int:
	# Step 1: normalise to [−π, π]
	var a: int = angle % FP_TWO_PI
	if a > FP_PI:
		a -= FP_TWO_PI
	elif a < -FP_PI:
		a += FP_TWO_PI

	# Step 2: further reduce to [−π/2, π/2] using sin(π − x) = sin(x)
	if a > FP_HALF_PI:
		a = FP_PI - a
	elif a < -FP_HALF_PI:
		a = -FP_PI - a

	var x2: int = FP.mul(a, a)
	var x3: int = FP.mul(x2, a)
	var x4: int = FP.mul(x2, x2)
	var x5: int = FP.mul(x4, a)
	var x7: int = FP.mul(x4, x3)
	# 1/6    ≈ 0.16667 → 10923 in 48.16
	# 1/120  ≈ 0.00833 →   546 in 48.16
	# 1/5040 ≈ 0.000198 →   13 in 48.16
	return a - FP.mul(x3, 10923) + FP.mul(x5, 546) - FP.mul(x7, 13)

## Fixed-point cosine.  cos(x) = sin(x + π/2).
static func _fp_cos(angle: int) -> int:
	return _fp_sin(angle + FP_HALF_PI)

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

static func _min_int(a: int, b: int) -> int:
	return a if a < b else b

static func _clamp_fp(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v
