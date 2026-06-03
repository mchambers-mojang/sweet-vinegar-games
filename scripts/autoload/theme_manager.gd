extends Node

## Manages light/dark theme switching and applies a global Godot Theme

signal theme_changed(is_dark: bool)

var is_dark: bool = false
var ui_theme: Theme

## Theme colors
var colors := {
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

var _dark_colors := {
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

var _light_colors: Dictionary


func _ready() -> void:
	_light_colors = colors.duplicate()
	ui_theme = Theme.new()
	_apply_theme_setting()
	SettingsManager.settings_changed.connect(_apply_theme_setting)


func _apply_theme_setting() -> void:
	match SettingsManager.dark_mode:
		"system":
			set_dark(DisplayServer.is_dark_mode() if DisplayServer.has_method("is_dark_mode") else false)
		"dark":
			set_dark(true)
		"light":
			set_dark(false)


func set_dark(dark: bool) -> void:
	is_dark = dark
	if dark:
		for key in _dark_colors:
			colors[key] = _dark_colors[key]
	else:
		for key in _light_colors:
			colors[key] = _light_colors[key]
	_rebuild_ui_theme()
	theme_changed.emit(is_dark)


func _rebuild_ui_theme() -> void:
	# Button styles
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = colors["button_bg"]
	btn_normal.set_corner_radius_all(8)
	btn_normal.set_content_margin_all(10)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = colors["button_bg_hover"]
	btn_hover.set_corner_radius_all(8)
	btn_hover.set_content_margin_all(10)

	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = colors["button_bg_pressed"]
	btn_pressed.set_corner_radius_all(8)
	btn_pressed.set_content_margin_all(10)

	var btn_disabled := StyleBoxFlat.new()
	btn_disabled.bg_color = colors["button_disabled"]
	btn_disabled.set_corner_radius_all(8)
	btn_disabled.set_content_margin_all(10)

	ui_theme.set_stylebox("normal", "Button", btn_normal)
	ui_theme.set_stylebox("hover", "Button", btn_hover)
	ui_theme.set_stylebox("pressed", "Button", btn_pressed)
	ui_theme.set_stylebox("disabled", "Button", btn_disabled)
	ui_theme.set_color("font_color", "Button", colors["button_text"])
	ui_theme.set_color("font_hover_color", "Button", colors["button_text"])
	ui_theme.set_color("font_pressed_color", "Button", colors["button_text"])
	ui_theme.set_color("font_disabled_color", "Button", colors["button_disabled_text"])

	# Label colors
	ui_theme.set_color("font_color", "Label", colors["label_text"])

	# CheckButton
	ui_theme.set_color("font_color", "CheckButton", colors["label_text"])

	# OptionButton
	var opt_normal := btn_normal.duplicate()
	ui_theme.set_stylebox("normal", "OptionButton", opt_normal)
	ui_theme.set_stylebox("hover", "OptionButton", btn_hover.duplicate())
	ui_theme.set_stylebox("pressed", "OptionButton", btn_pressed.duplicate())
	ui_theme.set_color("font_color", "OptionButton", colors["button_text"])
	ui_theme.set_color("font_hover_color", "OptionButton", colors["button_text"])

	# PanelContainer background
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = colors["background"]
	ui_theme.set_stylebox("panel", "PanelContainer", panel_style)

	# HSeparator
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = colors["grid_line_thin"]
	sep_style.set_content_margin_all(0)
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	ui_theme.set_stylebox("separator", "HSeparator", sep_style)

	# Apply to the scene tree root so it cascades to all controls
	if get_tree() and get_tree().root:
		get_tree().root.theme = ui_theme


func get_color(key: String) -> Color:
	return colors.get(key, Color.MAGENTA)
