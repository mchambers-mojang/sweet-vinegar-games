class_name CaromScreenShake
extends Node

## Camera shake utility — attach as child of Camera3D.
## Call shake() with intensity and optional duration/decay.

@export var default_decay: float = 4.0
@export var max_offset: float = 0.5

var _trauma: float = 0.0
var _camera: Camera3D = null


func _ready() -> void:
	_camera = get_parent() as Camera3D
	if _camera == null:
		push_warning("CaromScreenShake must be a child of Camera3D")


func _process(delta: float) -> void:
	if _trauma <= 0.0:
		return

	_trauma = maxf(0.0, _trauma - default_decay * delta)

	if _camera:
		var shake_amount := _trauma * _trauma  # Quadratic falloff
		var offset_x := randf_range(-1.0, 1.0) * max_offset * shake_amount
		var offset_y := randf_range(-1.0, 1.0) * max_offset * shake_amount
		_camera.h_offset = offset_x
		_camera.v_offset = offset_y

		if _trauma <= 0.0:
			_camera.h_offset = 0.0
			_camera.v_offset = 0.0


## Add trauma (0.0–1.0). Stacks with existing shake.
func shake(intensity: float = 0.5) -> void:
	_trauma = clampf(_trauma + intensity, 0.0, 1.0)


## Hard reset — immediately stop shaking.
func reset() -> void:
	_trauma = 0.0
	if _camera:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
