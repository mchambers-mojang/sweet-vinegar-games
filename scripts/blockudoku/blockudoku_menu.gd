extends GameMenu

## Blockudoku main menu — config-driven via assets/menu/blockudoku_menu.tres
##
## All ceremony (start/resume, game rules registration) is handled by GameMenu
## using the MenuConfig resource.  No override needed.

func _init() -> void:
	config = preload("res://assets/menu/blockudoku_menu.tres")

