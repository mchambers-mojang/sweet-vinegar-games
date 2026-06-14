extends GameMenu

## Sudoku main menu — config-driven via assets/menu/sudoku_menu.tres
##
## All ceremony (difficulty dropdown, start/resume, abandon stats, title colour)
## is handled by GameMenu using the MenuConfig resource.  No override needed.

func _init() -> void:
	config = preload("res://assets/menu/sudoku_menu.tres")
