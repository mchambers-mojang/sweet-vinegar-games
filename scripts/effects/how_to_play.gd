class_name HowToPlay
extends Node

## Shows a "How to Play" dialog for each game mode.
## Usage: HowToPlay.show_for(parent, game_mode)

const HELP_DIR := "res://assets/help/"


static func _load_help(game_mode: String) -> HelpContent:
	var path := HELP_DIR + game_mode + "_help.tres"
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as HelpContent


static func show_for(parent: Node, game_mode: String) -> void:
	var content := _load_help(game_mode)
	if content == null or content.body.is_empty():
		return
	var text: String = content.body

	var dialog := AcceptDialog.new()
	dialog.title = "How to Play"
	dialog.ok_button_text = "Got it"

	# Use a custom label with proper wrapping
	dialog.dialog_text = ""
	var label := dialog.get_label()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(280, 0)

	dialog.min_size = Vector2i(320, 0)
	dialog.max_size = Vector2i(360, 600)
	parent.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void: dialog.queue_free())
