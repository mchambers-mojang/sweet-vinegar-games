class_name FeedbackSettings
extends RefCounted

## Feedback and effects settings sub-module.
## Owns validation and persistence for the [feedback] and [effects] sections of settings.cfg.

signal changed

var _sound_enabled: bool = true
var _haptic_enabled: bool = true
var _screen_shake_enabled: bool = true
var _shockwave_enabled: bool = true
var _particle_effects_enabled: bool = true

var sound_enabled: bool:
	get:
		return _sound_enabled
	set(value):
		_sound_enabled = value
		changed.emit()

var haptic_enabled: bool:
	get:
		return _haptic_enabled
	set(value):
		_haptic_enabled = value
		changed.emit()

var screen_shake_enabled: bool:
	get:
		return _screen_shake_enabled
	set(value):
		_screen_shake_enabled = value
		changed.emit()

var shockwave_enabled: bool:
	get:
		return _shockwave_enabled
	set(value):
		_shockwave_enabled = value
		changed.emit()

var particle_effects_enabled: bool:
	get:
		return _particle_effects_enabled
	set(value):
		_particle_effects_enabled = value
		changed.emit()


## Writes the feedback and effects sections into an already-loaded ConfigFile.
func save(config: ConfigFile) -> void:
	config.set_value("feedback", "sound_enabled", _sound_enabled)
	config.set_value("feedback", "haptic_enabled", _haptic_enabled)
	config.set_value("effects", "screen_shake", _screen_shake_enabled)
	config.set_value("effects", "shockwave", _shockwave_enabled)
	config.set_value("effects", "particles", _particle_effects_enabled)


## Reads the feedback and effects sections from a ConfigFile.
func load_from(config: ConfigFile) -> void:
	sound_enabled = config.get_value("feedback", "sound_enabled", _sound_enabled)
	haptic_enabled = config.get_value("feedback", "haptic_enabled", _haptic_enabled)
	screen_shake_enabled = config.get_value("effects", "screen_shake", _screen_shake_enabled)
	shockwave_enabled = config.get_value("effects", "shockwave", _shockwave_enabled)
	particle_effects_enabled = config.get_value("effects", "particles", _particle_effects_enabled)
