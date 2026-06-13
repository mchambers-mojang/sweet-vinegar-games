class_name CaromTurretInput
extends RefCounted

## Base class for turret input providers.
## Subclasses implement process() to return commands each frame.
## The turret polls this every frame and applies the returned commands.

## Turret state snapshot (passed to process each frame):
##   aim_offset: float — current aim offset in degrees
##   aim_arc: float — max aim arc in degrees
##   aim_speed: float — aim speed in degrees/sec
##   base_yaw: float — base yaw in degrees
##   ammo: int — current ammo
##   clip_size: int — max ammo
##   is_reloading: bool
##   is_active: bool
##   global_position: Vector3

## Command dictionary (returned from process):
##   aim_target: float — desired aim offset in degrees (turret interpolates)
##   fire: bool — attempt to fire this frame
##   start_reload: bool — start reloading
##   cancel_reload: bool — cancel active reload


func process(_delta: float, _turret_state: Dictionary) -> Dictionary:
	return {}
