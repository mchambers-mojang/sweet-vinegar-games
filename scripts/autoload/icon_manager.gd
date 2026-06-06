extends Node

## Preloads SVG icons and provides them for button setup.
## Automatically applies icons to buttons with emoji text when scenes load.
## Icons are white SVGs tinted to match the current theme.

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
	for key in ICON_PATHS:
		var tex := load(ICON_PATHS[key]) as Texture2D
		if tex:
			_icons[key] = tex
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	ThemeManager.theme_changed.connect(_on_theme_changed)
	# Apply icons to buttons already in the tree (initial scene)
	call_deferred("_scan_existing_buttons")


func _on_node_added(node: Node) -> void:
	if node is Button:
		_try_apply_icon(node as Button)


func _scan_existing_buttons() -> void:
	_scan_node(get_tree().root)


func _scan_node(node: Node) -> void:
	if node is Button:
		_try_apply_icon(node as Button)
	for child in node.get_children():
		_scan_node(child)


func _on_node_removed(node: Node) -> void:
	if node is Button:
		_icon_buttons.erase(node as Button)


func _on_theme_changed(_dark: bool) -> void:
	var color := ThemeManager.get_color("button_text")
	for btn in _icon_buttons:
		if is_instance_valid(btn):
			btn.add_theme_color_override("icon_normal_color", color)
			btn.add_theme_color_override("icon_hover_color", color)
			btn.add_theme_color_override("icon_pressed_color", color)


func _try_apply_icon(button: Button) -> void:
	var text := button.text.strip_edges()
	if text in TEXT_TO_ICON:
		apply_icon(button, TEXT_TO_ICON[text])
	elif text == "Replays":
		apply_icon(button, "replays", true)
		button.expand_icon = false


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
		var color := ThemeManager.get_color("button_text")
		button.add_theme_color_override("icon_normal_color", color)
		button.add_theme_color_override("icon_hover_color", color)
		button.add_theme_color_override("icon_pressed_color", color)

		if button not in _icon_buttons:
			_icon_buttons.append(button)
