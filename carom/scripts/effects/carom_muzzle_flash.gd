class_name CaromMuzzleFlash
extends Node3D

## Brief team-colored OmniLight3D burst at the turret barrel tip.
## Spawned once per shot via spawn(); self-destructs after the flash fades.

const FLASH_DURATION: float = 0.1
const FLASH_ENERGY: float = 8.0
const FLASH_RANGE: float = 1.5


## Spawn a muzzle flash at the given world position with the given team color.
static func spawn(pos: Vector3, color: Color, parent: Node) -> void:
	var flash := CaromMuzzleFlash.new()
	parent.add_child(flash)
	flash.global_position = pos
	flash._begin(color)


func _begin(color: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = FLASH_ENERGY
	light.omni_range = FLASH_RANGE
	add_child(light)

	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, FLASH_DURATION)
	tween.tween_callback(queue_free)
