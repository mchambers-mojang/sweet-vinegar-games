extends GutTest

const OverlayScene := preload("res://carom/scenes/carom_connection_overlay.tscn")


func test_overlay_starts_hidden_and_blocks_input_with_safe_area() -> void:
	var overlay := OverlayScene.instantiate() as CaromConnectionOverlay
	add_child_autofree(overlay)

	assert_false(overlay.visible)
	var backdrop := overlay.get_node("Backdrop") as ColorRect
	assert_eq(backdrop.mouse_filter, Control.MOUSE_FILTER_STOP)

	var margin := overlay.get_node("MarginContainer") as MarginContainer
	var insets: Dictionary = SafeAreaManager.get_insets()
	assert_eq(margin.get_theme_constant("margin_top"), int(insets["top"]))
	assert_eq(margin.get_theme_constant("margin_left"), int(insets["left"]))
	assert_eq(margin.get_theme_constant("margin_right"), int(insets["right"]))
	assert_eq(margin.get_theme_constant("margin_bottom"), int(insets["bottom"]))


func test_show_status_updates_all_overlay_states() -> void:
	var overlay := OverlayScene.instantiate() as CaromConnectionOverlay
	add_child_autofree(overlay)

	var status_label := overlay.get_node("MarginContainer/VBoxContainer/CenterBox/StatusLabel") as Label
	var indicator_label := overlay.get_node("MarginContainer/VBoxContainer/CenterBox/IndicatorLabel") as Label
	var back_button := overlay.get_node("MarginContainer/VBoxContainer/BackButton") as Button

	overlay.show_status("connecting", "Connecting to server...")
	assert_true(overlay.visible)
	assert_eq(status_label.text, "Connecting to server...")
	assert_true(indicator_label.visible)
	assert_eq(indicator_label.pivot_offset, indicator_label.size / 2.0)
	assert_eq(back_button.text, "Cancel")

	overlay.show_status("waiting", "Waiting for opponent...")
	assert_eq(status_label.text, "Waiting for opponent...")
	assert_false(indicator_label.visible)
	assert_eq(back_button.text, "Cancel")

	overlay.show_status("connected", "Opponent found!")
	assert_eq(status_label.text, "Opponent found!")
	assert_true(indicator_label.visible)
	assert_eq(back_button.text, "Cancel")

	overlay.show_status("error", "Connection failed")
	assert_eq(status_label.text, "Connection failed")
	assert_false(indicator_label.visible)
	assert_eq(back_button.text, "Back to Menu")


func test_back_button_emits_back_requested_signal() -> void:
	var overlay := OverlayScene.instantiate() as CaromConnectionOverlay
	add_child_autofree(overlay)
	watch_signals(overlay)

	var back_button := overlay.get_node("MarginContainer/VBoxContainer/BackButton") as Button
	back_button.emit_signal("pressed")

	assert_signal_emitted(overlay, "back_requested")


func test_online_flow_scripts_load_with_connection_overlay() -> void:
	assert_not_null(load("res://carom/scripts/netcode/carom_online_flow.gd"))
	assert_not_null(load("res://carom/scripts/netcode/carom_online_match_controller.gd"))
	assert_not_null(load("res://carom/scripts/netcode/carom_multiplayer_controller.gd"))
