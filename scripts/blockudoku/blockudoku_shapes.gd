class_name BlockudokuShapes
extends RefCounted

## Defines all block shapes for Blockudoku (2-5 cells, no monominoes)
## Each shape is an Array of Vector2i offsets from origin (0,0)

static func get_all_shapes() -> Array[Array]:
	var shapes: Array[Array] = []

	# === DOMINOES (2 cells) ===
	shapes.append([Vector2i(0, 0), Vector2i(1, 0)])   # Horizontal
	shapes.append([Vector2i(0, 0), Vector2i(0, 1)])   # Vertical

	# === TRIOMINOES (3 cells) ===
	# Straight
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])   # Horizontal line
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)])   # Vertical line
	# L-shapes (all 4 rotations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)])   # L top-left
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)])   # L top-right
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)])   # L bottom-left
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, -1)])  # L inverted

	# === TETROMINOES (4 cells) ===
	# Straight line
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])  # H line
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)])  # V line
	# Square
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)])  # 2x2 square
	# T-shapes (4 rotations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)])  # T down
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, -1)]) # T up
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 1)])  # T right
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(-1, 1)]) # T left
	# L-shapes (4 rotations)
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)])  # L
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(-1, 2)]) # J
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)])  # L rotated
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)])  # J rotated
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2)])  # L rotated 2
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)])  # J rotated 2
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, -1)]) # L rotated 3
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, -1)]) # J rotated 3
	# S-shapes
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)])  # S horizontal
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, -1)]) # S vertical
	# Z-shapes
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(2, -1)]) # Z horizontal
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)])   # Z vertical

	# === PENTOMINOES (5 cells) — a subset of interesting ones ===
	# Plus/cross
	shapes.append([Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)])
	# Straight line
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)])
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4)])
	# Big L shapes
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 3)])
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 1)])
	# U shape
	shapes.append([Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)])
	# T pentomino
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2)])
	# Corner 3x3 minus
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(0, 2)])
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)])

	return shapes


## Pick n random shapes from the pool
static func pick_random(count: int) -> Array[Array]:
	var all := get_all_shapes()
	var result: Array[Array] = []
	for i in count:
		result.append(all[randi() % all.size()])
	return result


## Normalize a shape so its minimum x/y offset is 0
static func normalize(shape: Array) -> Array[Vector2i]:
	var min_x := 999
	var min_y := 999
	for cell in shape:
		var c: Vector2i = cell
		min_x = mini(min_x, c.x)
		min_y = mini(min_y, c.y)
	var result: Array[Vector2i] = []
	for cell in shape:
		var c: Vector2i = cell
		result.append(Vector2i(c.x - min_x, c.y - min_y))
	return result


## Get bounding size of a shape (width, height)
static func get_bounds(shape: Array) -> Vector2i:
	var max_x := 0
	var max_y := 0
	for cell in shape:
		var c: Vector2i = cell
		max_x = maxi(max_x, c.x)
		max_y = maxi(max_y, c.y)
	return Vector2i(max_x + 1, max_y + 1)


## Get a unique color for a shape based on its geometry
static func get_shape_color(shape: Array) -> Color:
	var norm := normalize(shape)
	# Sort cells for consistent hashing
	norm.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	# Build a hash from cell positions
	var h := 0
	for c in norm:
		h = h * 31 + c.x * 7 + c.y * 13
	# Use golden ratio spacing for well-distributed hues
	var hue := fmod(float(absi(h)) * 0.618033988749, 1.0)
	return Color.from_hsv(hue, 0.55, 0.85)
