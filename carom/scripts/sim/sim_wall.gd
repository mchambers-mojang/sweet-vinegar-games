class_name SimWall
extends RefCounted

## An infinite line segment used as an arena boundary.
## All values are 48.16 fixed-point integers.

## Endpoint A (FPVec2).
var a: Dictionary

## Endpoint B (FPVec2).
var b: Dictionary

## Outward-facing unit normal (FPVec2), pre-computed.
var normal: Dictionary

# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init() -> void:
	a      = FP.FPVec2.make(0, 0)
	b      = FP.FPVec2.make(0, 0)
	normal = FP.FPVec2.make(0, 0)

## Convenience factory: creates a wall from two endpoints and computes the
## left-hand outward normal automatically.
static func make(pa: Dictionary, pb: Dictionary) -> SimWall:
	var w: SimWall = SimWall.new()
	w.a = pa
	w.b = pb
	# Edge direction
	var dx: int = pb.x - pa.x
	var dy: int = pb.y - pa.y
	# Left-hand perpendicular (outward for CCW winding)
	var raw: Dictionary = FP.FPVec2.make(-dy, dx)
	w.normal = FP.FPVec2.normalize(raw)
	return w
