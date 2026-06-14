extends Node

## Adjusts MarginContainer top/bottom margins to respect mobile safe areas
## (notch, status bar, home indicator). Call apply() on any MarginContainer.

var _safe_insets := Rect2i()


func _ready() -> void:
	_update_safe_area()
	get_tree().root.size_changed.connect(_update_safe_area)


func _update_safe_area() -> void:
	if not OS.has_feature("mobile"):
		# Desktop: apply minimum padding so UI isn't flush against edges
		_safe_insets = Rect2i(16, 16, 16, 0)
		return
	var screen_size := DisplayServer.screen_get_size()
	var safe_area := DisplayServer.get_display_safe_area()
	# Convert from physical screen pixels to viewport-relative insets
	var viewport_size := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 390),
		ProjectSettings.get_setting("display/window/size/viewport_height", 844),
	)
	var scale_x := viewport_size.x / float(screen_size.x) if screen_size.x > 0 else 1.0
	var scale_y := viewport_size.y / float(screen_size.y) if screen_size.y > 0 else 1.0
	_safe_insets = Rect2i(
		int(safe_area.position.x * scale_x),
		int(safe_area.position.y * scale_y),
		int((screen_size.x - safe_area.end.x) * scale_x),
		int((screen_size.y - safe_area.end.y) * scale_y),
	)
	# iOS fallback: if safe area reports zero insets but we're on iPhone,
	# apply minimum top inset for status bar / Dynamic Island
	if OS.has_feature("ios") and _safe_insets.position.y == 0:
		_safe_insets.position.y = 59  # Dynamic Island minimum safe area
	# Ensure a minimum top padding on all platforms
	if _safe_insets.position.y < 16:
		_safe_insets.position.y = 16
	# Ensure minimum horizontal padding so content doesn't hug the edges
	if _safe_insets.position.x < 16:
		_safe_insets.position.x = 16
	if _safe_insets.size.x < 16:
		_safe_insets.size.x = 16


## Returns the safe area insets as a dictionary with top, bottom, left, right
func get_insets() -> Dictionary:
	return {
		"top": _safe_insets.position.y,
		"bottom": _safe_insets.size.y,
		"left": _safe_insets.position.x,
		"right": _safe_insets.size.x,
	}


## Apply safe area insets to a MarginContainer
## Only applies the inset values directly (does not add to existing margins)
func apply(container: MarginContainer) -> void:
	var insets := get_insets()
	container.add_theme_constant_override("margin_top", insets["top"])
	container.add_theme_constant_override("margin_bottom", insets["bottom"])
	container.add_theme_constant_override("margin_left", insets["left"])
	container.add_theme_constant_override("margin_right", insets["right"])


## Auto-apply safe area to a scene root node.
## Looks for a direct MarginContainer child and calls apply().
## Skipped if the scene root has meta "skip_safe_area" set to true.
## Returns true if safe area was applied.
func apply_to_scene_root(scene_root: Node) -> bool:
	if scene_root == null:
		return false
	if scene_root.has_meta("skip_safe_area") and scene_root.get_meta("skip_safe_area"):
		return false
	var margin := scene_root.get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		apply(margin)
		return true
	return false
