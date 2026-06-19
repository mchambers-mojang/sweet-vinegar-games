class_name SimZone
extends RefCounted

## Axis-aligned rectangular zone used for goal / trigger detection.
## All values are 48.16 fixed-point integers.

## Minimum corner (FPVec2) — lower-left in world space.
var min_pt: Dictionary

## Maximum corner (FPVec2) — upper-right in world space.
var max_pt: Dictionary

## Arbitrary identifier so callers can distinguish zones.
var id: int = 0

# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init() -> void:
	min_pt = FP.FPVec2.make(0, 0)
	max_pt = FP.FPVec2.make(0, 0)

## Convenience factory.
static func make(mn: Dictionary, mx: Dictionary, zone_id: int = 0) -> SimZone:
	var z: SimZone = SimZone.new()
	z.min_pt = mn
	z.max_pt = mx
	z.id     = zone_id
	return z

# ---------------------------------------------------------------------------
# Query
# ---------------------------------------------------------------------------

## Returns true if point (FPVec2) lies strictly inside or on the boundary.
func contains(point: Dictionary) -> bool:
	return (point.x >= min_pt.x and point.x <= max_pt.x
		and point.y >= min_pt.y and point.y <= max_pt.y)
