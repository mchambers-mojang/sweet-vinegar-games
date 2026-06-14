class_name DisplaySettings
extends RefCounted

## Display settings sub-module: theme mode and timer visibility.
## Owns validation and persistence for the [display] section of settings.cfg.

signal changed

const VALID_DARK_MODES: Array[String] = ["system", "light", "dark", "neon", "custom"]

var _dark_mode: String = "neon"
var _show_timer: bool = true

var dark_mode: String:
	get:
		return _dark_mode
	set(value):
		if value in VALID_DARK_MODES:
			_dark_mode = value
			changed.emit()

var show_timer: bool:
	get:
		return _show_timer
	set(value):
		_show_timer = value
		changed.emit()


## Writes the display section into an already-loaded ConfigFile.
func save(config: ConfigFile) -> void:
	config.set_value("display", "dark_mode", _dark_mode)
	config.set_value("display", "show_timer", _show_timer)


## Reads the display section from a ConfigFile.
func load_from(config: ConfigFile) -> void:
	dark_mode = config.get_value("display", "dark_mode", _dark_mode)
	show_timer = config.get_value("display", "show_timer", _show_timer)
