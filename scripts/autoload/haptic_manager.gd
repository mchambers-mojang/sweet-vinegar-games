extends Node

## Haptic feedback for touch interactions

const THROTTLE_MS := 50

# Initialised to -THROTTLE_MS so the very first vibrate call is never suppressed.
var _last_vibrate_msec: int = -THROTTLE_MS


func vibrate_light() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	_do_vibrate(15)


func vibrate_medium() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	_do_vibrate(30)


func vibrate_heavy() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	_do_vibrate(50)


func vibrate_error() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	_do_vibrate(80)


func vibrate_success() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	_do_vibrate(40)
	var t := create_tween()
	t.tween_callback(func() -> void: _do_vibrate(40)).set_delay(0.1)


## Cancel any active vibration immediately.
## Intentionally skips the haptic_enabled check — stopping must always work
## to prevent a stuck vibration even if the setting is toggled mid-session.
func stop() -> void:
	Input.vibrate_handheld(0)


func _do_vibrate(duration_ms: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_vibrate_msec < THROTTLE_MS:
		return  # Suppress rapid-fire calls to prevent vibration stacking
	_last_vibrate_msec = now
	Input.vibrate_handheld(duration_ms)
