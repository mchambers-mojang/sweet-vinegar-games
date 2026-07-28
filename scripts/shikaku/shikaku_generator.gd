class_name ShikakuGenerator
extends RefCounted

## Generates Shikaku puzzles by building a valid partition then deriving anchor clues.
## Standard mode: area-only anchors.
## Shapes mode: mix of area-only, shape-only, and combined anchors with uniqueness guarantee.

const MIN_AREA := 2
const MAX_AREA := 8


## Generate a puzzle for the given grid size and rule set.
## Returns { "width", "height", "anchors": Dictionary, "solution": Array[Rect2i] }
## anchors: { Vector2i -> {area: int, shape: int} }
##   area == 0 means no area constraint; shape == ShikakuLogic.SHAPE_ABSENT means no shape constraint.
static func generate(width: int, height: int, seed: int = -1, rule_set: int = ShikakuLogic.RULE_SET_STANDARD) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	var solution := _generate_partition(width, height, rng)
	var anchors: Dictionary
	if rule_set == ShikakuLogic.RULE_SET_SHAPES:
		anchors = _derive_shapes_anchors(solution, rng, width, height)
	else:
		anchors = _derive_standard_anchors(solution, rng)
	return {
		"width": width,
		"height": height,
		"anchors": anchors,
		"solution": solution,
	}


## Derive area-only anchors (Standard mode).
static func _derive_standard_anchors(solution: Array[Rect2i], rng: RandomNumberGenerator) -> Dictionary:
	var anchors: Dictionary = {}
	for rect in solution:
		var rect_area := rect.size.x * rect.size.y
		var col := rect.position.x + rng.randi_range(0, rect.size.x - 1)
		var row := rect.position.y + rng.randi_range(0, rect.size.y - 1)
		anchors[Vector2i(col, row)] = {"area": rect_area, "shape": ShikakuLogic.SHAPE_ABSENT}
	return anchors


## Derive generalized anchors for Shapes mode.
## Each anchor gets its rectangle's shape class, then tries to minimize clues while
## preserving a unique solution (area-only, shape-only, or combined).
static func _derive_shapes_anchors(
		solution: Array[Rect2i], rng: RandomNumberGenerator,
		width: int, height: int) -> Dictionary:
	# First pass: assign positions and full area+shape clues.
	var anchor_data: Array[Dictionary] = []
	for rect in solution:
		var rect_area := rect.size.x * rect.size.y
		var rect_shape := _classify_rect_shape(rect)
		var col := rect.position.x + rng.randi_range(0, rect.size.x - 1)
		var row := rect.position.y + rng.randi_range(0, rect.size.y - 1)
		anchor_data.append({
			"pos": Vector2i(col, row),
			"area": rect_area,
			"shape": rect_shape,
		})

	# Shuffle order for diversity in which anchors get minimized.
	_shuffle_array(anchor_data, rng)

	# Build current anchors dict (start: all combined area+shape).
	var anchors: Dictionary = {}
	for d in anchor_data:
		anchors[d["pos"]] = {"area": d["area"], "shape": d["shape"]}

	# Second pass: try to minimize each anchor.
	for d in anchor_data:
		var pos: Vector2i = d["pos"]
		var orig_area: int = d["area"]
		var orig_shape: int = d["shape"]

		# Try shape-only (drop area).
		if orig_shape != ShikakuLogic.SHAPE_ABSENT and orig_shape != ShikakuLogic.SHAPE_ANY:
			var test_anchors := anchors.duplicate()
			test_anchors[pos] = {"area": 0, "shape": orig_shape}
			if ShikakuSolver.count_solutions(width, height, test_anchors, 2) == 1:
				anchors[pos] = {"area": 0, "shape": orig_shape}
				continue

		# Try area-only (drop shape).
		var test_anchors_ao := anchors.duplicate()
		test_anchors_ao[pos] = {"area": orig_area, "shape": ShikakuLogic.SHAPE_ABSENT}
		if ShikakuSolver.count_solutions(width, height, test_anchors_ao, 2) == 1:
			anchors[pos] = {"area": orig_area, "shape": ShikakuLogic.SHAPE_ABSENT}
			continue

		# Keep combined (area + shape).
		anchors[pos] = {"area": orig_area, "shape": orig_shape}

	return anchors


## Classify a rectangle as square, tall, or wide.
static func _classify_rect_shape(rect: Rect2i) -> int:
	if rect.size.x == rect.size.y:
		return ShikakuLogic.SHAPE_SQUARE
	elif rect.size.y > rect.size.x:
		return ShikakuLogic.SHAPE_TALL
	else:
		return ShikakuLogic.SHAPE_WIDE


static func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _generate_partition(width: int, height: int, rng: RandomNumberGenerator) -> Array[Rect2i]:
	for _attempt in range(200):
		var result := _try_partition(width, height, rng)
		if result.size() > 0:
			return result
	return _try_partition(width, height, rng)


static func _try_partition(width: int, height: int, rng: RandomNumberGenerator) -> Array[Rect2i]:
	var covered := PackedByteArray()
	covered.resize(width * height)
	covered.fill(0)
	var rectangles: Array[Rect2i] = []

	while true:
		var start := -1
		for i in covered.size():
			if covered[i] == 0:
				start = i
				break
		if start < 0:
			break

		var start_col := start % width
		var start_row := start / width

		var candidates: Array[Rect2i] = []
		var weights: Array[float] = []
		for w in range(1, width - start_col + 1):
			for h in range(1, height - start_row + 1):
				var area := w * h
				if area < MIN_AREA or area > MAX_AREA:
					continue
				if _rect_fits(start_col, start_row, w, h, width, covered):
					if not _would_isolate(start_col, start_row, w, h, width, height, covered):
						candidates.append(Rect2i(start_col, start_row, w, h))
						weights.append(1.0 / float(area))

		if candidates.is_empty():
			return []

		var rect := _weighted_pick(candidates, weights, rng)
		rectangles.append(rect)

		for r in range(rect.position.y, rect.position.y + rect.size.y):
			for c in range(rect.position.x, rect.position.x + rect.size.x):
				covered[r * width + c] = 1

	return rectangles


static func _would_isolate(col: int, row: int, w: int, h: int, grid_w: int, grid_h: int, covered: PackedByteArray) -> bool:
	var temp := covered.duplicate()
	for r in range(row, row + h):
		for c in range(col, col + w):
			temp[r * grid_w + c] = 1

	var check_min_r := maxi(0, row - 1)
	var check_max_r := mini(grid_h - 1, row + h)
	var check_min_c := maxi(0, col - 1)
	var check_max_c := mini(grid_w - 1, col + w)

	for r in range(check_min_r, check_max_r + 1):
		for c in range(check_min_c, check_max_c + 1):
			if temp[r * grid_w + c] == 0:
				if not _cell_can_pair(c, r, grid_w, grid_h, temp):
					return true
	return false


static func _cell_can_pair(col: int, row: int, grid_w: int, grid_h: int, covered: PackedByteArray) -> bool:
	if col + 1 < grid_w and covered[row * grid_w + col + 1] == 0:
		return true
	if row + 1 < grid_h and covered[(row + 1) * grid_w + col] == 0:
		return true
	if col - 1 >= 0 and covered[row * grid_w + col - 1] == 0:
		return true
	if row - 1 >= 0 and covered[(row - 1) * grid_w + col] == 0:
		return true
	return false


static func _rect_fits(col: int, row: int, w: int, h: int, grid_width: int, covered: PackedByteArray) -> bool:
	for r in range(row, row + h):
		for c in range(col, col + w):
			if covered[r * grid_width + c] != 0:
				return false
	return true


static func _weighted_pick(items: Array[Rect2i], weights: Array[float], rng: RandomNumberGenerator) -> Rect2i:
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	var accum := 0.0
	for i in range(items.size()):
		accum += weights[i]
		if roll <= accum:
			return items[i]
	return items[items.size() - 1]
