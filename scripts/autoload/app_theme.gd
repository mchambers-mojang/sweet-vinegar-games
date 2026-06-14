extends Node

## Unified theme module. Owns the Godot Theme resource and icon set.
## Palette data model (color derivation, persistence, CRUD) is delegated to
## ThemePalette, which is owned here and exposed as `palette`.
## Exposes get_color(), get_icon(), apply_icon(), and the theme_changed signal.
## Icons are applied reactively via the node_added signal — no tree-scanning.

signal theme_changed(is_dark: bool)

var is_dark: bool = false
var is_neon: bool = false
var ui_theme: Theme

## ThemePalette instance — single owner of palette truth.
## ThemeEditorScreen and other callers may read this to use the ThemePalette API.
var palette: ThemePalette

## Mirror of palette._colors (same Dictionary reference).
## Kept here so _rebuild_ui_theme() and callers that use AppTheme.colors directly
## continue to work without modification.
var colors: Dictionary

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
	palette = ThemePalette.new()
	palette.load()
	# colors is a live reference to palette._colors; _rebuild_ui_theme() uses it directly.
	colors = palette._colors
	palette.palette_changed.connect(_on_palette_changed)
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
	palette.set_mode(PlatformSettings.dark_mode)


func _on_palette_changed() -> void:
	is_dark = palette.is_dark
	is_neon = palette.is_neon
	_rebuild_ui_theme()
	theme_changed.emit(is_dark)
	_retint_icon_buttons()


## Switch to the given named mode. Delegates to ThemePalette.set_mode() which
## updates colors and emits palette_changed (handled by _on_palette_changed).
func set_theme_mode(mode: String) -> void:
	palette.set_mode(mode)


func set_dark(dark: bool) -> void:
	set_theme_mode("dark" if dark else "light")


func get_color(key: String) -> Color:
	return palette.get_color(key)


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
