extends GutTest

## Unit tests for PlatformSettings — defaults, validation, and persistence.

const PlatformSettingsScript := preload("res://scripts/autoload/platform_settings.gd")


func _make_settings() -> PlatformSettingsScript:
	return PlatformSettingsScript.new()


# --- Default values ---

func test_default_dark_mode_is_neon() -> void:
	var s := _make_settings()
	assert_eq(s.dark_mode, "neon")


func test_default_show_timer_is_true() -> void:
	var s := _make_settings()
	assert_true(s.show_timer)


func test_default_sound_enabled_is_false() -> void:
	var s := _make_settings()
	assert_false(s.sound_enabled)


func test_default_haptic_enabled_is_true() -> void:
	var s := _make_settings()
	assert_true(s.haptic_enabled)


func test_default_screen_shake_enabled_is_true() -> void:
	var s := _make_settings()
	assert_true(s.screen_shake_enabled)


func test_default_shockwave_enabled_is_true() -> void:
	var s := _make_settings()
	assert_true(s.shockwave_enabled)


func test_default_particle_effects_enabled_is_true() -> void:
	var s := _make_settings()
	assert_true(s.particle_effects_enabled)


# --- dark_mode validation ---

func test_valid_dark_modes_accepted() -> void:
	var s := _make_settings()
	for mode in PlatformSettingsScript.VALID_DARK_MODES:
		s.dark_mode = mode
		assert_eq(s.dark_mode, mode, "Expected '%s' to be accepted" % mode)


func test_invalid_dark_mode_rejected() -> void:
	var s := _make_settings()
	s.dark_mode = "neon"
	s.dark_mode = "garbage"
	assert_eq(s.dark_mode, "neon", "Invalid value should be ignored")


func test_empty_dark_mode_rejected() -> void:
	var s := _make_settings()
	s.dark_mode = "light"
	s.dark_mode = ""
	assert_eq(s.dark_mode, "light", "Empty string should be ignored")


# --- save / load round-trip ---

func test_save_load_dark_mode() -> void:
	var s := _make_settings()
	s.dark_mode = "light"
	var config := ConfigFile.new()
	s._save_to_config(config)

	var s2 := _make_settings()
	s2._load_from_config(config)
	assert_eq(s2.dark_mode, "light")


func test_save_load_show_timer_false() -> void:
	var s := _make_settings()
	s.show_timer = false
	var config := ConfigFile.new()
	s._save_to_config(config)

	var s2 := _make_settings()
	s2._load_from_config(config)
	assert_false(s2.show_timer)


func test_save_load_all_valid_dark_modes() -> void:
	for mode in PlatformSettingsScript.VALID_DARK_MODES:
		var s := _make_settings()
		s.dark_mode = mode
		var config := ConfigFile.new()
		s._save_to_config(config)

		var s2 := _make_settings()
		s2._load_from_config(config)
		assert_eq(s2.dark_mode, mode, "Round-trip failed for mode '%s'" % mode)


func test_save_load_sound_disabled() -> void:
	var s := _make_settings()
	s.sound_enabled = false
	var config := ConfigFile.new()
	s._save_to_config(config)

	var s2 := _make_settings()
	s2._load_from_config(config)
	assert_false(s2.sound_enabled)


func test_save_load_haptic_disabled() -> void:
	var s := _make_settings()
	s.haptic_enabled = false
	var config := ConfigFile.new()
	s._save_to_config(config)

	var s2 := _make_settings()
	s2._load_from_config(config)
	assert_false(s2.haptic_enabled)


func test_save_load_screen_shake_disabled() -> void:
	var s := _make_settings()
	s.screen_shake_enabled = false
	var config := ConfigFile.new()
	s._save_to_config(config)

	var s2 := _make_settings()
	s2._load_from_config(config)
	assert_false(s2.screen_shake_enabled)


func test_save_load_shockwave_disabled() -> void:
	var s := _make_settings()
	s.shockwave_enabled = false
	var config := ConfigFile.new()
	s._save_to_config(config)

	var s2 := _make_settings()
	s2._load_from_config(config)
	assert_false(s2.shockwave_enabled)


func test_save_load_particles_disabled() -> void:
	var s := _make_settings()
	s.particle_effects_enabled = false
	var config := ConfigFile.new()
	s._save_to_config(config)

	var s2 := _make_settings()
	s2._load_from_config(config)
	assert_false(s2.particle_effects_enabled)


func test_save_load_all_feedback_disabled() -> void:
	var s := _make_settings()
	s.sound_enabled = false
	s.haptic_enabled = false
	s.screen_shake_enabled = false
	s.shockwave_enabled = false
	s.particle_effects_enabled = false
	var config := ConfigFile.new()
	s._save_to_config(config)

	var s2 := _make_settings()
	s2._load_from_config(config)
	assert_false(s2.sound_enabled)
	assert_false(s2.haptic_enabled)
	assert_false(s2.screen_shake_enabled)
	assert_false(s2.shockwave_enabled)
	assert_false(s2.particle_effects_enabled)


func test_load_from_missing_keys_uses_defaults() -> void:
	var config := ConfigFile.new()
	# No keys set — defaults should be preserved
	var s := _make_settings()
	s._load_from_config(config)
	assert_eq(s.dark_mode, "neon")
	assert_true(s.show_timer)
	assert_false(s.sound_enabled)
	assert_true(s.haptic_enabled)
	assert_true(s.screen_shake_enabled)
	assert_true(s.shockwave_enabled)
	assert_true(s.particle_effects_enabled)
