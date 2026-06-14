extends Node

## Platform settings coordinator — thin facade over DisplaySettings and FeedbackSettings.
## Palette storage remains here until issue #84 (ThemePalette) is resolved.

signal settings_changed

const SAVE_PATH := "user://settings.cfg"

## Sub-modules — access directly for fine-grained change signals.
var display: DisplaySettings = DisplaySettings.new()
var feedback: FeedbackSettings = FeedbackSettings.new()

## Display — delegated to DisplaySettings
var dark_mode: String:
	get:
		return display.dark_mode
	set(value):
		display.dark_mode = value

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

## Custom palettes (palette storage stays here until issue #84 is resolved)
## Each element: { "name": String, "bg": [r,g,b,a], "accent": [r,g,b,a], "secondary": [r,g,b,a], "error": [r,g,b,a] }
var custom_palettes: Array = []
var active_custom_palette_index: int = -1


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
	config.set_value("custom_palettes", "active_index", active_custom_palette_index)
	config.set_value("custom_palettes", "list", JSON.stringify(custom_palettes))
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
	active_custom_palette_index = config.get_value("custom_palettes", "active_index", -1)
	var json_str: String = config.get_value("custom_palettes", "list", "[]")
	var parsed = JSON.parse_string(json_str)
	if parsed is Array:
		custom_palettes = parsed


## Returns the active custom palette as { name, bg, accent, secondary, error: Color },
## or an empty dict if none is selected.
func get_active_custom_palette() -> Dictionary:
	if active_custom_palette_index >= 0 and active_custom_palette_index < custom_palettes.size():
		return _deserialize_palette(custom_palettes[active_custom_palette_index])
	return {}


## Returns palette at index as { name, bg, accent, secondary, error: Color }
func get_custom_palette(index: int) -> Dictionary:
	if index >= 0 and index < custom_palettes.size():
		return _deserialize_palette(custom_palettes[index])
	return {}


## Adds a new palette. Returns its index.
func add_custom_palette(name: String, bg: Color, accent: Color, secondary: Color, error: Color) -> int:
	custom_palettes.append(_serialize_palette(name, bg, accent, secondary, error))
	return custom_palettes.size() - 1


## Updates an existing palette in place.
func update_custom_palette(index: int, name: String, bg: Color, accent: Color, secondary: Color, error: Color) -> void:
	if index >= 0 and index < custom_palettes.size():
		custom_palettes[index] = _serialize_palette(name, bg, accent, secondary, error)


## Duplicates a palette and returns the new index.
func duplicate_custom_palette(index: int) -> int:
	if index < 0 or index >= custom_palettes.size():
		return -1
	var copy: Dictionary = custom_palettes[index].duplicate(true)
	copy["name"] = copy["name"] + " Copy"
	custom_palettes.append(copy)
	return custom_palettes.size() - 1


## Removes a palette and adjusts active index.
func remove_custom_palette(index: int) -> void:
	if index < 0 or index >= custom_palettes.size():
		return
	custom_palettes.remove_at(index)
	if active_custom_palette_index == index:
		active_custom_palette_index = -1
	elif active_custom_palette_index > index:
		active_custom_palette_index -= 1


## Returns a serialized palette dict (with color arrays) from raw Color values.
static func _serialize_palette(name: String, bg: Color, accent: Color, secondary: Color, error: Color) -> Dictionary:
	return {
		"name": name,
		"bg": _color_to_array(bg),
		"accent": _color_to_array(accent),
		"secondary": _color_to_array(secondary),
		"error": _color_to_array(error),
	}


## Converts a stored palette dict to one with typed Color values.
static func _deserialize_palette(p: Dictionary) -> Dictionary:
	return {
		"name": p.get("name", "Palette"),
		"bg": _array_to_color(p.get("bg", [])),
		"accent": _array_to_color(p.get("accent", [])),
		"secondary": _array_to_color(p.get("secondary", [])),
		"error": _array_to_color(p.get("error", [])),
	}


static func _color_to_array(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


static func _array_to_color(a: Array) -> Color:
	if a.size() >= 4:
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	if a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return Color(0.04, 0.04, 0.1)


## Default neon-based palette (cyan/pink/red) for new palettes.
static func default_palette_colors() -> Dictionary:
	return {
		"bg": Color(0.04, 0.04, 0.1),
		"accent": Color(0.0, 1.5, 1.5),
		"secondary": Color(2.0, 0.3, 1.8),
		"error": Color(2.0, 0.0, 0.2),
	}


## Ensures at least one default palette exists. Returns true if a new one was created.
func ensure_default_palette() -> bool:
	if custom_palettes.is_empty():
		var defaults: Dictionary = default_palette_colors()
		var new_idx := add_custom_palette(
			"My Palette",
			defaults["bg"], defaults["accent"], defaults["secondary"], defaults["error"]
		)
		active_custom_palette_index = new_idx
		return true
	return false


func _snapshot() -> Dictionary:
	var active_palette_name := ""
	var active := get_active_custom_palette()
	if not active.is_empty():
		active_palette_name = str(active.get("name", ""))
	return {
		"dark_mode": dark_mode,
		"show_timer": show_timer,
		"sound_enabled": sound_enabled,
		"haptic_enabled": haptic_enabled,
		"screen_shake_enabled": screen_shake_enabled,
		"shockwave_enabled": shockwave_enabled,
		"particle_effects_enabled": particle_effects_enabled,
		"active_custom_palette_index": active_custom_palette_index,
		"active_custom_palette_name": active_palette_name,
	}
