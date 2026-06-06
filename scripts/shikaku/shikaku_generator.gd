class_name ShikakuGenerator
extends RefCounted

## Generates Shikaku puzzles by building a valid partition then extracting numbers

const MIN_AREA := 2
const MAX_AREA := 8


## Generate a puzzle for the given grid size
## Returns { "width": int, "height": int, "numbers": Dictionary, "solution": Array[Rect2i] }
## numbers: { Vector2i(col, row) -> area_value }
## solution: Array of Rect2i rectangles covering the grid
static func generate(width: int, height: int, seed: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	var solution := _generate_partition(width, height, rng)
	var numbers := _place_numbers(solution, rng)
	return {
		"width": width,
		"height": height,
		"numbers": numbers,
		"solution": solution,
	}


static func _generate_partition(width: int, height: int, rng: RandomNumberGenerator) -> Array[Rect2i]:
	# Retry from scratch if we paint ourselves into a corner (isolated single cells)
	for _attempt in range(200):
		var result := _try_partition(width, height, rng)
		if result.size() > 0:
			return result
	# Should never reach here, but return whatever we get
	return _try_partition(width, height, rng)


static func _try_partition(width: int, height: int, rng: RandomNumberGenerator) -> Array[Rect2i]:
	var covered := PackedByteArray()
	covered.resize(width * height)
	covered.fill(0)
	var rectangles: Array[Rect2i] = []

	while true:
		# Find first uncovered cell (top-left scan)
		var start := -1
		for i in covered.size():
			if covered[i] == 0:
				start = i
				break
		if start < 0:
			break  # All covered

		var start_col := start % width
		var start_row := start / width

		# Enumerate all valid rectangles starting at this cell
		var candidates: Array[Rect2i] = []
		var weights: Array[float] = []
		for w in range(1, width - start_col + 1):
			for h in range(1, height - start_row + 1):
				var area := w * h
				if area < MIN_AREA or area > MAX_AREA:
					continue
				# Check if all cells in this rectangle are uncovered
				if _rect_fits(start_col, start_row, w, h, width, covered):
					# Also check that this placement won't isolate any single cells
					if not _would_isolate(start_col, start_row, w, h, width, height, covered):
						candidates.append(Rect2i(start_col, start_row, w, h))
						# Weight smaller rectangles more heavily
						weights.append(1.0 / float(area))

		if candidates.is_empty():
			# Can't place anything without isolating — restart
			return []

		# Weighted random selection
		var rect := _weighted_pick(candidates, weights, rng)
		rectangles.append(rect)

		# Mark cells as covered
		for r in range(rect.position.y, rect.position.y + rect.size.y):
			for c in range(rect.position.x, rect.position.x + rect.size.x):
				covered[r * width + c] = 1

	return rectangles


## Check if placing a rectangle would create any isolated single uncovered cells
static func _would_isolate(col: int, row: int, w: int, h: int, grid_w: int, grid_h: int, covered: PackedByteArray) -> bool:
	# Temporarily mark the rectangle as covered
	var temp := covered.duplicate()
	for r in range(row, row + h):
		for c in range(col, col + w):
			temp[r * grid_w + c] = 1

	# Check all uncovered cells adjacent to the placed rect (within a 1-cell border)
	var check_min_r := maxi(0, row - 1)
	var check_max_r := mini(grid_h - 1, row + h)
	var check_min_c := maxi(0, col - 1)
	var check_max_c := mini(grid_w - 1, col + w)

	for r in range(check_min_r, check_max_r + 1):
		for c in range(check_min_c, check_max_c + 1):
			if temp[r * grid_w + c] == 0:
				# This cell is uncovered — check if it can still form a rect of area >= 2
				if not _cell_can_pair(c, r, grid_w, grid_h, temp):
					return true
	return false


## Check whether an uncovered cell can be part of at least one rect of area >= MIN_AREA
static func _cell_can_pair(col: int, row: int, grid_w: int, grid_h: int, covered: PackedByteArray) -> bool:
	# Check 1x2 (horizontal)
	if col + 1 < grid_w and covered[row * grid_w + col + 1] == 0:
		return true
	# Check 2x1 (vertical)
	if row + 1 < grid_h and covered[(row + 1) * grid_w + col] == 0:
		return true
	# Check left neighbor
	if col - 1 >= 0 and covered[row * grid_w + col - 1] == 0:
		return true
	# Check top neighbor
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


static func _place_numbers(solution: Array[Rect2i], rng: RandomNumberGenerator) -> Dictionary:
	var placed_numbers := {}
	for rect in solution:
		var rect_area := rect.size.x * rect.size.y
		# Pick a random cell anywhere inside the rectangle
		var col := rect.position.x + rng.randi_range(0, rect.size.x - 1)
		var row := rect.position.y + rng.randi_range(0, rect.size.y - 1)
		placed_numbers[Vector2i(col, row)] = rect_area
	return placed_numbers
