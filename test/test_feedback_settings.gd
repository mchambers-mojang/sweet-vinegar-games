extends GutTest

## Unit tests for FeedbackSettings — defaults, changed signals, and persistence.

const FeedbackSettingsScript := preload("res://scripts/settings/feedback_settings.gd")


func _make_feedback() -> FeedbackSettings:
	return FeedbackSettingsScript.new()


# --- Default values ---

func test_default_sound_enabled_is_true() -> void:
	var f := _make_feedback()
	assert_true(f.sound_enabled)


func test_default_haptic_enabled_is_true() -> void:
	var f := _make_feedback()
	assert_true(f.haptic_enabled)


func test_default_screen_shake_enabled_is_true() -> void:
	var f := _make_feedback()
	assert_true(f.screen_shake_enabled)


func test_default_shockwave_enabled_is_true() -> void:
	var f := _make_feedback()
	assert_true(f.shockwave_enabled)


func test_default_particle_effects_enabled_is_true() -> void:
	var f := _make_feedback()
	assert_true(f.particle_effects_enabled)


# --- changed signal ---

func test_setting_sound_enabled_emits_changed() -> void:
	var f := _make_feedback()
	watch_signals(f)
	f.sound_enabled = false
	assert_signal_emitted(f, "changed")


func test_setting_haptic_enabled_emits_changed() -> void:
	var f := _make_feedback()
	watch_signals(f)
	f.haptic_enabled = false
	assert_signal_emitted(f, "changed")


func test_setting_screen_shake_emits_changed() -> void:
	var f := _make_feedback()
	watch_signals(f)
	f.screen_shake_enabled = false
	assert_signal_emitted(f, "changed")


func test_setting_shockwave_emits_changed() -> void:
	var f := _make_feedback()
	watch_signals(f)
	f.shockwave_enabled = false
	assert_signal_emitted(f, "changed")


func test_setting_particles_emits_changed() -> void:
	var f := _make_feedback()
	watch_signals(f)
	f.particle_effects_enabled = false
	assert_signal_emitted(f, "changed")


# --- save / load round-trip ---

func test_save_load_sound_disabled() -> void:
	var f := _make_feedback()
	f.sound_enabled = false
	var config := ConfigFile.new()
	f.save(config)

	var f2 := _make_feedback()
	f2.load_from(config)
	assert_false(f2.sound_enabled)


func test_save_load_haptic_disabled() -> void:
	var f := _make_feedback()
	f.haptic_enabled = false
	var config := ConfigFile.new()
	f.save(config)

	var f2 := _make_feedback()
	f2.load_from(config)
	assert_false(f2.haptic_enabled)


func test_save_load_screen_shake_disabled() -> void:
	var f := _make_feedback()
	f.screen_shake_enabled = false
	var config := ConfigFile.new()
	f.save(config)

	var f2 := _make_feedback()
	f2.load_from(config)
	assert_false(f2.screen_shake_enabled)


func test_save_load_shockwave_disabled() -> void:
	var f := _make_feedback()
	f.shockwave_enabled = false
	var config := ConfigFile.new()
	f.save(config)

	var f2 := _make_feedback()
	f2.load_from(config)
	assert_false(f2.shockwave_enabled)


func test_save_load_particles_disabled() -> void:
	var f := _make_feedback()
	f.particle_effects_enabled = false
	var config := ConfigFile.new()
	f.save(config)

	var f2 := _make_feedback()
	f2.load_from(config)
	assert_false(f2.particle_effects_enabled)


func test_save_load_all_disabled() -> void:
	var f := _make_feedback()
	f.sound_enabled = false
	f.haptic_enabled = false
	f.screen_shake_enabled = false
	f.shockwave_enabled = false
	f.particle_effects_enabled = false
	var config := ConfigFile.new()
	f.save(config)

	var f2 := _make_feedback()
	f2.load_from(config)
	assert_false(f2.sound_enabled)
	assert_false(f2.haptic_enabled)
	assert_false(f2.screen_shake_enabled)
	assert_false(f2.shockwave_enabled)
	assert_false(f2.particle_effects_enabled)


func test_load_from_missing_keys_uses_defaults() -> void:
	var config := ConfigFile.new()
	# No keys set — defaults should be preserved
	var f := _make_feedback()
	f.load_from(config)
	assert_true(f.sound_enabled)
	assert_true(f.haptic_enabled)
	assert_true(f.screen_shake_enabled)
	assert_true(f.shockwave_enabled)
	assert_true(f.particle_effects_enabled)
