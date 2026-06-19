class_name SimBody
extends RefCounted

## A physics body in the deterministic simulation.
## All numeric properties are 48.16 fixed-point integers (FP library).
## No float arithmetic is used anywhere in the simulation loop.

# ---------------------------------------------------------------------------
# Shape type
# ---------------------------------------------------------------------------

enum Shape { CIRCLE, POLYGON }

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

var id: int = 0

# ---------------------------------------------------------------------------
# Spatial state — all FP integers
# ---------------------------------------------------------------------------

var position: Dictionary         ## FPVec2
var velocity: Dictionary         ## FPVec2

## Circle: collision radius (FP).
var radius: int = 0

## Polygon: vertices in local (body) space as Array of FPVec2 Dictionaries.
var vertices: Array = []

## Polygon: current orientation in FP radians and angular velocity per tick.
var rotation: int = 0
var angular_velocity: int = 0

# ---------------------------------------------------------------------------
# Physical properties — all FP integers
# ---------------------------------------------------------------------------

var mass: int = FP.ONE            ## > 0 always
var restitution: int = FP.ONE     ## 1.0 = perfectly elastic, 0 = inelastic
var damping: int = 0              ## velocity = velocity * (ONE - damping) per tick

# ---------------------------------------------------------------------------
# Shape selector
# ---------------------------------------------------------------------------

var shape: Shape = Shape.CIRCLE

# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init() -> void:
	position = FP.FPVec2.make(0, 0)
	velocity  = FP.FPVec2.make(0, 0)

# ---------------------------------------------------------------------------
# Serialisation (byte-deterministic: same state → same Dictionary)
# ---------------------------------------------------------------------------

func get_state() -> Dictionary:
	return {
		id               = id,
		shape            = shape,
		pos_x            = position.x,
		pos_y            = position.y,
		vel_x            = velocity.x,
		vel_y            = velocity.y,
		radius           = radius,
		rotation         = rotation,
		angular_velocity = angular_velocity,
		mass             = mass,
		restitution      = restitution,
		damping          = damping,
		vertices         = _pack_vertices(),
	}

func set_state(s: Dictionary) -> void:
	id               = s.id
	shape            = s.shape
	position         = FP.FPVec2.make(s.pos_x, s.pos_y)
	velocity         = FP.FPVec2.make(s.vel_x, s.vel_y)
	radius           = s.radius
	rotation         = s.rotation
	angular_velocity = s.angular_velocity
	mass             = s.mass
	restitution      = s.restitution
	damping          = s.damping
	_unpack_vertices(s.vertices)

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _pack_vertices() -> Array:
	var out: Array = []
	for v: Dictionary in vertices:
		out.append({x = v.x, y = v.y})
	return out

func _unpack_vertices(data: Array) -> void:
	vertices = []
	for e: Dictionary in data:
		vertices.append(FP.FPVec2.make(e.x, e.y))
