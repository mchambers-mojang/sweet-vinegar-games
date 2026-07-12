extends Node

## Platform settings — dark mode, timer, sound, haptic, and effects.
## Palette storage moved to ThemePalette (#84). All palette CRUD is now via AppTheme.palette.

signal settings_changed

const SAVE_PATH := "user://settings.cfg"
const VALID_DARK_MODES: Array[String] = ["system", "light", "dark", "neon", "custom"]

## Display settings
var _dark_mode: String = "neon"
var _show_timer: bool = true

## Feedback settings
var _sound_enabled: bool = false
var _haptic_enabled: bool = true
var _screen_shake_enabled: bool = true
var _shockwave_enabled: bool = true
var _particle_effects_enabled: bool = true

var dark_mode: String:
	get:
		return _dark_mode
	set(value):
		if value in VALID_DARK_MODES:
			_dark_mode = value

var show_timer: bool:
	get:
		return _show_timer
	set(value):
		_show_timer = value

var sound_enabled: bool:
	get:
		return _sound_enabled
	set(value):
		_sound_enabled = value

var haptic_enabled: bool:
	get:
		return _haptic_enabled
	set(value):
		_haptic_enabled = value

var screen_shake_enabled: bool:
	get:
		return _screen_shake_enabled
	set(value):
		_screen_shake_enabled = value

var shockwave_enabled: bool:
	get:
		return _shockwave_enabled
	set(value):
		_shockwave_enabled = value

var particle_effects_enabled: bool:
	get:
		return _particle_effects_enabled
	set(value):
		_particle_effects_enabled = value


func _ready() -> void:
	load_settings()
	# Ensure window is resizable on desktop
	if not OS.has_feature("mobile"):
		get_window().unresizable = false


func save_settings() -> void:
	var previous := _snapshot()
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	_save_to_config(config)
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
	_load_from_config(config)


func _save_to_config(config: ConfigFile) -> void:
	config.set_value("display", "dark_mode", _dark_mode)
	config.set_value("display", "show_timer", _show_timer)
	config.set_value("feedback", "sound_enabled", _sound_enabled)
	config.set_value("feedback", "haptic_enabled", _haptic_enabled)
	config.set_value("effects", "screen_shake", _screen_shake_enabled)
	config.set_value("effects", "shockwave", _shockwave_enabled)
	config.set_value("effects", "particles", _particle_effects_enabled)


func _load_from_config(config: ConfigFile) -> void:
	dark_mode = config.get_value("display", "dark_mode", _dark_mode)
	show_timer = config.get_value("display", "show_timer", _show_timer)
	sound_enabled = config.get_value("feedback", "sound_enabled", _sound_enabled)
	haptic_enabled = config.get_value("feedback", "haptic_enabled", _haptic_enabled)
	screen_shake_enabled = config.get_value("effects", "screen_shake", _screen_shake_enabled)
	shockwave_enabled = config.get_value("effects", "shockwave", _shockwave_enabled)
	particle_effects_enabled = config.get_value("effects", "particles", _particle_effects_enabled)


func _snapshot() -> Dictionary:
	return {
		"dark_mode": dark_mode,
		"show_timer": show_timer,
		"sound_enabled": sound_enabled,
		"haptic_enabled": haptic_enabled,
		"screen_shake_enabled": screen_shake_enabled,
		"shockwave_enabled": shockwave_enabled,
		"particle_effects_enabled": particle_effects_enabled,
	}
