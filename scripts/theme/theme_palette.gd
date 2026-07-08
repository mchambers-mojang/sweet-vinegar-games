class_name ThemePalette
extends RefCounted

## Owns the full palette data model: color derivation, CRUD for custom palettes,
## mode switching (dark/light/neon/custom), and persistence.
## AppTheme instantiates one ThemePalette and rebuilds the Theme resource on
## palette_changed. ThemeEditorScreen uses this interface directly via AppTheme.palette.

signal palette_changed

const SAVE_PATH := "user://settings.cfg"

## Current active mode: "system", "light", "dark", "neon", "custom"
var _mode: String = "light"

## Live color dictionary — modified in-place by _apply_color_set().
## AppTheme.colors is assigned to point at this same object so all callers
## that reference AppTheme.colors see live values without an extra copy.
var _colors: Dictionary = {
	"background": Color.WHITE,
	"cell_background": Color.WHITE,
	"cell_selected": Color(0.85, 0.92, 1.0),
	"cell_highlighted": Color(0.92, 0.95, 1.0),
	"cell_same_number": Color(0.80, 0.88, 1.0),
	"cell_error": Color(1.0, 0.85, 0.85),
	"cell_given": Color(0.96, 0.96, 0.96),
	"grid_line_thin": Color(0.75, 0.75, 0.75),
	"grid_line_thick": Color(0.2, 0.2, 0.2),
	"text_given": Color(0.1, 0.1, 0.1),
	"text_placed": Color(0.2, 0.4, 0.8),
	"text_error": Color(0.9, 0.2, 0.2),
	"text_pencil": Color(0.5, 0.5, 0.5),
	"text_primary": Color(0.1, 0.1, 0.1),
	"text_secondary": Color(0.2, 0.4, 0.8),
	"button_bg": Color(0.92, 0.92, 0.92),
	"button_bg_hover": Color(0.85, 0.88, 0.95),
	"button_bg_pressed": Color(0.78, 0.82, 0.92),
	"button_text": Color(0.15, 0.15, 0.15),
	"button_disabled": Color(0.75, 0.75, 0.75),
	"button_disabled_text": Color(0.55, 0.55, 0.55),
	"label_text": Color(0.1, 0.1, 0.1),
	"timer_text": Color(0.4, 0.4, 0.4),
	"strike_active": Color(0.9, 0.2, 0.2),
	"strike_inactive": Color(0.8, 0.8, 0.8),
}

## Resolved flags — set by set_mode(), consumed by AppTheme to drive Theme building.
var is_dark: bool = false
var is_neon: bool = false

## Custom palette storage. Each element:
## { "name": String, "bg": [r,g,b,a], "accent": [...], "secondary": [...], "error": [...] }
var custom_palettes: Array = []
var active_custom_palette_index: int = -1

# ---------------------------------------------------------------------------
# Built-in color sets (private)
# ---------------------------------------------------------------------------

var _light_colors: Dictionary
var _dark_colors: Dictionary = {
	"background": Color(0.1, 0.1, 0.12),
	"cell_background": Color(0.15, 0.15, 0.18),
	"cell_selected": Color(0.2, 0.28, 0.4),
	"cell_highlighted": Color(0.18, 0.2, 0.28),
	"cell_same_number": Color(0.22, 0.3, 0.45),
	"cell_error": Color(0.4, 0.15, 0.15),
	"cell_given": Color(0.18, 0.18, 0.22),
	"grid_line_thin": Color(0.35, 0.35, 0.4),
	"grid_line_thick": Color(0.7, 0.7, 0.75),
	"text_given": Color(0.9, 0.9, 0.9),
	"text_placed": Color(0.5, 0.7, 1.0),
	"text_error": Color(1.0, 0.4, 0.4),
	"text_pencil": Color(0.6, 0.6, 0.65),
	"text_primary": Color(0.9, 0.9, 0.9),
	"text_secondary": Color(0.5, 0.7, 1.0),
	"button_bg": Color(0.22, 0.22, 0.27),
	"button_bg_hover": Color(0.28, 0.28, 0.35),
	"button_bg_pressed": Color(0.18, 0.18, 0.22),
	"button_text": Color(0.88, 0.88, 0.92),
	"button_disabled": Color(0.2, 0.2, 0.24),
	"button_disabled_text": Color(0.45, 0.45, 0.5),
	"label_text": Color(0.88, 0.88, 0.92),
	"timer_text": Color(0.6, 0.6, 0.65),
	"strike_active": Color(1.0, 0.4, 0.4),
	"strike_inactive": Color(0.35, 0.35, 0.4),
}
var _neon_colors: Dictionary = {
	"background": Color(0.04, 0.04, 0.1),
	"cell_background": Color(0.06, 0.06, 0.14),
	"cell_selected": Color(0.12, 0.14, 0.3),
	"cell_highlighted": Color(0.1, 0.08, 0.22),
	"cell_same_number": Color(0.15, 0.05, 0.35),
	"cell_error": Color(0.5, 0.0, 0.1),
	"cell_given": Color(0.08, 0.08, 0.18),
	"grid_line_thin": Color(0.15, 0.1, 0.35),
	"grid_line_thick": Color(0.0, 1.5, 1.5),       # HDR cyan — will bloom
	"text_given": Color(0.0, 2.0, 1.6),             # HDR cyan text — blooms
	"text_placed": Color(2.0, 0.3, 1.8),            # HDR hot pink — blooms
	"text_error": Color(2.0, 0.0, 0.2),             # HDR red — blooms
	"text_pencil": Color(0.2, 0.15, 0.5),
	"text_primary": Color(0.0, 2.0, 1.6),           # HDR cyan — same as text_given
	"text_secondary": Color(2.0, 0.3, 1.8),         # HDR hot pink — same as text_placed
	"button_bg": Color(0.08, 0.06, 0.18),
	"button_bg_hover": Color(0.12, 0.08, 0.28),
	"button_bg_pressed": Color(0.06, 0.04, 0.14),
	"button_text": Color(0.0, 1.5, 1.5),            # HDR cyan buttons
	"button_disabled": Color(0.08, 0.06, 0.14),
	"button_disabled_text": Color(0.25, 0.2, 0.4),
	"label_text": Color(0.0, 1.5, 1.5),             # HDR cyan labels
	"timer_text": Color(1.5, 0.2, 1.2),             # HDR magenta
	"strike_active": Color(2.0, 0.0, 0.2),
	"strike_inactive": Color(0.2, 0.15, 0.35),
}


func _init() -> void:
	# Snapshot the light defaults (initial _colors values) so we can restore them.
	_light_colors = _colors.duplicate()


# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

## Switch to the given mode and emit palette_changed.
## Callers: AppTheme._apply_theme_setting(), AppTheme.set_theme_mode(), ThemeEditorScreen.
func set_mode(mode: String) -> void:
	_mode = mode
	match mode:
		"system":
			is_neon = false
			is_dark = DisplayServer.is_dark_mode() if DisplayServer.has_method("is_dark_mode") else false
			_apply_color_set(_dark_colors if is_dark else _light_colors)
		"dark":
			is_neon = false
			is_dark = true
			_apply_color_set(_dark_colors)
		"light":
			is_neon = false
			is_dark = false
			_apply_color_set(_light_colors)
		"neon":
			is_neon = true
			is_dark = true
			_apply_color_set(_neon_colors)
		"custom":
			is_neon = true
			is_dark = true
			var pal: Dictionary = get_active_custom_palette()
			if not pal.is_empty():
				_apply_color_set(build_custom(pal["bg"], pal["accent"], pal["secondary"], pal["error"]))
			else:
				_apply_color_set(_neon_colors)
	palette_changed.emit()


## Look up a color by key; returns Color.MAGENTA if the key is unknown.
func get_color(key: String) -> Color:
	return _colors.get(key, Color.MAGENTA)


## Persist custom palette arrays to settings.cfg.
## Only writes the [custom_palettes] section; mode persistence is handled by
## AppTheme._on_palette_changed() to keep ThemePalette free of PlatformSettings coupling.
func save() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("custom_palettes", "active_index", active_custom_palette_index)
	config.set_value("custom_palettes", "list", JSON.stringify(custom_palettes))
	config.save(SAVE_PATH)


## Load custom palette arrays from settings.cfg.
func load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	active_custom_palette_index = config.get_value("custom_palettes", "active_index", -1)
	var json_str: String = config.get_value("custom_palettes", "list", "[]")
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed is Array:
		custom_palettes = parsed


## Derives a full 22-key color palette from 4 user-chosen base colors.
## Intended for the "custom" neon-style theme mode.
## [b]accent[/b], [b]secondary[/b], and [b]error[/b] may carry HDR values (>1.0)
## to drive neon bloom; derived surface/cell colors are clamped to [0, 1].
static func build_custom(bg: Color, accent: Color, secondary: Color, error: Color) -> Dictionary:
	# Background variants — slight brightness offsets to keep the dark neon feel.
	var s := 0.03  # step
	var cell_bg := Color(
		clampf(bg.r + s, 0.0, 1.0),
		clampf(bg.g + s, 0.0, 1.0),
		clampf(bg.b + s * 1.5, 0.0, 1.0))
	var cell_given := Color(
		clampf(bg.r + s * 1.5, 0.0, 1.0),
		clampf(bg.g + s * 1.5, 0.0, 1.0),
		clampf(bg.b + s * 3.0, 0.0, 1.0))
	var btn_bg := Color(
		clampf(bg.r + s * 1.5, 0.0, 1.0),
		clampf(bg.g + s * 0.5, 0.0, 1.0),
		clampf(bg.b + s * 3.0, 0.0, 1.0))
	var btn_hover := Color(
		clampf(bg.r + s * 3.0, 0.0, 1.0),
		clampf(bg.g + s * 1.5, 0.0, 1.0),
		clampf(bg.b + s * 6.0, 0.0, 1.0))
	var btn_pressed := Color(
		clampf(bg.r + s * 0.5, 0.0, 1.0),
		clampf(bg.g + s * 0.3, 0.0, 1.0),
		clampf(bg.b + s, 0.0, 1.0))

	# Cell tinting — bg + small fraction of the accent/secondary/error color.
	var t := 0.08
	var cell_sel := Color(
		clampf(bg.r + accent.r * t * 1.5, 0.0, 1.0),
		clampf(bg.g + accent.g * t * 1.5, 0.0, 1.0),
		clampf(bg.b + accent.b * t * 2.0, 0.0, 1.0))
	var cell_same := Color(
		clampf(bg.r + secondary.r * t, 0.0, 1.0),
		clampf(bg.g + secondary.g * t * 0.05, 0.0, 1.0),
		clampf(bg.b + secondary.b * t * 1.5, 0.0, 1.0))
	var cell_hi := Color(
		clampf(bg.r + secondary.r * t * 0.5, 0.0, 1.0),
		clampf(bg.g + secondary.g * t * 0.3, 0.0, 1.0),
		clampf(bg.b + secondary.b * t, 0.0, 1.0))
	var cell_err := Color(clampf(error.r * 0.25, 0.0, 1.0), clampf(error.g * 0.05, 0.0, 1.0), clampf(error.b * 0.1, 0.0, 1.0))

	# Thin grid: bg lightened with faint accent tint (clamped, not HDR)
	var grid_thin := Color(
		clampf(bg.r * 1.5 + accent.r * 0.05, 0.0, 1.0),
		clampf(bg.g * 1.5 + accent.g * 0.05, 0.0, 1.0),
		clampf(bg.b * 1.5 + accent.b * 0.05, 0.0, 1.0)
	)

	# Muted auto-derived versions at ~30% intensity
	var a30 := Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3)
	var s30 := Color(secondary.r * 0.25, secondary.g * 0.25, secondary.b * 0.25)
	var e30 := Color(error.r * 0.3, error.g * 0.3, error.b * 0.3)

	return {
		"background": bg,
		"cell_background": cell_bg,
		"cell_selected": cell_sel,
		"cell_highlighted": cell_hi,
		"cell_same_number": cell_same,
		"cell_error": cell_err,
		"cell_given": cell_given,
		"grid_line_thin": grid_thin,
		"grid_line_thick": accent,
		"text_given": accent,
		"text_placed": secondary,
		"text_error": error,
		"text_pencil": s30,
		"text_primary": accent,
		"text_secondary": secondary,
		"button_bg": btn_bg,
		"button_bg_hover": btn_hover,
		"button_bg_pressed": btn_pressed,
		"button_text": accent,
		"button_disabled": bg,
		"button_disabled_text": a30,
		"label_text": accent,
		"timer_text": secondary,
		"strike_active": error,
		"strike_inactive": e30,
	}


# ---------------------------------------------------------------------------
# Custom palette CRUD
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _apply_color_set(source: Dictionary) -> void:
	for key in source:
		_colors[key] = source[key]


static func _serialize_palette(name: String, bg: Color, accent: Color, secondary: Color, error: Color) -> Dictionary:
	return {
		"name": name,
		"bg": _color_to_array(bg),
		"accent": _color_to_array(accent),
		"secondary": _color_to_array(secondary),
		"error": _color_to_array(error),
	}


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
