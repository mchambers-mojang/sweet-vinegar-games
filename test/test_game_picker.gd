extends GutTest

const GamePickerScript := preload("res://scripts/game_picker.gd")

var picker: Control


func before_each() -> void:
	picker = GamePickerScript.new()
	picker.carom_button = Button.new()
	picker.carom_button.visible = false


func after_each() -> void:
	if is_instance_valid(picker.carom_button):
		picker.carom_button.free()
	if is_instance_valid(picker):
		picker.free()


func test_is_title_tap_release_handles_mouse_and_touch() -> void:
	var mouse_press := InputEventMouseButton.new()
	mouse_press.button_index = MOUSE_BUTTON_LEFT
	mouse_press.pressed = true
	assert_false(picker._is_title_tap_release(mouse_press))

	var mouse_release := InputEventMouseButton.new()
	mouse_release.button_index = MOUSE_BUTTON_LEFT
	mouse_release.pressed = false
	assert_true(picker._is_title_tap_release(mouse_release))

	var touch_release := InputEventScreenTouch.new()
	touch_release.pressed = false
	assert_true(picker._is_title_tap_release(touch_release))


func test_register_carom_unlock_tap_reveals_after_7_rapid_taps() -> void:
	for tap_index in 7:
		picker._register_carom_unlock_tap(float(tap_index) * 0.08, true)

	assert_true(picker.carom_button.visible)
	assert_eq(picker._carom_touch_taps.size(), 0)


func test_register_carom_unlock_tap_expires_old_taps() -> void:
	for tap_index in 7:
		picker._register_carom_unlock_tap(float(tap_index), true)

	assert_false(picker.carom_button.visible)
