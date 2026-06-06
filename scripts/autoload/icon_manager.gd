extends Node

## Preloads SVG icons and provides them for button setup.
## Automatically applies icons to buttons with emoji text when scenes load.

var _icons: Dictionary = {}

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


func _on_node_added(node: Node) -> void:
	if node is Button:
		_try_apply_icon(node as Button)


func _try_apply_icon(button: Button) -> void:
	var text := button.text.strip_edges()
	if text in TEXT_TO_ICON:
		apply_icon(button, TEXT_TO_ICON[text])
	elif text == "Replays":
		apply_icon(button, "replays", true)


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
		else:
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
