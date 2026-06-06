class_name NeonSweep
extends Node2D

## Sweeping neon wipe effect for row/column/box clears
## A bright line sweeps across the cleared area

const LIFETIME := 0.4


static func create(parent: Node, rect: Rect2, horizontal: bool = true, color: Color = Color(0.0, 2.0, 1.5)) -> void:
	if not SettingsManager.particle_effects_enabled:
		return
	var sweep := NeonSweep.new()
	sweep.position = rect.position
	parent.add_child(sweep)
	sweep._start(rect.size, horizontal, color)


var _size: Vector2
var _horizontal: bool
var _color: Color
var _elapsed: float = 0.0


func _start(size: Vector2, horizontal: bool, color: Color) -> void:
	_size = size
	_horizontal = horizontal
	_color = color


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _elapsed / LIFETIME
	var alpha := 1.0 - t

	if _horizontal:
		# Sweep left to right
		var x := t * _size.x
		var width := _size.x * 0.15
		var sweep_rect := Rect2(x - width / 2.0, 0, width, _size.y)
		var glow_color := Color(_color.r, _color.g, _color.b, alpha * 0.6)
		draw_rect(sweep_rect, glow_color)

		# Core bright line
		var core_color := Color(_color.r * 1.5, _color.g * 1.5, _color.b * 1.5, alpha)
		draw_line(Vector2(x, 0), Vector2(x, _size.y), core_color, 2.0)
	else:
		# Sweep top to bottom
		var y := t * _size.y
		var height := _size.y * 0.15
		var vertical_sweep_rect := Rect2(0, y - height / 2.0, _size.x, height)
		var vertical_glow_color := Color(_color.r, _color.g, _color.b, alpha * 0.6)
		draw_rect(vertical_sweep_rect, vertical_glow_color)

		var vertical_core_color := Color(_color.r * 1.5, _color.g * 1.5, _color.b * 1.5, alpha)
		draw_line(Vector2(0, y), Vector2(_size.x, y), vertical_core_color, 2.0)

	# Flash the whole area briefly at start
	if t < 0.15:
		var flash_alpha := (1.0 - t / 0.15) * 0.3
		var flash_color := Color(_color.r, _color.g, _color.b, flash_alpha)
		draw_rect(Rect2(Vector2.ZERO, _size), flash_color)
