extends GutTest

## Unit tests for DisplaySettings — validation and persistence.
## Theme mode (dark_mode) was moved to ThemePalette; see test_theme_palette.gd.

const DisplaySettingsScript := preload("res://scripts/settings/display_settings.gd")


func _make_display() -> DisplaySettings:
	return DisplaySettingsScript.new()


# --- Default values ---

func test_default_show_timer_is_true() -> void:
	var d := _make_display()
	assert_true(d.show_timer)


# --- changed signal ---

func test_setting_show_timer_emits_changed() -> void:
	var d := _make_display()
	watch_signals(d)
	d.show_timer = false
	assert_signal_emitted(d, "changed")


# --- save / load round-trip ---

func test_save_load_show_timer_false() -> void:
	var d := _make_display()
	d.show_timer = false
	var config := ConfigFile.new()
	d.save(config)

	var d2 := _make_display()
	d2.load_from(config)
	assert_false(d2.show_timer)


func test_load_from_missing_keys_uses_defaults() -> void:
	var config := ConfigFile.new()
	# No keys set — defaults should be preserved
	var d := _make_display()
	d.load_from(config)
	assert_true(d.show_timer)
