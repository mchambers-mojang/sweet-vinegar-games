class_name ComboLabel
extends Label

## Floating combo text that animates upward and fades out.
## Usage: ComboLabel.create(parent, position, text)

static func create(parent: Control, pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	var label := ComboLabel.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = pos - Vector2(60, 20)
	label.custom_minimum_size = Vector2(120, 40)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", color)
	label.modulate.a = 1.0
	parent.add_child(label)
	label._animate()


func _animate() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 60.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(queue_free)
