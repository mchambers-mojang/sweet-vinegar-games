extends Node

## Platform display, feedback, and effects settings with persistence

signal settings_changed

const SAVE_PATH := "user://settings.cfg"

## Display
var dark_mode: String = "neon" # "system", "light", "dark", "neon", "custom"
var show_timer: bool = true

## Custom palette (defaults mirror the Neon palette)
var custom_palette_bg: Color = Color(0.04, 0.04, 0.1)
var custom_palette_accent: Color = Color(0.0, 1.5, 1.5)
var custom_palette_secondary: Color = Color(2.0, 0.3, 1.8)
var custom_palette_error: Color = Color(2.0, 0.0, 0.2)

## Feedback
var sound_enabled: bool = true
var haptic_enabled: bool = true

## Effects
var screen_shake_enabled: bool = true
var shockwave_enabled: bool = true
var particle_effects_enabled: bool = true


func _ready() -> void:
	load_settings()
	# Ensure window is resizable on desktop
	if not OS.has_feature("mobile"):
		get_window().unresizable = false


func save_settings() -> void:
	var previous := _snapshot()
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("display", "dark_mode", dark_mode)
	config.set_value("display", "show_timer", show_timer)
	config.set_value("display", "custom_palette_bg", custom_palette_bg)
	config.set_value("display", "custom_palette_accent", custom_palette_accent)
	config.set_value("display", "custom_palette_secondary", custom_palette_secondary)
	config.set_value("display", "custom_palette_error", custom_palette_error)
	config.set_value("feedback", "sound_enabled", sound_enabled)
	config.set_value("feedback", "haptic_enabled", haptic_enabled)
	config.set_value("effects", "screen_shake", screen_shake_enabled)
	config.set_value("effects", "shockwave", shockwave_enabled)
	config.set_value("effects", "particles", particle_effects_enabled)
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
	dark_mode = config.get_value("display", "dark_mode", dark_mode)
	show_timer = config.get_value("display", "show_timer", show_timer)
	custom_palette_bg = config.get_value("display", "custom_palette_bg", custom_palette_bg)
	custom_palette_accent = config.get_value("display", "custom_palette_accent", custom_palette_accent)
	custom_palette_secondary = config.get_value("display", "custom_palette_secondary", custom_palette_secondary)
	custom_palette_error = config.get_value("display", "custom_palette_error", custom_palette_error)
	sound_enabled = config.get_value("feedback", "sound_enabled", sound_enabled)
	haptic_enabled = config.get_value("feedback", "haptic_enabled", haptic_enabled)
	screen_shake_enabled = config.get_value("effects", "screen_shake", screen_shake_enabled)
	shockwave_enabled = config.get_value("effects", "shockwave", shockwave_enabled)
	particle_effects_enabled = config.get_value("effects", "particles", particle_effects_enabled)


func _snapshot() -> Dictionary:
	return {
		"dark_mode": dark_mode,
		"show_timer": show_timer,
		"sound_enabled": sound_enabled,
		"haptic_enabled": haptic_enabled,
		"screen_shake_enabled": screen_shake_enabled,
		"shockwave_enabled": shockwave_enabled,
		"particle_effects_enabled": particle_effects_enabled,
		"custom_palette_bg": custom_palette_bg.to_html(),
		"custom_palette_accent": custom_palette_accent.to_html(),
		"custom_palette_secondary": custom_palette_secondary.to_html(),
		"custom_palette_error": custom_palette_error.to_html(),
	}
