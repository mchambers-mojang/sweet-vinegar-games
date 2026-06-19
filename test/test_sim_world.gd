extends GutTest

## Unit tests for SimWorld — deterministic fixed-point physics simulation.
## All checks use integer arithmetic; floats appear only in assert helpers
## where GUT requires them.

const SimWorldScript := preload("res://carom/scripts/sim/sim_world.gd")
const SimBodyScript  := preload("res://carom/scripts/sim/sim_body.gd")
const SimWallScript  := preload("res://carom/scripts/sim/sim_wall.gd")
const SimZoneScript  := preload("res://carom/scripts/sim/sim_zone.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _fp(n: int) -> int:
	return FP.from_int(n)

func _fpf(f: float) -> int:
	return FP.from_float(f)

func _tof(fp: int) -> float:
	return FP.to_float(fp)

## Build a minimal SimWorld with no walls or zones.
func _make_world() -> SimWorld:
	return SimWorldScript.new()

## Create a circle body at (x, y) with given velocity and radius.
func _circle(x: int, y: int, vx: int, vy: int, r: int = 1) -> SimBody:
	var b: SimBody = SimBodyScript.new()
	b.shape      = SimBody.Shape.CIRCLE
	b.position   = FP.FPVec2.make(_fp(x), _fp(y))
	b.velocity   = FP.FPVec2.make(_fp(vx), _fp(vy))
	b.radius     = _fp(r)
	b.mass       = FP.ONE
	b.restitution = FP.ONE
	b.damping    = 0
	return b

## Add four walls forming a box from (−hw, −hh) to (+hw, +hh).
func _add_box_walls(world: SimWorld, hw: int, hh: int) -> void:
	# Bottom, Top, Left, Right (outward normal points inward to box)
	var left: int   = _fp(-hw)
	var right: int  = _fp(hw)
	var bottom: int = _fp(-hh)
	var top: int    = _fp(hh)

	# Bottom wall — normal points up (+y)
	world.add_wall(SimWallScript.make(
		FP.FPVec2.make(left,  bottom),
		FP.FPVec2.make(right, bottom)))
	# Top wall — normal points down (−y); swap a/b to flip normal
	world.add_wall(SimWallScript.make(
		FP.FPVec2.make(right, top),
		FP.FPVec2.make(left,  top)))
	# Left wall — normal points right (+x)
	world.add_wall(SimWallScript.make(
		FP.FPVec2.make(left, top),
		FP.FPVec2.make(left, bottom)))
	# Right wall — normal points left (−x)
	world.add_wall(SimWallScript.make(
		FP.FPVec2.make(right, bottom),
		FP.FPVec2.make(right, top)))

# ---------------------------------------------------------------------------
# 1. Two circles collide head-on — elastic equal-mass → velocities swap
# ---------------------------------------------------------------------------

func test_circle_circle_elastic_head_on_swaps_velocities() -> void:
	var world: SimWorld = _make_world()

	# A moves right at +5, B moves left at −5, placed just touching
	var a: SimBody = _circle(-1, 0,  5, 0)
	var b: SimBody = _circle( 1, 0, -5, 0)
	world.add_body(a)
	world.add_body(b)

	world.advance()

	# After elastic equal-mass head-on collision velocities must swap
	# A should now move left (negative x), B should move right (positive x)
	assert_true(a.velocity.x < 0,
		"A should now move left, got vx = %d" % a.velocity.x)
	assert_true(b.velocity.x > 0,
		"B should now move right, got vx = %d" % b.velocity.x)

	# Magnitudes should be ~5 (allow small tolerance from fixed-point rounding)
	var a_speed: float = _tof(FP.abs_fp(a.velocity.x))
	var b_speed: float = _tof(FP.abs_fp(b.velocity.x))
	assert_almost_eq(a_speed, 5.0, 0.1, "A speed should be ~5")
	assert_almost_eq(b_speed, 5.0, 0.1, "B speed should be ~5")

# ---------------------------------------------------------------------------
# 2. Circle hits wall and reflects correctly
# ---------------------------------------------------------------------------

func test_circle_wall_reflection() -> void:
	var world: SimWorld = _make_world()
	_add_box_walls(world, 20, 20)

	# Ball moving right, starting just inside the right wall (will overlap after integration)
	var b: SimBody = _circle(19, 0, 3, 0)
	world.add_body(b)

	# Advance until it bounces — should trigger on the first or second tick
	for _i in range(5):
		world.advance()

	# Velocity x should have reversed
	assert_true(b.velocity.x <= 0,
		"Ball should have bounced off right wall, vx = %d" % b.velocity.x)

# ---------------------------------------------------------------------------
# 3. Body with damping comes to rest within expected ticks
# ---------------------------------------------------------------------------

func test_damped_body_comes_to_rest() -> void:
	var world: SimWorld = _make_world()

	# Use a large box so we don't hit walls
	_add_box_walls(world, 1000, 1000)

	var b: SimBody = _circle(0, 0, 3, 0)
	# ~5 % damping per tick
	b.damping = _fpf(0.05)
	world.add_body(b)

	# After enough ticks the speed should be < 0.1 units
	for _i in range(200):
		world.advance()

	var speed: float = _tof(FP.FPVec2.length(b.velocity))
	assert_lt(speed, 0.1, "Damped body should come to rest, speed = %f" % speed)

# ---------------------------------------------------------------------------
# 4. Speed cap prevents velocity exceeding max
# ---------------------------------------------------------------------------

func test_speed_cap_clamps_velocity() -> void:
	var world: SimWorld = _make_world()
	world.max_speed = _fp(10)   # cap at 10 units/tick

	# Start with velocity well above the cap
	var b: SimBody = _circle(0, 0, 50, 0)
	world.add_body(b)

	world.advance()

	var speed: float = _tof(FP.FPVec2.length(b.velocity))
	assert_le(speed, 10.1, "Speed should be capped at 10, got %f" % speed)

# ---------------------------------------------------------------------------
# 5. Zone detection triggers when body centre enters
# ---------------------------------------------------------------------------

func test_zone_detection_triggers() -> void:
	var world: SimWorld = _make_world()

	var zone: SimZone = SimZoneScript.make(
		FP.FPVec2.make(_fp(5),  _fp(-2)),
		FP.FPVec2.make(_fp(15), _fp(2)),
		42)
	world.add_zone(zone)

	# Body starts just outside zone, moving into it at speed 3
	var b: SimBody = _circle(4, 0, 3, 0)
	world.add_body(b)

	var triggered: bool = false
	for _i in range(40):
		world.advance()
		for ev: Dictionary in world.zone_events:
			if ev.zone_id == 42 and ev.body_id == b.id:
				triggered = true
				break
		if triggered:
			break

	assert_true(triggered, "Zone event should have fired when body entered zone 42")

# ---------------------------------------------------------------------------
# 6. Serialize → deserialize → advance produces identical result
# ---------------------------------------------------------------------------

func test_serialize_deserialize_advance_identical() -> void:
	var world_a: SimWorld = _make_world()
	_add_box_walls(world_a, 20, 20)

	var b1: SimBody = _circle(-5, 0,  3,  1)
	var b2: SimBody = _circle( 5, 0, -3, -1)
	world_a.add_body(b1)
	world_a.add_body(b2)

	# Run 10 ticks to get an interesting state
	for _i in range(10):
		world_a.advance()

	# Snapshot
	var state: Dictionary = world_a.get_body_state()

	# Clone via serialisation
	var world_b: SimWorld = _make_world()
	_add_box_walls(world_b, 20, 20)
	world_b.set_body_state(state)

	# Advance both one more tick
	world_a.advance()
	world_b.advance()

	# Positions and velocities must match exactly (bit-for-bit)
	var final_a: Dictionary = world_a.get_body_state()
	var final_b: Dictionary = world_b.get_body_state()
	for id_str: String in final_a.bodies.keys():
		var sa: Dictionary = final_a.bodies[id_str]
		var sb: Dictionary = final_b.bodies[id_str]
		assert_eq(sa.pos_x, sb.pos_x, "pos_x mismatch for body %s" % id_str)
		assert_eq(sa.pos_y, sb.pos_y, "pos_y mismatch for body %s" % id_str)
		assert_eq(sa.vel_x, sb.vel_x, "vel_x mismatch for body %s" % id_str)
		assert_eq(sa.vel_y, sb.vel_y, "vel_y mismatch for body %s" % id_str)

# ---------------------------------------------------------------------------
# 7. Determinism self-check — 100 ticks, same inputs → identical final state
# ---------------------------------------------------------------------------

func test_determinism_100_ticks() -> void:
	# Build and run world A from scratch
	var world_a: SimWorld = _make_world()
	_add_box_walls(world_a, 15, 10)
	var a1: SimBody = _circle(-6, 0,  4,  2)
	var a2: SimBody = _circle( 6, 0, -4, -2)
	a1.id = 1
	a2.id = 2
	world_a.add_body(a1)
	world_a.add_body(a2)

	# Build and run world B identically
	var world_b: SimWorld = _make_world()
	_add_box_walls(world_b, 15, 10)
	var b1: SimBody = _circle(-6, 0,  4,  2)
	var b2: SimBody = _circle( 6, 0, -4, -2)
	b1.id = 1
	b2.id = 2
	world_b.add_body(b1)
	world_b.add_body(b2)

	for _i in range(100):
		world_a.advance()
		world_b.advance()

	var state_a: Dictionary = world_a.get_body_state()
	var state_b: Dictionary = world_b.get_body_state()

	for id_str: String in state_a.bodies.keys():
		var sa: Dictionary = state_a.bodies[id_str]
		var sb: Dictionary = state_b.bodies[id_str]
		assert_eq(sa.pos_x, sb.pos_x, "Determinism: pos_x mismatch body %s" % id_str)
		assert_eq(sa.pos_y, sb.pos_y, "Determinism: pos_y mismatch body %s" % id_str)
		assert_eq(sa.vel_x, sb.vel_x, "Determinism: vel_x mismatch body %s" % id_str)
		assert_eq(sa.vel_y, sb.vel_y, "Determinism: vel_y mismatch body %s" % id_str)

# ---------------------------------------------------------------------------
# 8. Timer — starts at MATCH_DURATION_TICKS, expires after exactly that many ticks
# ---------------------------------------------------------------------------

func test_timer_starts_at_match_duration() -> void:
	var world: SimWorld = _make_world()
	assert_eq(world.get_timer_ticks_remaining(), SimWorld.MATCH_DURATION_TICKS,
		"Timer should start at MATCH_DURATION_TICKS (%d)" % SimWorld.MATCH_DURATION_TICKS)
	assert_false(world.time_expired, "time_expired must be false at start")


func test_timer_reaches_zero_after_full_duration() -> void:
	var world: SimWorld = _make_world()
	for _i in range(SimWorld.MATCH_DURATION_TICKS):
		world.advance()
	assert_eq(world.get_timer_ticks_remaining(), 0, "Timer should be 0 after full duration")
	assert_true(world.time_expired, "time_expired should be true after full duration")


func test_timer_not_expired_one_tick_before() -> void:
	var world: SimWorld = _make_world()
	for _i in range(SimWorld.MATCH_DURATION_TICKS - 1):
		world.advance()
	assert_false(world.time_expired,
		"time_expired must still be false one tick before expiry")
	assert_eq(world.get_timer_ticks_remaining(), 1,
		"One tick should remain before expiry")


func test_timer_snapshot_restore_preserves_ticks() -> void:
	var world: SimWorld = _make_world()
	# Advance partway through the match
	for _i in range(100):
		world.advance()

	var snapshot: Dictionary = world.get_body_state()
	var ticks_at_snapshot: int = world.get_timer_ticks_remaining()

	# Continue advancing
	for _i in range(50):
		world.advance()

	# Restore from snapshot and verify timer is back to snapshot value
	var world_b: SimWorld = _make_world()
	world_b.set_body_state(snapshot)
	assert_eq(world_b.get_timer_ticks_remaining(), ticks_at_snapshot,
		"Restored timer should match snapshot value")


func test_timer_sudden_death_no_decrement() -> void:
	var world: SimWorld = _make_world()
	world.sudden_death = true
	var ticks_before: int = world.get_timer_ticks_remaining()
	for _i in range(100):
		world.advance()
	assert_eq(world.get_timer_ticks_remaining(), ticks_before,
		"Timer must not decrement in sudden death mode")
	assert_false(world.time_expired,
		"time_expired must not be set in sudden death mode")


func test_timer_snapshot_preserves_sudden_death_flag() -> void:
	var world: SimWorld = _make_world()
	world.sudden_death = true
	var snapshot: Dictionary = world.get_body_state()

	var world_b: SimWorld = _make_world()
	world_b.set_body_state(snapshot)
	assert_true(world_b.sudden_death,
		"sudden_death flag should survive snapshot/restore")
