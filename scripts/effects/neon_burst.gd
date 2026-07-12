class_name NeonBurst
extends Node2D

## Quick neon spark/particle burst — used on placements, clears, combos
## Usage: NeonBurst.create(parent, position, color, count, intensity)

const LIFETIME := 0.5


static func create(parent: Node, pos: Vector2, color: Color, count: int = 16, intensity: float = 1.0) -> void:
	var burst := NeonBurst.new()
	burst.position = pos
	parent.add_child(burst)
	burst._spawn_particles(color, count, intensity)


var _particles: Array[Dictionary] = []
var _elapsed: float = 0.0


func _spawn_particles(color: Color, count: int, intensity: float) -> void:
	for i in count:
		var angle := randf() * TAU
		var speed := randf_range(60.0, 200.0) * intensity
		var vel := Vector2(cos(angle), sin(angle)) * speed
		var size := randf_range(1.5, 4.0) * intensity

		# HDR boost for bloom
		var p_color := color
		if AppTheme.is_neon:
			p_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 1.0)

		_particles.append({
			"pos": Vector2.ZERO,
			"vel": vel,
			"size": size,
			"color": p_color,
			"drag": randf_range(2.0, 4.0),
		})


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= LIFETIME:
		queue_free()
		return

	for p in _particles:
		var vel: Vector2 = p["vel"]
		var drag: float = p["drag"]
		vel *= (1.0 - drag * delta)
		p["vel"] = vel
		p["pos"] = (p["pos"] as Vector2) + vel * delta

	queue_redraw()


func _draw() -> void:
	var t := _elapsed / LIFETIME
	var alpha := 1.0 - t * t

	for p in _particles:
		var pos: Vector2 = p["pos"]
		var size: float = p["size"] * (1.0 - t * 0.5)
		var base_color: Color = p["color"]
		var color := Color(base_color.r, base_color.g, base_color.b, alpha)

		draw_circle(pos, size, color)

		# Trail line
		if AppTheme.is_neon:
			var vel: Vector2 = p["vel"]
			var trail_end := pos - vel.normalized() * size * 3.0
			var trail_color := Color(base_color.r, base_color.g, base_color.b, alpha * 0.3)
			draw_line(pos, trail_end, trail_color, size * 0.5)
