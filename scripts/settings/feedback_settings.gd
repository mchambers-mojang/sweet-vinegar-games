class_name FeedbackSettings
extends RefCounted

## Feedback and effects settings sub-module.
## Owns validation and persistence for the [feedback] and [effects] sections of settings.cfg.

signal changed

var sound_enabled: bool = true:
	set(value):
		sound_enabled = value
		changed.emit()

var haptic_enabled: bool = true:
	set(value):
		haptic_enabled = value
		changed.emit()

var screen_shake_enabled: bool = true:
	set(value):
		screen_shake_enabled = value
		changed.emit()

var shockwave_enabled: bool = true:
	set(value):
		shockwave_enabled = value
		changed.emit()

var particle_effects_enabled: bool = true:
	set(value):
		particle_effects_enabled = value
		changed.emit()


## Writes the feedback and effects sections into an already-loaded ConfigFile.
func save(config: ConfigFile) -> void:
	config.set_value("feedback", "sound_enabled", sound_enabled)
	config.set_value("feedback", "haptic_enabled", haptic_enabled)
	config.set_value("effects", "screen_shake", screen_shake_enabled)
	config.set_value("effects", "shockwave", shockwave_enabled)
	config.set_value("effects", "particles", particle_effects_enabled)


## Reads the feedback and effects sections from a ConfigFile.
func load_from(config: ConfigFile) -> void:
	sound_enabled = config.get_value("feedback", "sound_enabled", sound_enabled)
	haptic_enabled = config.get_value("feedback", "haptic_enabled", haptic_enabled)
	screen_shake_enabled = config.get_value("effects", "screen_shake", screen_shake_enabled)
	shockwave_enabled = config.get_value("effects", "shockwave", shockwave_enabled)
	particle_effects_enabled = config.get_value("effects", "particles", particle_effects_enabled)
