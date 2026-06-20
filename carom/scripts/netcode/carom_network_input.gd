class_name CaromNetworkInput
extends CaromTurretInput

## Turret input provider for the remote player in multiplayer.
##
## Each sim tick, the multiplayer controller feeds a decoded input (aim, fire,
## reload) via set_tick_input(). The turret polls process() every render frame
## but only the tick-aligned input matters for determinism.

var _aim_offset_degrees: float = 0.0
var _fire: bool = false
var _reload: bool = false
var _has_input: bool = false


## Feed decoded input for the current tick. Called once per sim tick by the
## multiplayer controller before the sim advances.
func set_tick_input(aim_fp: int, fire: bool, reload: bool, aim_arc_degrees: float) -> void:
	# Convert fixed-point aim (0..FP_TWO_PI) to degrees offset from center.
	# aim_fp represents absolute angle in radians (fixed-point).
	# Turret aim_offset is in degrees, centered at 0 with range ±arc/2.
	var aim_rad: float = FP.to_float(aim_fp)
	# Normalize to [-PI, PI] range for offset from forward
	var offset_rad: float = aim_rad - PI
	_aim_offset_degrees = clampf(
		rad_to_deg(offset_rad),
		-aim_arc_degrees * 0.5,
		aim_arc_degrees * 0.5
	)
	_fire = fire
	_reload = reload
	_has_input = true


func process(_delta: float, _turret_state: Dictionary) -> Dictionary:
	if not _has_input:
		return {}

	var commands: Dictionary = {}
	commands["aim_target"] = _aim_offset_degrees

	if _fire:
		commands["fire"] = true
		_fire = false  # Only fire once per tick

	if _reload:
		commands["start_reload"] = true
		_reload = false

	return commands


## Clear pending input (used when resetting between rounds).
func clear() -> void:
	_aim_offset_degrees = 0.0
	_fire = false
	_reload = false
	_has_input = false
