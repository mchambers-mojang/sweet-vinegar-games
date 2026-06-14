extends GutTest

## Unit tests for ThemePalette — pure RefCounted, no scene tree required.
## Covers colour derivation (build_custom), mode switching, and CRUD operations.

const PaletteScript := preload("res://scripts/theme/theme_palette.gd")


func _make_palette() -> ThemePalette:
	return PaletteScript.new()


# ---------------------------------------------------------------------------
# build_custom — static derivation logic
# ---------------------------------------------------------------------------

func test_build_custom_returns_all_22_keys() -> void:
	var p := ThemePalette.build_custom(
		Color(0.04, 0.04, 0.1),
		Color(0.0, 1.5, 1.5),
		Color(2.0, 0.3, 1.8),
		Color(2.0, 0.0, 0.2)
	)
	var expected_keys := [
		"background", "cell_background", "cell_selected", "cell_highlighted",
		"cell_same_number", "cell_error", "cell_given", "grid_line_thin",
		"grid_line_thick", "text_given", "text_placed", "text_error",
		"text_pencil", "button_bg", "button_bg_hover", "button_bg_pressed",
		"button_text", "button_disabled", "button_disabled_text",
		"label_text", "timer_text", "strike_active", "strike_inactive",
	]
	for k in expected_keys:
		assert_true(p.has(k), "build_custom result must contain key: %s" % k)


func test_build_custom_background_is_input_bg() -> void:
	var bg := Color(0.04, 0.04, 0.1)
	var p := ThemePalette.build_custom(bg, Color(0.0, 1.5, 1.5), Color(2.0, 0.3, 1.8), Color(2.0, 0.0, 0.2))
	assert_eq(p["background"], bg)


func test_build_custom_text_given_is_accent() -> void:
	var accent := Color(0.0, 1.5, 1.5)
	var p := ThemePalette.build_custom(Color(0.04, 0.04, 0.1), accent, Color(2.0, 0.3, 1.8), Color(2.0, 0.0, 0.2))
	assert_eq(p["text_given"], accent)


func test_build_custom_text_placed_is_secondary() -> void:
	var secondary := Color(2.0, 0.3, 1.8)
	var p := ThemePalette.build_custom(Color(0.04, 0.04, 0.1), Color(0.0, 1.5, 1.5), secondary, Color(2.0, 0.0, 0.2))
	assert_eq(p["text_placed"], secondary)


func test_build_custom_text_error_is_error() -> void:
	var error := Color(2.0, 0.0, 0.2)
	var p := ThemePalette.build_custom(Color(0.04, 0.04, 0.1), Color(0.0, 1.5, 1.5), Color(2.0, 0.3, 1.8), error)
	assert_eq(p["text_error"], error)


func test_build_custom_cell_colors_are_clamped() -> void:
	# HDR accent/secondary must not cause cell colors to exceed 1.0
	var p := ThemePalette.build_custom(
		Color(0.04, 0.04, 0.1),
		Color(0.0, 5.0, 5.0),   # very bright HDR accent
		Color(5.0, 5.0, 5.0),   # very bright HDR secondary
		Color(5.0, 0.0, 0.0)    # very bright HDR error
	)
	for key in ["cell_background", "cell_selected", "cell_highlighted", "cell_same_number",
				"cell_error", "cell_given", "grid_line_thin",
				"button_bg", "button_bg_hover", "button_bg_pressed", "button_disabled"]:
		var c: Color = p[key]
		assert_true(c.r <= 1.0 and c.g <= 1.0 and c.b <= 1.0,
			"Key %s must have clamped RGB, got (%s, %s, %s)" % [key, c.r, c.g, c.b])


func test_build_custom_neon_defaults_match_neon_colors() -> void:
	# The neon color set is exactly what build_custom returns with neon base colors.
	var defaults := ThemePalette.default_palette_colors()
	var derived := ThemePalette.build_custom(
		defaults["bg"], defaults["accent"], defaults["secondary"], defaults["error"]
	)
	# Key neon values that must match exactly
	assert_eq(derived["text_given"], defaults["accent"])
	assert_eq(derived["text_placed"], defaults["secondary"])
	assert_eq(derived["text_error"], defaults["error"])
	assert_eq(derived["background"], defaults["bg"])


# ---------------------------------------------------------------------------
# Mode switching
# ---------------------------------------------------------------------------

func test_set_mode_dark_sets_is_dark_true() -> void:
	var pal := _make_palette()
	pal.set_mode("dark")
	assert_true(pal.is_dark)
	assert_false(pal.is_neon)


func test_set_mode_light_sets_is_dark_false() -> void:
	var pal := _make_palette()
	pal.set_mode("light")
	assert_false(pal.is_dark)
	assert_false(pal.is_neon)


func test_set_mode_neon_sets_is_neon_true() -> void:
	var pal := _make_palette()
	pal.set_mode("neon")
	assert_true(pal.is_neon)
	assert_true(pal.is_dark)


func test_set_mode_custom_sets_is_neon_true() -> void:
	var pal := _make_palette()
	pal.set_mode("custom")
	assert_true(pal.is_neon)
	assert_true(pal.is_dark)


func test_set_mode_emits_palette_changed() -> void:
	var pal := _make_palette()
	var tracker := {"fired": false}
	pal.palette_changed.connect(func() -> void: tracker["fired"] = true)
	pal.set_mode("dark")
	assert_true(tracker["fired"], "palette_changed should fire when set_mode is called")


func test_set_mode_dark_updates_get_color() -> void:
	var pal := _make_palette()
	pal.set_mode("dark")
	# Dark background should be much darker than white
	var bg := pal.get_color("background")
	assert_true(bg.r < 0.2 and bg.g < 0.2 and bg.b < 0.2,
		"Dark mode background should be very dark")


func test_set_mode_light_background_is_white_ish() -> void:
	var pal := _make_palette()
	pal.set_mode("light")
	var bg := pal.get_color("background")
	assert_true(bg.r > 0.8 and bg.g > 0.8 and bg.b > 0.8,
		"Light mode background should be bright")


func test_set_mode_neon_text_given_is_hdr() -> void:
	var pal := _make_palette()
	pal.set_mode("neon")
	var tg := pal.get_color("text_given")
	assert_true(tg.r > 1.0 or tg.g > 1.0 or tg.b > 1.0,
		"Neon text_given should have an HDR component > 1.0")


func test_get_color_unknown_key_returns_magenta() -> void:
	var pal := _make_palette()
	assert_eq(pal.get_color("nonexistent_key"), Color.MAGENTA)


# ---------------------------------------------------------------------------
# Custom palette CRUD
# ---------------------------------------------------------------------------

func test_add_custom_palette_returns_zero_for_first() -> void:
	var pal := _make_palette()
	var idx := pal.add_custom_palette("Test", Color.BLACK, Color.RED, Color.GREEN, Color.BLUE)
	assert_eq(idx, 0)


func test_add_two_palettes_returns_sequential_indices() -> void:
	var pal := _make_palette()
	var i0 := pal.add_custom_palette("A", Color.BLACK, Color.RED, Color.GREEN, Color.BLUE)
	var i1 := pal.add_custom_palette("B", Color.WHITE, Color.RED, Color.GREEN, Color.BLUE)
	assert_eq(i0, 0)
	assert_eq(i1, 1)


func test_get_custom_palette_round_trip() -> void:
	var pal := _make_palette()
	var bg := Color(0.1, 0.2, 0.3)
	var acc := Color(0.0, 1.5, 1.5)
	pal.add_custom_palette("RoundTrip", bg, acc, Color.RED, Color.BLUE)
	var loaded: Dictionary = pal.get_custom_palette(0)
	assert_false(loaded.is_empty())
	assert_eq(loaded["name"], "RoundTrip")
	# Colours survive array serialization round-trip (within float tolerance)
	assert_almost_eq(loaded["bg"].r, bg.r, 0.001)
	assert_almost_eq(loaded["bg"].g, bg.g, 0.001)
	assert_almost_eq(loaded["bg"].b, bg.b, 0.001)
	assert_almost_eq(loaded["accent"].g, acc.g, 0.001)


func test_get_custom_palette_out_of_range_returns_empty() -> void:
	var pal := _make_palette()
	assert_true(pal.get_custom_palette(5).is_empty())


func test_update_custom_palette_changes_stored_value() -> void:
	var pal := _make_palette()
	pal.add_custom_palette("Original", Color.BLACK, Color.RED, Color.GREEN, Color.BLUE)
	pal.update_custom_palette(0, "Updated", Color.WHITE, Color.RED, Color.GREEN, Color.BLUE)
	var loaded: Dictionary = pal.get_custom_palette(0)
	assert_eq(loaded["name"], "Updated")
	assert_almost_eq(loaded["bg"].r, 1.0, 0.001)


func test_duplicate_custom_palette() -> void:
	var pal := _make_palette()
	pal.add_custom_palette("Original", Color.BLACK, Color.RED, Color.GREEN, Color.BLUE)
	var new_idx := pal.duplicate_custom_palette(0)
	assert_eq(new_idx, 1)
	assert_eq(pal.custom_palettes.size(), 2)
	var copy: Dictionary = pal.get_custom_palette(1)
	assert_true(copy["name"].ends_with("Copy"))


func test_remove_custom_palette_adjusts_active_index() -> void:
	var pal := _make_palette()
	pal.add_custom_palette("A", Color.BLACK, Color.RED, Color.GREEN, Color.BLUE)
	pal.add_custom_palette("B", Color.WHITE, Color.RED, Color.GREEN, Color.BLUE)
	pal.active_custom_palette_index = 1
	pal.remove_custom_palette(0)
	# Active index should shift down by 1
	assert_eq(pal.active_custom_palette_index, 0)


func test_remove_active_palette_clears_active_index() -> void:
	var pal := _make_palette()
	pal.add_custom_palette("A", Color.BLACK, Color.RED, Color.GREEN, Color.BLUE)
	pal.active_custom_palette_index = 0
	pal.remove_custom_palette(0)
	assert_eq(pal.active_custom_palette_index, -1)


func test_ensure_default_palette_creates_entry_when_empty() -> void:
	var pal := _make_palette()
	assert_true(pal.custom_palettes.is_empty())
	var created := pal.ensure_default_palette()
	assert_true(created)
	assert_eq(pal.custom_palettes.size(), 1)
	assert_eq(pal.active_custom_palette_index, 0)


func test_ensure_default_palette_no_op_when_not_empty() -> void:
	var pal := _make_palette()
	pal.add_custom_palette("Existing", Color.BLACK, Color.RED, Color.GREEN, Color.BLUE)
	var created := pal.ensure_default_palette()
	assert_false(created)
	assert_eq(pal.custom_palettes.size(), 1)


func test_get_active_custom_palette_returns_empty_when_none() -> void:
	var pal := _make_palette()
	assert_true(pal.get_active_custom_palette().is_empty())


func test_get_active_custom_palette_returns_correct_entry() -> void:
	var pal := _make_palette()
	pal.add_custom_palette("First", Color.BLACK, Color.RED, Color.GREEN, Color.BLUE)
	pal.add_custom_palette("Second", Color.WHITE, Color.RED, Color.GREEN, Color.BLUE)
	pal.active_custom_palette_index = 1
	var active: Dictionary = pal.get_active_custom_palette()
	assert_eq(active["name"], "Second")


# ---------------------------------------------------------------------------
# set_mode("custom") uses active palette
# ---------------------------------------------------------------------------

func test_set_mode_custom_with_no_palette_falls_back_to_neon() -> void:
	var pal := _make_palette()
	# No custom palette — should fall back to neon colors
	pal.set_mode("custom")
	assert_true(pal.is_neon)
	# text_given should still have an HDR component (neon default)
	var tg := pal.get_color("text_given")
	assert_true(tg.r > 1.0 or tg.g > 1.0 or tg.b > 1.0,
		"Custom fall-back should produce neon (HDR) text_given")


func test_set_mode_custom_uses_active_palette_colors() -> void:
	var pal := _make_palette()
	var custom_bg := Color(0.5, 0.1, 0.1)
	pal.add_custom_palette("Mine", custom_bg, Color(0.0, 1.5, 1.5), Color(2.0, 0.3, 1.8), Color(2.0, 0.0, 0.2))
	pal.active_custom_palette_index = 0
	pal.set_mode("custom")
	assert_eq(pal.get_color("background"), custom_bg)


# ---------------------------------------------------------------------------
# default_palette_colors
# ---------------------------------------------------------------------------

func test_default_palette_colors_returns_neon_defaults() -> void:
	var d := ThemePalette.default_palette_colors()
	assert_true(d.has("bg"))
	assert_true(d.has("accent"))
	assert_true(d.has("secondary"))
	assert_true(d.has("error"))
	# Accent should be HDR
	assert_true(d["accent"].g > 1.0 or d["accent"].r > 1.0 or d["accent"].b > 1.0)
