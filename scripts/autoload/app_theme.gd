extends Node

## Unified theme module. Owns color palettes, icon set, and Godot Theme resource.
## Exposes get_color(), get_icon(), apply_icon(), and the theme_changed signal.
## Icons are applied reactively via the node_added signal — no tree-scanning.

signal theme_changed(is_dark: bool)

var is_dark: bool = false
var is_neon: bool = false
var ui_theme: Theme

var _glow_layer: CanvasLayer
var _world_env: WorldEnvironment
var _environment: Environment

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
	_setup_glow()


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
			var pal: Dictionary = PlatformSettings.get_active_custom_palette()
			if not pal.is_empty():
				_apply_color_set(build_custom_palette(pal["bg"], pal["accent"], pal["secondary"], pal["error"]))
			else:
				_apply_color_set(_neon_colors)
	_rebuild_ui_theme()
	theme_changed.emit(is_dark)
	_retint_icon_buttons()
	_update_glow()


## Derives a full 22-key color palette from 4 user-chosen base colors.
## Intended for use with the "custom" neon-style theme mode.
## [b]accent[/b], [b]secondary[/b], and [b]error[/b] may carry HDR values (>1.0)
## to drive neon bloom; derived surface/cell colors are clamped to [0, 1] so they
## display correctly on non-HDR render targets.
static func build_custom_palette(bg: Color, accent: Color, secondary: Color, error: Color) -> Dictionary:
	# Background variants — slight brightness offsets to keep the dark neon feel.
	# Clamped to [0,1] because these are standard (non-HDR) surface colors.
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
	# Accent/secondary may be HDR (>1.0), so the blended result must be clamped
	# to [0,1] for cell backgrounds which are not bloom-rendered.
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


func _apply_color_set(source: Dictionary) -> void:
	for key in source:
		colors[key] = source[key]


func _setup_glow() -> void:
	_glow_layer = CanvasLayer.new()
	_glow_layer.layer = -1
	add_child(_glow_layer)

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_CANVAS
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES

	# Glow settings for synthwave neon bloom
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.7
	_environment.glow_strength = 1.05
	_environment.glow_bloom = 0.25
	_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_environment.glow_hdr_threshold = 0.8
	_environment.glow_hdr_scale = 2.0
	# Multi-level glow for soft, wide bloom
	_environment.set_glow_level(0, true)   # Fine detail
	_environment.set_glow_level(1, true)   # Medium spread
	_environment.set_glow_level(2, true)   # Wide glow
	_environment.set_glow_level(3, false)
	_environment.set_glow_level(4, false)
	_environment.set_glow_level(5, false)
	_environment.set_glow_level(6, false)

	_world_env = WorldEnvironment.new()
	_world_env.environment = _environment
	# Don't add to tree unless neon is active — saves ~20-40MB on mobile
	_update_glow()


func _update_glow() -> void:
	if _glow_layer == null:
		return
	if is_neon:
		if not _world_env.is_inside_tree():
			_glow_layer.add_child(_world_env)
	else:
		if _world_env.is_inside_tree():
			_glow_layer.remove_child(_world_env)


## Create a screen-shake / impact effect
func screen_shake(intensity: float = 4.0, duration: float = 0.15) -> void:
	if not is_neon:
		return
	if not PlatformSettings.screen_shake_enabled:
		return
	var viewport := get_viewport()
	if not viewport:
		return
	var original := viewport.canvas_transform
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		var shake := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity)) * (1.0 - t)
		viewport.canvas_transform = Transform2D(0, shake) * original
	, 0.0, 1.0, duration)
	tween.tween_callback(func() -> void:
		viewport.canvas_transform = original
	)


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

	# PopupPanel (used by ColorPickerButton)
	var popup_panel_style := StyleBoxFlat.new()
	popup_panel_style.bg_color = colors["button_bg"]
	popup_panel_style.set_corner_radius_all(6)
	popup_panel_style.set_content_margin_all(8)
	if is_neon:
		popup_panel_style.border_color = Color(0.0, 0.8, 0.8, 0.6)
		popup_panel_style.set_border_width_all(1)
	ui_theme.set_stylebox("panel", "PopupPanel", popup_panel_style)

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
