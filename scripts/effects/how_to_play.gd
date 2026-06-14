class_name HowToPlay
extends Node

## Shows a "How to Play" dialog for each game mode.
## Usage: HowToPlay.show_for(parent, game_mode)

const HELP_TEXT := {
	"sudoku": "Fill the 9×9 grid so every row, column, and 3×3 box contains the digits 1–9 exactly once.\n\n• Tap a cell, then tap a number to place it\n• Use Notes mode to mark possible candidates\n• In Strict mode, 3 wrong answers ends the game\n• Double-tap a cell to highlight its row/column/box",
	"shikaku": "Divide the grid into rectangles so each rectangle contains exactly one number, and that number equals the rectangle's area.\n\n• Drag to draw a rectangle\n• Tap an existing rectangle to remove it\n• Every cell must be covered by exactly one rectangle\n• Use Hint if you get stuck",
	"blockudoku": "Place blocks on the 9×9 grid to fill complete rows, columns, or 3×3 boxes — filled lines are cleared for points.\n\n• Drag blocks from the tray onto the grid\n• Clear multiple lines at once for bonus points\n• Build combos by clearing on consecutive turns\n• Game ends when no remaining block fits",
	"carom": "Aim your mounted turret and ricochet projectiles into the opponent's goal.\n\n• Left/Right arrow keys to aim your turret\n• Enter or click to fire\n• R to reload (bullets load slowly over time)\n• On mobile: drag to aim (Drag mode), or use Hold Zones / Gyroscope — change aim mode in ⚙ Settings\n• On mobile: tap screen to fire; tap reload button (bottom corner) to reload\n• Ammo returns when projectiles reach a goal area\n• Puck has irregular contact points — momentum is unpredictable",
}


static func show_for(parent: Node, game_mode: String) -> void:
	var text: String = HELP_TEXT.get(game_mode, "")
	if text == "":
		return

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
