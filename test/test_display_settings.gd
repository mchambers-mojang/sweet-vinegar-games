extends GutTest

## Unit tests for DisplaySettings — validation and persistence.

const DisplaySettingsScript := preload("res://scripts/settings/display_settings.gd")


func _make_display() -> DisplaySettings:
	return DisplaySettingsScript.new()


# --- Default values ---

func test_default_dark_mode_is_neon() -> void:
	var d := _make_display()
	assert_eq(d.dark_mode, "neon")


func test_default_show_timer_is_true() -> void:
	var d := _make_display()
	assert_true(d.show_timer)


# --- dark_mode validation ---

func test_valid_dark_modes_accepted() -> void:
	var d := _make_display()
	for mode in DisplaySettings.VALID_DARK_MODES:
		d.dark_mode = mode
		assert_eq(d.dark_mode, mode, "Expected '%s' to be accepted" % mode)


func test_invalid_dark_mode_rejected() -> void:
	var d := _make_display()
	d.dark_mode = "neon"
	d.dark_mode = "garbage"
	assert_eq(d.dark_mode, "neon", "Invalid value should be ignored")


func test_empty_dark_mode_rejected() -> void:
	var d := _make_display()
	d.dark_mode = "light"
	d.dark_mode = ""
	assert_eq(d.dark_mode, "light", "Empty string should be ignored")


# --- changed signal ---

func test_setting_valid_dark_mode_emits_changed() -> void:
	var d := _make_display()
	watch_signals(d)
	d.dark_mode = "dark"
	assert_signal_emitted(d, "changed")


func test_setting_invalid_dark_mode_does_not_emit_changed() -> void:
	var d := _make_display()
	watch_signals(d)
	d.dark_mode = "bad_value"
	assert_signal_not_emitted(d, "changed")


func test_setting_show_timer_emits_changed() -> void:
	var d := _make_display()
	watch_signals(d)
	d.show_timer = false
	assert_signal_emitted(d, "changed")


# --- save / load round-trip ---

func test_save_load_dark_mode() -> void:
	var d := _make_display()
	d.dark_mode = "light"
	var config := ConfigFile.new()
	d.save(config)

	var d2 := _make_display()
	d2.load_from(config)
	assert_eq(d2.dark_mode, "light")


func test_save_load_show_timer_false() -> void:
	var d := _make_display()
	d.show_timer = false
	var config := ConfigFile.new()
	d.save(config)

	var d2 := _make_display()
	d2.load_from(config)
	assert_false(d2.show_timer)


func test_save_load_all_valid_modes() -> void:
	for mode in DisplaySettings.VALID_DARK_MODES:
		var d := _make_display()
		d.dark_mode = mode
		var config := ConfigFile.new()
		d.save(config)

		var d2 := _make_display()
		d2.load_from(config)
		assert_eq(d2.dark_mode, mode, "Round-trip failed for mode '%s'" % mode)


func test_load_from_missing_keys_uses_defaults() -> void:
	var config := ConfigFile.new()
	# No keys set — defaults should be preserved
	var d := _make_display()
	d.load_from(config)
	assert_eq(d.dark_mode, "neon")
	assert_true(d.show_timer)
