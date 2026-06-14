extends Node

## Unified theme module. Owns color palettes, icon set, and Godot Theme resource.
## Exposes get_color(), get_icon(), apply_icon(), and the theme_changed signal.
## Icons are applied reactively via the node_added signal — no tree-scanning.

signal theme_changed(is_dark: bool)

var is_dark: bool = false
var is_neon: bool = false
var ui_theme: Theme

## Active color palette (current theme values)
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

var _neon_colors := {
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

var _custom_colors: Dictionary = {}

# --- Icon state ---

var _icons: Dictionary = {}
var _icon_buttons: Array[Button] = []

const ICON_PATHS := {
	"back": "res://assets/icons/back.svg",
	"undo": "res://assets/icons/undo.svg",
	"redo": "res://assets/icons/redo.svg",
	"settings": "res://assets/icons/settings.svg",
	"play": "res://assets/icons/play.svg",
	"pause": "res://assets/icons/pause.svg",
	"replays": "res://assets/icons/replays.svg",
	"replays_small": "res://assets/icons/replays_small.svg",
}

# Map from emoji text to icon name
const TEXT_TO_ICON := {
	"←": "back",
	"↺": "undo",
	"↻": "redo",
	"⚙": "settings",
	"▶": "play",
	"⏸": "pause",
}


func _ready() -> void:
	_light_colors = colors.duplicate()
	ui_theme = Theme.new()
	_apply_theme_setting()
	PlatformSettings.settings_changed.connect(_apply_theme_setting)

	for key in ICON_PATHS:
		var tex := load(ICON_PATHS[key]) as Texture2D
		if tex:
			_icons[key] = tex
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	# Scan buttons already in the tree (main scene loads before node_added connects)
	call_deferred("_scan_existing_buttons")


func _apply_theme_setting() -> void:
	match PlatformSettings.dark_mode:
		"system":
			set_theme_mode("system")
		"dark":
			set_theme_mode("dark")
		"light":
			set_theme_mode("light")
		"neon":
			set_theme_mode("neon")
		"custom":
			set_theme_mode("custom")


func set_theme_mode(mode: String) -> void:
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
			_custom_colors = _build_custom_palette(
				PlatformSettings.custom_palette_bg,
				PlatformSettings.custom_palette_accent,
				PlatformSettings.custom_palette_secondary,
				PlatformSettings.custom_palette_error
			)
			_apply_color_set(_custom_colors)
	_rebuild_ui_theme()
	theme_changed.emit(is_dark)
	_retint_icon_buttons()


func _apply_color_set(source: Dictionary) -> void:
	for key in source:
		colors[key] = source[key]


func _build_custom_palette(bg: Color, accent: Color, secondary: Color, error: Color) -> Dictionary:
	var p := {}

	# Background group — slight value shifts
	p["background"] = bg
	p["cell_background"] = Color(bg.r + 0.02, bg.g + 0.02, bg.b + 0.04)
	p["cell_given"] = Color(bg.r + 0.04, bg.g + 0.04, bg.b + 0.08)
	p["button_bg"] = Color(bg.r + 0.04, bg.g + 0.02, bg.b + 0.08)
	p["button_bg_hover"] = Color(bg.r + 0.08, bg.g + 0.04, bg.b + 0.18)
	p["button_bg_pressed"] = Color(bg.r + 0.02, bg.g + 0.0, bg.b + 0.04)
	p["button_disabled"] = Color(bg.r + 0.04, bg.g + 0.02, bg.b + 0.04)

	# Accent group — full intensity + cell tints
	p["grid_line_thick"] = accent
	p["text_given"] = accent
	p["button_text"] = accent
	p["label_text"] = accent
	p["cell_selected"] = Color(bg.r + accent.r * 0.08, bg.g + accent.g * 0.08, bg.b + accent.b * 0.08)
	p["cell_same_number"] = Color(bg.r + accent.r * 0.05, bg.g + accent.g * 0.05, bg.b + accent.b * 0.05)

	# Secondary group — full intensity + cell tint
	p["text_placed"] = secondary
	p["timer_text"] = secondary
	p["cell_highlighted"] = Color(bg.r + secondary.r * 0.05, bg.g + secondary.g * 0.05, bg.b + secondary.b * 0.05)

	# Error group — full intensity + cell tint
	p["text_error"] = error
	p["strike_active"] = error
	p["cell_error"] = Color(bg.r + error.r * 0.15, bg.g + error.g * 0.02, bg.b + error.b * 0.02)

	# Auto-derived (~15–25% intensity of parent group)
	p["grid_line_thin"] = Color(accent.r * 0.15, accent.g * 0.15, accent.b * 0.15)
	p["text_pencil"] = Color(secondary.r * 0.15, secondary.g * 0.15, secondary.b * 0.15)
	p["button_disabled_text"] = Color(accent.r * 0.25, accent.g * 0.25, accent.b * 0.25)
	p["strike_inactive"] = Color(error.r * 0.15, error.g * 0.15, error.b * 0.15)

	return p


func set_dark(dark: bool) -> void:
	set_theme_mode("dark" if dark else "light")


func get_color(key: String) -> Color:
	return colors.get(key, Color.MAGENTA)


func get_theme_resource() -> Theme:
	return ui_theme


func _rebuild_ui_theme() -> void:
	# Button styles
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = colors["button_bg"]
	btn_normal.set_corner_radius_all(8)
	btn_normal.set_content_margin_all(10)
	if is_neon:
		btn_normal.border_color = Color(0.0, 0.8, 0.8, 0.5)
		btn_normal.set_border_width_all(1)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = colors["button_bg_hover"]
	btn_hover.set_corner_radius_all(8)
	btn_hover.set_content_margin_all(10)
	if is_neon:
		btn_hover.border_color = Color(0.0, 1.2, 1.2, 0.8)
		btn_hover.set_border_width_all(2)

	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = colors["button_bg_pressed"]
	btn_pressed.set_corner_radius_all(8)
	btn_pressed.set_content_margin_all(10)
	if is_neon:
		btn_pressed.border_color = Color(1.5, 0.2, 1.0, 0.8)
		btn_pressed.set_border_width_all(2)

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

	# CheckButton state styles — fix focus/hover outlines for neon consistency
	var check_normal := StyleBoxFlat.new()
	check_normal.bg_color = Color.TRANSPARENT
	check_normal.set_corner_radius_all(4)
	check_normal.set_content_margin_all(4)
	if is_neon:
		check_normal.border_color = Color(0.0, 0.8, 0.8, 0.4)
		check_normal.set_border_width_all(1)

	var check_hover := StyleBoxFlat.new()
	check_hover.bg_color = Color.TRANSPARENT
	check_hover.set_corner_radius_all(4)
	check_hover.set_content_margin_all(4)
	if is_neon:
		check_hover.border_color = Color(0.0, 1.0, 1.0, 0.6)
		check_hover.set_border_width_all(1)

	var check_pressed := StyleBoxFlat.new()
	check_pressed.bg_color = Color.TRANSPARENT
	check_pressed.set_corner_radius_all(4)
	check_pressed.set_content_margin_all(4)
	if is_neon:
		check_pressed.border_color = Color(1.5, 0.2, 1.0, 0.8)
		check_pressed.set_border_width_all(1)

	var check_focus := StyleBoxEmpty.new()

	ui_theme.set_stylebox("normal", "CheckButton", check_normal)
	ui_theme.set_stylebox("hover", "CheckButton", check_hover)
	ui_theme.set_stylebox("pressed", "CheckButton", check_pressed)
	ui_theme.set_stylebox("hover_pressed", "CheckButton", check_pressed.duplicate())
	ui_theme.set_stylebox("focus", "CheckButton", check_focus)

	# OptionButton
	var opt_normal := btn_normal.duplicate()
	ui_theme.set_stylebox("normal", "OptionButton", opt_normal)
	ui_theme.set_stylebox("hover", "OptionButton", btn_hover.duplicate())
	ui_theme.set_stylebox("pressed", "OptionButton", btn_pressed.duplicate())
	ui_theme.set_color("font_color", "OptionButton", colors["button_text"])
	ui_theme.set_color("font_hover_color", "OptionButton", colors["button_text"])

	# PopupMenu (dropdown list for OptionButton)
	var popup_panel := StyleBoxFlat.new()
	popup_panel.bg_color = colors["button_bg"]
	popup_panel.set_corner_radius_all(6)
	popup_panel.set_content_margin_all(4)
	if is_neon:
		popup_panel.border_color = Color(0.0, 0.8, 0.8, 0.6)
		popup_panel.set_border_width_all(1)
	ui_theme.set_stylebox("panel", "PopupMenu", popup_panel)

	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = colors["button_bg_hover"]
	popup_hover.set_corner_radius_all(4)
	ui_theme.set_stylebox("hover", "PopupMenu", popup_hover)

	ui_theme.set_color("font_color", "PopupMenu", colors["button_text"])
	ui_theme.set_color("font_hover_color", "PopupMenu", colors["button_text"])

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


# --- Icon API ---

func get_icon(icon_name: String) -> Texture2D:
	return _icons.get(icon_name, null)


func apply_icon(button: Button, icon_name: String, show_text: bool = false) -> void:
	var tex := get_icon(icon_name)
	if tex:
		button.icon = tex
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if not show_text:
			button.text = ""
			if button.custom_minimum_size.x < 48:
				button.custom_minimum_size.x = 48
			if button.custom_minimum_size.y < 44:
				button.custom_minimum_size.y = 44
		else:
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT

		# Tint icon to match theme
		var color := get_color("button_text")
		button.add_theme_color_override("icon_normal_color", color)
		button.add_theme_color_override("icon_hover_color", color)
		button.add_theme_color_override("icon_pressed_color", color)

		if button not in _icon_buttons:
			_icon_buttons.append(button)


# --- Reactive icon application (push model via node_added signal) ---

func _scan_existing_buttons() -> void:
	var root := get_tree().root
	if root:
		_scan_node_recursive(root)


func _scan_node_recursive(node: Node) -> void:
	if node is Button:
		_try_apply_icon(node as Button)
	for child in node.get_children():
		_scan_node_recursive(child)


func _on_node_added(node: Node) -> void:
	if node is Button:
		_try_apply_icon(node as Button)


func _on_node_removed(node: Node) -> void:
	if node is Button:
		_icon_buttons.erase(node as Button)


func _try_apply_icon(button: Button) -> void:
	var text := button.text.strip_edges()
	if text in TEXT_TO_ICON:
		apply_icon(button, TEXT_TO_ICON[text])
	elif text == "Replays":
		# Create icon+text as a centered child layout instead of using Button.icon
		button.text = ""
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var hbox := HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", 6)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var tex_rect := TextureRect.new()
		tex_rect.texture = get_icon("replays_small")
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(20, 20)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var color := get_color("button_text")
		tex_rect.modulate = color
		hbox.add_child(tex_rect)
		var lbl := Label.new()
		lbl.text = "Replays"
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(lbl)
		button.add_child(hbox)
		# Track for theme changes
		button.set_meta("_icon_tex_rect", tex_rect)
		if button not in _icon_buttons:
			_icon_buttons.append(button)


func _retint_icon_buttons() -> void:
	var color := get_color("button_text")
	for btn in _icon_buttons:
		if is_instance_valid(btn):
			btn.add_theme_color_override("icon_normal_color", color)
			btn.add_theme_color_override("icon_hover_color", color)
			btn.add_theme_color_override("icon_pressed_color", color)
			if btn.has_meta("_icon_tex_rect"):
				var tex_rect = btn.get_meta("_icon_tex_rect")
				if is_instance_valid(tex_rect):
					tex_rect.modulate = color
