extends GutTest

const ArenaScene := preload("res://carom/scenes/carom_arena.tscn")
const _SETTINGS_PATH := "user://carom_settings.cfg"


func after_each() -> void:
	if FileAccess.file_exists(_SETTINGS_PATH):
		DirAccess.remove_absolute(_SETTINGS_PATH)
	CaromSettings._loaded = false
	CaromSettings.aim_mode = CaromSettings.AimMode.DRAG
	CaromSettings.reload_button_side = CaromSettings.ReloadButtonSide.RIGHT
	CaromSettings.camera_mode = "top_down"


func test_camera_mode_persists_in_carom_settings() -> void:
	CaromSettings._loaded = true
	CaromSettings.camera_mode = "isometric"
	CaromSettings.save()

	CaromSettings.camera_mode = "top_down"
	CaromSettings._loaded = false
	CaromSettings.ensure_loaded()

	assert_eq(CaromSettings.camera_mode, "isometric")


func test_arena_applies_camera_modes_without_animation() -> void:
	CaromSettings._loaded = true
	CaromSettings.camera_mode = "top_down"
	var arena := ArenaScene.instantiate() as CaromArena
	add_child_autofree(arena)

	var camera := arena.get_node("Camera3D") as Camera3D
	assert_not_null(camera)

	arena.set_camera_mode("isometric", false)
	assert_eq(camera.position, CaromArena.ISOMETRIC_POSITION)
	assert_eq(camera.rotation_degrees, CaromArena.ISOMETRIC_ROTATION)

	arena.set_camera_mode("top_down", false)
	assert_eq(camera.position, CaromArena.TOP_DOWN_POSITION)
	assert_eq(camera.rotation_degrees, CaromArena.TOP_DOWN_ROTATION)

