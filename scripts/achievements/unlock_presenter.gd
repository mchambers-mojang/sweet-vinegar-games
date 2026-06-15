class_name UnlockPresenter
extends Node

signal platform_unlock_requested(payload: Dictionary)

var _toast_layer: CanvasLayer
var _toast_queue: Array[Dictionary] = []
var _toast_showing := false


func present_unlock(definition: Dictionary) -> void:
	if definition.is_empty():
		return
	var payload: Dictionary = definition.get("platform_payload", {})
	if not payload.is_empty():
		platform_unlock_requested.emit(payload)
	_toast_queue.append(definition)
	if not _toast_showing:
		_show_next_toast()


func _show_next_toast() -> void:
	if _toast_queue.is_empty():
		_toast_showing = false
		return
	_toast_showing = true
	var definition: Dictionary = _toast_queue.pop_front()
	var root: Window = get_tree().root
	if root == null:
		_toast_showing = false
		return
	if _toast_layer == null or not is_instance_valid(_toast_layer):
		_toast_layer = CanvasLayer.new()
		_toast_layer.layer = 120
		_toast_layer.name = "AchievementToastLayer"
		root.add_child(_toast_layer)

	var label := Label.new()
	label.text = "Achievement Unlocked: %s" % str(definition.get("title", ""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var vp_size: Vector2 = root.get_visible_rect().size
	var safe_top: int = SafeAreaManager.get_insets().get("top", 0)
	var toast_width: float = minf(420.0, vp_size.x * 0.85)
	label.custom_minimum_size = Vector2(toast_width, 48)
	label.size = Vector2(toast_width, 48)
	label.position = Vector2((vp_size.x - toast_width) * 0.5, safe_top + 24)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.pivot_offset = Vector2(toast_width, 48) / 2.0
	label.scale = Vector2(1.2, 1.2)
	_toast_layer.add_child(label)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(label, "position:y", label.position.y + 12.0, 3.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(2.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(func() -> void:
		label.queue_free()
		_show_next_toast()
	)
