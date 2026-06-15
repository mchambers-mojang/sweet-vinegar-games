extends RefCounted

const MATCH_WIN_ZOOM_RATIO: float = 0.65
const MATCH_WIN_CAMERA_SHIFT_RATIO: float = 0.35
const MATCH_WIN_ZOOM_IN_SECONDS: float = 0.4
const MATCH_WIN_ZOOM_OUT_SECONDS: float = 0.6
const MATCH_WIN_SHAKE_INTENSITY: float = 0.9
const GOAL_SHAKE_INTENSITY: float = 0.4
const GOAL_ZOOM_RATIO: float = 0.9
const GOAL_ZOOM_IN_SECONDS: float = 0.15
const GOAL_ZOOM_OUT_SECONDS: float = 0.3
const GOAL_CAMERA_SHIFT_RATIO: float = 0.1
const MIN_TIME_SCALE_CLAMP: float = 0.001

var _camera: Camera3D = null
var _screen_shake: CaromScreenShake = null


func setup(camera: Camera3D, screen_shake: CaromScreenShake) -> void:
	_camera = camera
	_screen_shake = screen_shake


func play_goal_camera(goal_position: Vector3) -> void:
	if _camera == null:
		return

	if _screen_shake:
		_screen_shake.shake(GOAL_SHAKE_INTENSITY)

	var start_position: Vector3 = _camera.global_position
	var target_position: Vector3 = Vector3(goal_position.x, start_position.y, goal_position.z)
	var zoom_position: Vector3 = start_position.lerp(target_position, GOAL_CAMERA_SHIFT_RATIO)

	var zoom_tween := _camera.create_tween()
	zoom_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		var start_size: float = _camera.size
		zoom_tween.tween_property(_camera, "size", start_size * GOAL_ZOOM_RATIO, GOAL_ZOOM_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		zoom_tween.parallel().tween_property(_camera, "global_position", zoom_position, GOAL_ZOOM_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		zoom_tween.tween_property(_camera, "size", start_size, GOAL_ZOOM_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		zoom_tween.parallel().tween_property(_camera, "global_position", start_position, GOAL_ZOOM_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	else:
		var start_fov: float = _camera.fov
		zoom_tween.tween_property(_camera, "fov", start_fov * GOAL_ZOOM_RATIO, GOAL_ZOOM_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		zoom_tween.parallel().tween_property(_camera, "global_position", zoom_position, GOAL_ZOOM_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		zoom_tween.tween_property(_camera, "fov", start_fov, GOAL_ZOOM_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		zoom_tween.parallel().tween_property(_camera, "global_position", start_position, GOAL_ZOOM_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func play_match_win(goal_position: Vector3) -> void:
	if _camera == null:
		return

	if _screen_shake:
		_screen_shake.shake(MATCH_WIN_SHAKE_INTENSITY)

	var start_position: Vector3 = _camera.global_position
	var target_position: Vector3 = Vector3(goal_position.x, start_position.y, goal_position.z)
	var zoom_position: Vector3 = start_position.lerp(target_position, MATCH_WIN_CAMERA_SHIFT_RATIO)

	var zoom_tween := _camera.create_tween()
	zoom_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	zoom_tween.set_speed_scale(1.0 / maxf(Engine.time_scale, MIN_TIME_SCALE_CLAMP))

	if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		var start_size: float = _camera.size
		zoom_tween.tween_property(_camera, "size", start_size * MATCH_WIN_ZOOM_RATIO, MATCH_WIN_ZOOM_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		zoom_tween.parallel().tween_property(_camera, "global_position", zoom_position, MATCH_WIN_ZOOM_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		zoom_tween.tween_property(_camera, "size", start_size, MATCH_WIN_ZOOM_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		zoom_tween.parallel().tween_property(_camera, "global_position", start_position, MATCH_WIN_ZOOM_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	else:
		var start_fov: float = _camera.fov
		zoom_tween.tween_property(_camera, "fov", start_fov * MATCH_WIN_ZOOM_RATIO, MATCH_WIN_ZOOM_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		zoom_tween.parallel().tween_property(_camera, "global_position", zoom_position, MATCH_WIN_ZOOM_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		zoom_tween.tween_property(_camera, "fov", start_fov, MATCH_WIN_ZOOM_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		zoom_tween.parallel().tween_property(_camera, "global_position", start_position, MATCH_WIN_ZOOM_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
