extends GutTest

const AppThemeScript := preload("res://scripts/autoload/app_theme.gd")


func make_app_theme() -> Node:
	var app_theme := Node.new()
	app_theme.set_script(AppThemeScript)
	return app_theme


func test_force_popup_opacity_sets_option_button_popup_non_transparent() -> void:
	var app_theme := make_app_theme()
	add_child_autofree(app_theme)
	var option := OptionButton.new()
	add_child_autofree(option)
	option.get_popup().transparent = true

	app_theme._force_popup_opacity(option)

	assert_false(option.get_popup().transparent)


func test_force_popup_opacity_sets_color_picker_popup_non_transparent() -> void:
	var app_theme := make_app_theme()
	add_child_autofree(app_theme)
	var picker := ColorPickerButton.new()
	add_child_autofree(picker)
	picker.get_popup().transparent = true

	app_theme._force_popup_opacity(picker)

	assert_false(picker.get_popup().transparent)


func test_on_node_added_applies_popup_fix_for_nested_dropdowns() -> void:
	var app_theme := make_app_theme()
	add_child_autofree(app_theme)
	var root := VBoxContainer.new()
	add_child_autofree(root)
	var option := OptionButton.new()
	option.get_popup().transparent = true
	root.add_child(option)

	app_theme._on_node_added(root)

	assert_false(option.get_popup().transparent)
