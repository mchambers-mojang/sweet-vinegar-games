extends GameMenu
class_name CrownGridMenu

## Crown Grid main menu — config-driven via assets/menu/crown_grid_menu.tres

func _init() -> void:
	config = preload("res://assets/menu/crown_grid_menu.tres")


func _get_save_adapter() -> GameSaveAdapter:
	return CrownGridSaveAdapter.new()
