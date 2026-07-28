extends GameMenu

## Number Path main menu — config-driven via assets/menu/number_path_menu.tres

func _init() -> void:
	config = preload("res://assets/menu/number_path_menu.tres")


func _get_save_adapter() -> GameSaveAdapter:
	return NumberPathSaveAdapter.new()
