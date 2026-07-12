extends Node

## Platform settings coordinator — thin facade over DisplaySettings and FeedbackSettings.
## Theme mode (dark/light/neon/custom) is owned by ThemePalette — access via AppTheme.palette.

signal settings_changed

const SAVE_PATH := "user://settings.cfg"

## Sub-modules — access directly for fine-grained change signals.
var display: DisplaySettings = DisplaySettings.new()
var feedback: FeedbackSettings = FeedbackSettings.new()

## Display — delegated to DisplaySettings
var show_timer: bool:
	get:
		return display.show_timer
	set(value):
		display.show_timer = value

## Feedback — delegated to FeedbackSettings
var sound_enabled: bool:
	get:
		return feedback.sound_enabled
	set(value):
		feedback.sound_enabled = value

var haptic_enabled: bool:
	get:
		return feedback.haptic_enabled
	set(value):
		feedback.haptic_enabled = value

## Effects — delegated to FeedbackSettings
var screen_shake_enabled: bool:
	get:
		return feedback.screen_shake_enabled
	set(value):
		feedback.screen_shake_enabled = value

var shockwave_enabled: bool:
	get:
		return feedback.shockwave_enabled
	set(value):
		feedback.shockwave_enabled = value

var particle_effects_enabled: bool:
	get:
		return feedback.particle_effects_enabled
	set(value):
		feedback.particle_effects_enabled = value


func _ready() -> void:
	load_settings()
	# Ensure window is resizable on desktop
	if not OS.has_feature("mobile"):
		get_window().unresizable = false


func save_settings() -> void:
	var previous := _snapshot()
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	display.save(config)
	feedback.save(config)
	config.save(SAVE_PATH)
	settings_changed.emit()

	var current := _snapshot()
	for key in current.keys():
		if previous.get(key) != current.get(key):
			AnalyticsManager.log_event("setting_changed", {
				"setting": key,
				"value": current[key],
			})


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	display.load_from(config)
	feedback.load_from(config)


func _snapshot() -> Dictionary:
	return {
		"show_timer": show_timer,
		"sound_enabled": sound_enabled,
		"haptic_enabled": haptic_enabled,
		"screen_shake_enabled": screen_shake_enabled,
		"shockwave_enabled": shockwave_enabled,
		"particle_effects_enabled": particle_effects_enabled,
	}
