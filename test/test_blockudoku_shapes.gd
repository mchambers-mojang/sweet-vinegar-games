extends GutTest

## Unit tests for BlockudokuShapes — normalization, rotation, bounds, pick_random.


# --- normalize ---

func test_normalize_already_at_origin() -> void:
	var shape: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var normalized: Array[Vector2i] = BlockudokuShapes.normalize(shape)
	assert_eq(normalized, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i])


func test_normalize_shifts_to_origin() -> void:
	var shape: Array = [Vector2i(3, 2), Vector2i(4, 2), Vector2i(3, 3)]
	var normalized: Array[Vector2i] = BlockudokuShapes.normalize(shape)
	assert_eq(normalized[0], Vector2i(0, 0))
	assert_eq(normalized[1], Vector2i(1, 0))
	assert_eq(normalized[2], Vector2i(0, 1))


func test_normalize_negative_offsets() -> void:
	var shape: Array = [Vector2i(-1, -2), Vector2i(0, -2)]
	var normalized: Array[Vector2i] = BlockudokuShapes.normalize(shape)
	assert_eq(normalized[0], Vector2i(0, 0))
	assert_eq(normalized[1], Vector2i(1, 0))


# --- rotate_clockwise ---

func test_rotate_horizontal_line() -> void:
	# Horizontal line (0,0),(1,0),(2,0) should become vertical
	var shape: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var rotated: Array[Vector2i] = BlockudokuShapes.rotate_clockwise(shape)
	# After rotation: (y, -x) then normalize
	# (0,0) -> (0,0), (0,-1) -> (0,-1), (0,-2) -> (0,-2) => normalize => (0,0),(0,1),(0,2)
	assert_eq(rotated.size(), 3)
	# Should be vertical after rotation
	var bounds: Vector2i = BlockudokuShapes.get_bounds(rotated)
	assert_eq(bounds.x, 1)  # width=1
	assert_eq(bounds.y, 3)  # height=3


func test_rotate_four_times_returns_original() -> void:
	var shape: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	var current: Array = shape.duplicate()
	for i in 4:
		current = BlockudokuShapes.rotate_clockwise(current)
	var norm_original: Array[Vector2i] = BlockudokuShapes.normalize(shape)
	var norm_rotated: Array[Vector2i] = BlockudokuShapes.normalize(current)
	# Sort both to compare regardless of order
	norm_original.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y * 10 + a.x < b.y * 10 + b.x)
	norm_rotated.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y * 10 + a.x < b.y * 10 + b.x)
	assert_eq(norm_rotated, norm_original)


# --- get_bounds ---

func test_bounds_single_cell() -> void:
	var shape: Array = [Vector2i(0, 0)]
	assert_eq(BlockudokuShapes.get_bounds(shape), Vector2i(1, 1))


func test_bounds_horizontal_line() -> void:
	var shape: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	assert_eq(BlockudokuShapes.get_bounds(shape), Vector2i(3, 1))


func test_bounds_square() -> void:
	var shape: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	assert_eq(BlockudokuShapes.get_bounds(shape), Vector2i(2, 2))


# --- pick_random ---

func test_pick_random_returns_requested_count() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var shapes: Array[Array] = BlockudokuShapes.pick_random(3, rng)
	assert_eq(shapes.size(), 3)


func test_pick_random_shapes_are_nonempty() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100
	var shapes: Array[Array] = BlockudokuShapes.pick_random(3, rng)
	for shape in shapes:
		assert_true(shape.size() > 0)


func test_pick_random_deterministic_with_seed() -> void:
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 42
	var s1: Array[Array] = BlockudokuShapes.pick_random(3, rng1)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var s2: Array[Array] = BlockudokuShapes.pick_random(3, rng2)
	assert_eq(s1.size(), s2.size())
	for i in s1.size():
		assert_eq(s1[i], s2[i])


func test_pick_random_shapes_are_normalized() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var shapes: Array[Array] = BlockudokuShapes.pick_random(5, rng)
	for shape in shapes:
		var normalized: Array[Vector2i] = BlockudokuShapes.normalize(shape)
		# A normalized shape always has min offset at (0,0)
		var has_zero_x := false
		var has_zero_y := false
		for cell in normalized:
			var c: Vector2i = cell
			assert_true(c.x >= 0, "Cell x should be >= 0")
			assert_true(c.y >= 0, "Cell y should be >= 0")
			if c.x == 0:
				has_zero_x = true
			if c.y == 0:
				has_zero_y = true
		assert_true(has_zero_x, "Normalized shape should touch x=0")
		assert_true(has_zero_y, "Normalized shape should touch y=0")


# --- get_all_shapes ---

func test_all_shapes_nonempty() -> void:
	var all: Array[Array] = BlockudokuShapes.get_all_shapes()
	assert_true(all.size() > 0)
	for shape in all:
		assert_true(shape.size() > 0)


func test_all_shapes_contain_standard_set() -> void:
	# Standard shapes include dominoes (size 2) at minimum
	var all: Array[Array] = BlockudokuShapes.get_all_shapes()
	var has_size_2 := false
	for shape in all:
		if shape.size() == 2:
			has_size_2 = true
			break
	assert_true(has_size_2)
