class_name GlassShatter
extends Node2D

## Spawns triangular glass-like shards that fly apart and fade out
## Usage: GlassShatter.create(parent, rect, color, shard_count)

const GRAVITY := 400.0
const LIFETIME := 0.8


static func create(parent: Node, rect: Rect2, color: Color, shard_count: int = 12) -> void:
	var shatter := GlassShatter.new()
	shatter.position = rect.position + rect.size / 2.0
	parent.add_child(shatter)
	shatter._spawn_shards(rect.size, color, shard_count)


var _shards: Array[Dictionary] = []
var _elapsed: float = 0.0
var _rect_size: Vector2


func _spawn_shards(size: Vector2, color: Color, count: int) -> void:
	_rect_size = size
	for i in count:
		# Random triangle within the rect bounds
		var center := Vector2(
			randf_range(-size.x / 2.0, size.x / 2.0),
			randf_range(-size.y / 2.0, size.y / 2.0)
		)
		var shard_size := randf_range(3.0, maxf(size.x, size.y) * 0.35)

		# Triangle vertices (random rotation)
		var angle := randf() * TAU
		var verts: PackedVector2Array = PackedVector2Array()
		for j in 3:
			var a := angle + j * TAU / 3.0 + randf_range(-0.3, 0.3)
			verts.append(center + Vector2(cos(a), sin(a)) * shard_size * randf_range(0.4, 1.0))

		# Velocity: explode outward from center
		var dir := center.normalized()
		if dir.length() < 0.1:
			dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var speed := randf_range(80.0, 250.0)
		var vel := dir * speed

		# Neon glow color — boost for HDR bloom
		var shard_color := color
		if AppTheme.is_neon:
			shard_color = Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, color.a)

		_shards.append({
			"verts": verts,
			"velocity": vel,
			"rotation_speed": randf_range(-8.0, 8.0),
			"angle": 0.0,
			"color": shard_color,
			"offset": Vector2.ZERO,
		})


func _process(delta: float) -> void:
	_elapsed += delta
	var t := _elapsed / LIFETIME

	if t >= 1.0:
		queue_free()
		return

	for shard in _shards:
		shard["velocity"] = shard["velocity"] as Vector2 + Vector2(0, GRAVITY * delta)
		shard["offset"] = shard["offset"] as Vector2 + (shard["velocity"] as Vector2) * delta
		shard["angle"] = (shard["angle"] as float) + (shard["rotation_speed"] as float) * delta

	queue_redraw()


func _draw() -> void:
	var t := _elapsed / LIFETIME
	var alpha := 1.0 - t * t  # Quadratic fade

	for shard in _shards:
		var verts: PackedVector2Array = shard["verts"]
		var offset: Vector2 = shard["offset"]
		var angle: float = shard["angle"]
		var base_color: Color = shard["color"]

		var color := Color(base_color.r, base_color.g, base_color.b, base_color.a * alpha)

		# Compute rotated + offset vertices
		var transformed := PackedVector2Array()
		var center := (verts[0] + verts[1] + verts[2]) / 3.0
		for v in verts:
			var local := v - center
			var rotated := Vector2(
				local.x * cos(angle) - local.y * sin(angle),
				local.x * sin(angle) + local.y * cos(angle)
			)
			transformed.append(rotated + center + offset)

		var colors := PackedColorArray([color, color, color])
		draw_polygon(transformed, colors)

		# Neon edge glow
		if AppTheme.is_neon:
			var edge_color := Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, alpha * 0.4)
			for i in 3:
				draw_line(transformed[i], transformed[(i + 1) % 3], edge_color, 1.5)
