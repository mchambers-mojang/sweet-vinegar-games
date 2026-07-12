class_name DisplaySettings
extends RefCounted

## Display settings sub-module: timer visibility.
## Owns validation and persistence for the [display] section of settings.cfg.
## Theme mode (dark/light/neon/custom) is owned by ThemePalette.

signal changed

var _show_timer: bool = true

var show_timer: bool:
	get:
		return _show_timer
	set(value):
		_show_timer = value
		changed.emit()


## Writes the display section into an already-loaded ConfigFile.
func save(config: ConfigFile) -> void:
	config.set_value("display", "show_timer", _show_timer)


## Reads the display section from a ConfigFile.
func load_from(config: ConfigFile) -> void:
	show_timer = config.get_value("display", "show_timer", _show_timer)
