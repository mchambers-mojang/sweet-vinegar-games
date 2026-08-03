extends GameMenu

## Eclipse Grid main menu — config-driven via assets/menu/eclipse_grid_menu.tres

func _init() -> void:
	config = preload("res://assets/menu/eclipse_grid_menu.tres")


func _get_save_adapter() -> GameSaveAdapter:
	return EclipseGridSaveAdapter.new()
