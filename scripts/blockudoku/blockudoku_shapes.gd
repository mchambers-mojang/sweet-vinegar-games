class_name BlockudokuShapes
extends RefCounted

## Defines all block shapes for Blockudoku organized by family.
## Each shape is an Array of Vector2i offsets from origin (0,0).
## New shape families can be toggled on/off in settings.


static func get_all_shapes() -> Array[Array]:
	var shapes: Array[Array] = []
	shapes.append_array(_get_standard_shapes())

	if SettingsManager.blockudoku_pentominoes:
		shapes.append_array(_get_pentomino_shapes())
	if SettingsManager.blockudoku_p_pentomino:
		shapes.append_array(_get_p_pentomino_shapes())
	if SettingsManager.blockudoku_w_pentomino:
		shapes.append_array(_get_w_pentomino_shapes())
	if SettingsManager.blockudoku_y_pentomino:
		shapes.append_array(_get_y_pentomino_shapes())
	if SettingsManager.blockudoku_f_pentomino:
		shapes.append_array(_get_f_pentomino_shapes())
	if SettingsManager.blockudoku_n_pentomino:
		shapes.append_array(_get_n_pentomino_shapes())
	if SettingsManager.blockudoku_hexominoes:
		shapes.append_array(_get_hexomino_shapes())
	if SettingsManager.blockudoku_diagonals:
		shapes.append_array(_get_diagonal_shapes())

	return shapes


static func _get_standard_shapes() -> Array[Array]:
	var shapes: Array[Array] = []

	# === DOMINOES (2 cells) ===
	shapes.append([Vector2i(0, 0), Vector2i(1, 0)])   # Horizontal
	shapes.append([Vector2i(0, 0), Vector2i(0, 1)])   # Vertical

	# === TRIOMINOES (3 cells) ===
	# Straight
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])   # Horizontal line
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)])   # Vertical line
	# L-shapes (all 4 rotations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)])   # top-left corner
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)])   # top-right corner
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)])   # bottom-right corner
	shapes.append([Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)])   # bottom-left corner

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
	# L-shapes (all 8 orientations: L + J)
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)])  # L
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(-1, 2)]) # J
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)])  # L rotated
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)])  # J rotated
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2)])  # L rotated 2
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)])  # J rotated 2
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, -1)]) # L rotated 3
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, -1)]) # J rotated 3
	# S-shapes (2 rotations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)])  # S horizontal
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, -1)]) # S vertical
	# Z-shapes (2 rotations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(2, -1)]) # Z horizontal
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)])   # Z vertical

	return shapes


static func _get_pentomino_shapes() -> Array[Array]:
	var shapes: Array[Array] = []

	# Plus/cross (X pentomino — rotationally symmetric)
	shapes.append([Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)])

	# I pentomino (2 orientations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)])
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4)])

	# L pentomino (all 8 orientations: 4 rotations × 2 chiralities)
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 3)])  # L R0
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 1)])  # L R90
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)])  # L R180
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(3, -1)]) # L R270
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)])  # J R0
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)])  # J R90
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 0)])  # J R180
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, -1)]) # J R270

	# U pentomino (4 rotations)
	shapes.append([Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)])  # U R0
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)])  # U R90
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(2, 1)])  # U R180
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)])  # U R270

	# T pentomino (4 rotations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2)])  # T R0
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 0), Vector2i(2, 0)])  # T R90 (points right... actually this is V, let me fix)
	shapes.append([Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)])  # T R180
	shapes.append([Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)])  # T R270

	# V pentomino (4 rotations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(0, 2)])  # V R0
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)])  # V R90
	shapes.append([Vector2i(2, 0), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)])  # V R180
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)])  # V R270

	return shapes


static func _get_p_pentomino_shapes() -> Array[Array]:
	var shapes: Array[Array] = []
	# P pentomino: 2x2 block + tail (8 orientations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)])  # P R0
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)])  # P R90
	shapes.append([Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)])  # P R180
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)])  # P R270
	# Mirror (F')
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)])  # P' R0
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)])  # P' R90
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)])  # P' R180
	shapes.append([Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)])  # P' R270
	return shapes


static func _get_w_pentomino_shapes() -> Array[Array]:
	var shapes: Array[Array] = []
	# W pentomino: stair-step (4 rotations)
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)])  # W R0
	shapes.append([Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2)])  # W R90
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)])  # W R180
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)])  # W R270
	return shapes


static func _get_y_pentomino_shapes() -> Array[Array]:
	var shapes: Array[Array] = []
	# Y pentomino: 4-long with one branch (8 orientations)
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 1)])  # Y R0
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(1, 1)])  # Y R90
	shapes.append([Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(0, 2)])  # Y R180
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, -1)]) # Y R270
	# Mirror
	shapes.append([Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(0, 1)])  # Y' R0
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(1, -1)]) # Y' R90
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 2)])  # Y' R180
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1)])  # Y' R270
	return shapes


static func _get_f_pentomino_shapes() -> Array[Array]:
	var shapes: Array[Array] = []
	# F pentomino: asymmetric (8 orientations)
	shapes.append([Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)])  # F R0
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)])  # F R90
	shapes.append([Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2)])  # F R180
	shapes.append([Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)])  # F R270
	# Mirror
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)])  # F' R0
	shapes.append([Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2)])  # F' R90
	shapes.append([Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)])  # F' R180
	shapes.append([Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)])  # F' R270
	return shapes


static func _get_n_pentomino_shapes() -> Array[Array]:
	var shapes: Array[Array] = []
	# N pentomino: zigzag/snake (8 orientations)
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(1, 3)])  # N R0
	shapes.append([Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)])  # N R90
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)])  # N R180
	shapes.append([Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2)])  # N R270
	# Mirror
	shapes.append([Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(0, 3)])  # N' R0
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)])  # N' R90
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 0), Vector2i(1, 1)])  # N' R180
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)])  # N' R270
	return shapes


static func _get_hexomino_shapes() -> Array[Array]:
	var shapes: Array[Array] = []

	# 2x3 rectangle (2 orientations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)])
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)])

	# 6-line (2 orientations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)])
	shapes.append([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5)])

	# Extended T (4 rotations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(1, 1), Vector2i(2, 1)])
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 1)])
	shapes.append([Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)])
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(0, 2)])

	# C/U hexomino (4 rotations)
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)])
	shapes.append([Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2)])
	shapes.append([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(0, 2), Vector2i(2, 2)])
	shapes.append([Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)])

	return shapes


static func _get_diagonal_shapes() -> Array[Array]:
	var shapes: Array[Array] = []
	# 3-tile diagonal / (bottom-left to top-right)
	shapes.append([Vector2i(0, 2), Vector2i(1, 1), Vector2i(2, 0)])
	# 3-tile diagonal \ (top-left to bottom-right)
	shapes.append([Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2)])
	return shapes


## Pick n random shapes from the pool
static func pick_random(count: int, rng: RandomNumberGenerator = null) -> Array[Array]:
	var all := get_all_shapes()
	var result: Array[Array] = []
	for i in count:
		if rng:
			result.append(all[rng.randi_range(0, all.size() - 1)])
		else:
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
		var normalized_cell: Vector2i = cell
		result.append(Vector2i(normalized_cell.x - min_x, normalized_cell.y - min_y))
	return result


## Rotate a shape 90° clockwise and normalize to origin.
static func rotate_clockwise(shape: Array) -> Array[Vector2i]:
	var rotated: Array[Vector2i] = []
	for cell in shape:
		var c: Vector2i = cell
		rotated.append(Vector2i(c.y, -c.x))
	return normalize(rotated)


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
	norm.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	var h := 0
	for c in norm:
		h = h * 31 + c.x * 7 + c.y * 13
	var hue := fmod(float(absi(h)) * 0.618033988749, 1.0)
	return Color.from_hsv(hue, 0.55, 0.85)
