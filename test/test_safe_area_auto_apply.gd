extends GutTest

## Tests for SafeAreaManager.apply_to_scene_root() and
## SceneTransition._auto_apply_safe_area() auto-application logic.

# --- SafeAreaManager.apply_to_scene_root ---

func test_apply_to_scene_root_applies_to_margin_container() -> void:
	var root := Control.new()
	add_child_autofree(root)
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	root.add_child(margin)

	var result: bool = SafeAreaManager.apply_to_scene_root(root)

	assert_true(result, "apply_to_scene_root should return true when a MarginContainer is found")
	var insets := SafeAreaManager.get_insets()
	assert_eq(
		margin.get_theme_constant("margin_top"),
		insets["top"],
		"margin_top should match safe area top inset"
	)
	assert_eq(
		margin.get_theme_constant("margin_left"),
		insets["left"],
		"margin_left should match safe area left inset"
	)


func test_apply_to_scene_root_returns_false_without_margin_container() -> void:
	var root := Control.new()
	add_child_autofree(root)

	var result: bool = SafeAreaManager.apply_to_scene_root(root)

	assert_false(result, "apply_to_scene_root should return false when no MarginContainer exists")


func test_apply_to_scene_root_skips_when_skip_safe_area_meta_true() -> void:
	var root := Control.new()
	add_child_autofree(root)
	root.set_meta("skip_safe_area", true)
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	root.add_child(margin)

	var result: bool = SafeAreaManager.apply_to_scene_root(root)

	assert_false(result, "apply_to_scene_root should return false when skip_safe_area meta is true")
	assert_eq(
		margin.get_theme_constant("margin_top"),
		0,
		"margin_top should not be modified when skip_safe_area is true"
	)


func test_apply_to_scene_root_applies_when_skip_safe_area_meta_false() -> void:
	var root := Control.new()
	add_child_autofree(root)
	root.set_meta("skip_safe_area", false)
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	root.add_child(margin)

	var result: bool = SafeAreaManager.apply_to_scene_root(root)

	assert_true(result, "apply_to_scene_root should return true when skip_safe_area meta is false")


func test_apply_to_scene_root_handles_null_gracefully() -> void:
	var result: bool = SafeAreaManager.apply_to_scene_root(null)
	assert_false(result, "apply_to_scene_root should return false for null input")


# --- SceneTransition._auto_apply_safe_area ---

func test_auto_apply_safe_area_applies_to_node_with_margin_container() -> void:
	var scene_root := Control.new()
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	scene_root.add_child(margin)
	get_tree().root.add_child(scene_root)

	SceneTransition._auto_apply_safe_area()

	var insets := SafeAreaManager.get_insets()
	assert_eq(
		margin.get_theme_constant("margin_top"),
		insets["top"],
		"_auto_apply_safe_area should set margin_top from safe area insets"
	)

	get_tree().root.remove_child(scene_root)
	scene_root.queue_free()


func test_auto_apply_safe_area_respects_opt_out_meta() -> void:
	var scene_root := Control.new()
	scene_root.set_meta("skip_safe_area", true)
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	scene_root.add_child(margin)
	get_tree().root.add_child(scene_root)

	SceneTransition._auto_apply_safe_area()

	assert_eq(
		margin.get_theme_constant("margin_top"),
		0,
		"_auto_apply_safe_area should not modify margin when skip_safe_area is true"
	)

	get_tree().root.remove_child(scene_root)
	scene_root.queue_free()
