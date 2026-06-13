extends Node

## Haptic feedback for touch interactions


func vibrate_light() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	Input.vibrate_handheld(15)


func vibrate_medium() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	Input.vibrate_handheld(30)


func vibrate_heavy() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	Input.vibrate_handheld(50)


func vibrate_error() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	Input.vibrate_handheld(80)


func vibrate_success() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	Input.vibrate_handheld(40)
	var t := create_tween()
	t.tween_callback(func() -> void: Input.vibrate_handheld(40)).set_delay(0.1)
