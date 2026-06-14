extends GameMenu

## Shikaku main menu — config-driven via assets/menu/shikaku_menu.tres
##
## All ceremony (size dropdown, start/resume, abandon stats) is handled by
## GameMenu using the MenuConfig resource.  No override needed.

func _init() -> void:
	config = preload("res://assets/menu/shikaku_menu.tres")
