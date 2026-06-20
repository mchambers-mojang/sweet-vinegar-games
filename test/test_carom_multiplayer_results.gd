extends GutTest

const ResultsScript: GDScript = preload("res://carom/scripts/carom_multiplayer_results.gd")


func _make_results() -> Control:
	var results: Control = ResultsScript.new()
	add_child_autofree(results)
	return results


func test_show_results_win_text_and_score() -> void:
	var results := _make_results()
	results.show_results(true, 5, 3, false)

	var title := results.find_child("TitleLabel", true, false) as Label
	var score := results.find_child("ScoreLabel", true, false) as Label
	var subtitle := results.find_child("SubtitleLabel", true, false) as Label

	assert_eq(title.text, "You Win!")
	assert_eq(score.text, "5 – 3")
	assert_false(subtitle.visible)


func test_show_results_loss_text_and_score() -> void:
	var results := _make_results()
	results.show_results(false, 2, 5, false)

	var title := results.find_child("TitleLabel", true, false) as Label
	var score := results.find_child("ScoreLabel", true, false) as Label
	var subtitle := results.find_child("SubtitleLabel", true, false) as Label

	assert_eq(title.text, "You Lose!")
	assert_eq(score.text, "2 – 5")
	assert_false(subtitle.visible)


func test_show_results_forfeit_text_variant() -> void:
	var results := _make_results()
	results.show_results(true, 3, 2, true)

	var title := results.find_child("TitleLabel", true, false) as Label
	var subtitle := results.find_child("SubtitleLabel", true, false) as Label
	var score := results.find_child("ScoreLabel", true, false) as Label

	assert_eq(title.text, "Opponent Left")
	assert_eq(subtitle.text, "You win by forfeit")
	assert_true(subtitle.visible)
	assert_eq(score.text, "3 – 2")


func test_menu_requested_emitted_on_button_press() -> void:
	var results := _make_results()
	results.show_results(true, 1, 0, false)
	var emitted: Array[bool] = [false]
	results.menu_requested.connect(func() -> void:
		emitted[0] = true
	)

	var button := results.find_child("BackToMenuButton", true, false) as Button
	button.emit_signal("pressed")

	assert_true(emitted[0])


func test_panel_centered_within_safe_area() -> void:
	var results := _make_results()
	results.show_results(true, 1, 0, false)

	var panel := results.find_child("ResultsPanel", true, false) as PanelContainer
	var insets: Dictionary = SafeAreaManager.get_insets()
	var viewport_size: Vector2 = results.get_viewport_rect().size
	var safe_center_x: float = insets["left"] + (viewport_size.x - insets["left"] - insets["right"]) * 0.5
	var safe_center_y: float = insets["top"] + (viewport_size.y - insets["top"] - insets["bottom"]) * 0.5
	var panel_center_x: float = (panel.offset_left + panel.offset_right) * 0.5
	var panel_center_y: float = (panel.offset_top + panel.offset_bottom) * 0.5

	assert_almost_eq(panel_center_x, safe_center_x, 0.01)
	assert_almost_eq(panel_center_y, safe_center_y, 0.01)
