class_name CaromMenu
extends GameMenu

## Carom menu — config-driven via assets/menu/carom_menu.tres
##
## Carom has no save support and uses a PlayButton instead of NewGameButton.
## It passes difficulty via set_meta("carom_difficulty", …) instead of a
## start_new_game() method.  All of this is expressed in the MenuConfig resource.

func _init() -> void:
	config = preload("res://assets/menu/carom_menu.tres")

