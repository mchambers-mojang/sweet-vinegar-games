extends GutTest

const GamePickerScript := preload("res://scripts/game_picker.gd")
const GameEntryScript := preload("res://scripts/menu/game_entry.gd")

var picker: Control
var _secret_entry: GameEntry
var _secret_button: Button


func before_each() -> void:
	picker = GamePickerScript.new()
	# Simulate a secret_tap entry wired up as _build_game_buttons() would do.
	_secret_entry = GameEntryScript.new()
	_secret_entry.id = "test_secret"
	_secret_entry.unlock_rule = "secret_tap"
	_secret_entry.tap_mouse_count = 5
	_secret_entry.tap_mouse_window_sec = 1.0
	_secret_entry.tap_touch_count = 7
	_secret_entry.tap_touch_window_sec = 0.6
	_secret_button = Button.new()
	_secret_button.visible = false
	picker._game_buttons[_secret_entry.id] = _secret_button
	picker._mouse_taps[_secret_entry.id] = []
	picker._touch_taps[_secret_entry.id] = []


func after_each() -> void:
	if is_instance_valid(_secret_button):
		_secret_button.free()
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


func test_register_secret_tap_reveals_after_rapid_touch_taps() -> void:
	for tap_index in 7:
		picker._register_secret_tap(_secret_entry, float(tap_index) * 0.08, true)

	assert_true(_secret_button.visible)
	assert_eq(picker._touch_taps[_secret_entry.id].size(), 0)


func test_register_secret_tap_expires_old_touch_taps() -> void:
	for tap_index in 7:
		picker._register_secret_tap(_secret_entry, float(tap_index), true)

	assert_false(_secret_button.visible)


func test_register_secret_tap_reveals_after_rapid_mouse_clicks() -> void:
	for tap_index in 5:
		picker._register_secret_tap(_secret_entry, float(tap_index) * 0.18, false)

	assert_true(_secret_button.visible)
	assert_eq(picker._mouse_taps[_secret_entry.id].size(), 0)


func test_register_secret_tap_expires_old_mouse_taps() -> void:
	for tap_index in 5:
		picker._register_secret_tap(_secret_entry, float(tap_index) * 2.0, false)

	assert_false(_secret_button.visible)


func test_game_registry_entries_are_not_empty() -> void:
	assert_true(GameRegistry.ENTRIES.size() > 0)


func test_game_registry_carom_entry_has_secret_tap_unlock() -> void:
	var carom_entry: GameEntry = null
	for entry: GameEntry in GameRegistry.ENTRIES:
		if entry.id == "carom":
			carom_entry = entry
			break
	assert_not_null(carom_entry, "Carom entry not found in GameRegistry")
	assert_eq(carom_entry.unlock_rule, "secret_tap")


func test_game_registry_non_carom_entries_have_no_unlock_rule() -> void:
	for entry: GameEntry in GameRegistry.ENTRIES:
		if entry.id != "carom":
			assert_eq(entry.unlock_rule, "", "Entry %s should have no unlock rule" % entry.id)

