extends Node

## Adjusts MarginContainer top/bottom margins to respect mobile safe areas
## (notch, status bar, home indicator). Call apply() on any MarginContainer.

var _safe_insets := Rect2i()


func _ready() -> void:
	_update_safe_area()
	get_tree().root.size_changed.connect(_update_safe_area)


func _update_safe_area() -> void:
	if not OS.has_feature("mobile"):
		_safe_insets = Rect2i()
		return
	var screen_size := DisplayServer.screen_get_size()
	var safe_area := DisplayServer.get_display_safe_area()
	_safe_insets = Rect2i(
		safe_area.position.x,
		safe_area.position.y,
		screen_size.x - safe_area.end.x,
		screen_size.y - safe_area.end.y,
	)
	# iOS fallback: if safe area reports zero insets but we're on iPhone,
	# apply minimum top inset for status bar / Dynamic Island
	if OS.has_feature("ios") and _safe_insets.position.y == 0:
		_safe_insets.position.y = 59  # Dynamic Island minimum safe area


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
