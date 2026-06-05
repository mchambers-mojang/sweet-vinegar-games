class_name ComboLabel
extends Label

## Floating combo text with randomized arc animation and high readability.
## Usage: ComboLabel.create(parent, position, text)

static func create(parent: Control, pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	var label := ComboLabel.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = pos - Vector2(80, 24)
	label.custom_minimum_size = Vector2(160, 48)
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", color)

	# Outline for readability against any background
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))

	# Shadow for extra pop
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))

	# Start slightly scaled up for punch
	label.pivot_offset = label.custom_minimum_size / 2.0
	label.scale = Vector2(1.3, 1.3)
	label.modulate.a = 1.0
	parent.add_child(label)
	label._animate()


func _animate() -> void:
	# Randomize arc direction — wider spread
	var angle := randf_range(-PI * 0.75, -PI * 0.25)  # Broad upward arc
	var distance := randf_range(70.0, 120.0)
	var target_offset := Vector2(cos(angle), sin(angle)) * distance

	# Random rotation wobble
	var spin := randf_range(-12.0, 12.0)  # degrees

	var tween := create_tween()
	tween.set_parallel(true)

	# Arc movement with bounce feel
	tween.tween_property(self, "position", position + target_offset, 1.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Scale: pop in, overshoot, settle
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.15) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(0.9, 0.9), 0.9) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD).set_delay(0.3)

	# Rotation wobble
	tween.tween_property(self, "rotation_degrees", spin, 1.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

	# Fade out in the second half
	tween.tween_property(self, "modulate:a", 0.0, 0.5) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD).set_delay(0.6)

	tween.chain().tween_callback(queue_free)
