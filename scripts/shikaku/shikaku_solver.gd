class_name ShikakuSolver
extends RefCounted

## Validates player solutions and solves puzzles for hints


## Check if a set of rectangles is a valid solution for the given puzzle
## numbers: { Vector2i -> int }
## rectangles: Array[Rect2i]
static func validate(width: int, height: int, numbers: Dictionary, rectangles: Array[Rect2i]) -> bool:
	# Check: every cell is covered exactly once
	var coverage := PackedByteArray()
	coverage.resize(width * height)
	coverage.fill(0)

	for rect in rectangles:
		# Bounds check
		if rect.position.x < 0 or rect.position.y < 0:
			return false
		if rect.position.x + rect.size.x > width or rect.position.y + rect.size.y > height:
			return false

		var area := rect.size.x * rect.size.y

		# Check: rectangle contains exactly one number and it equals the area
		var found_number := false
		for r in range(rect.position.y, rect.position.y + rect.size.y):
			for c in range(rect.position.x, rect.position.x + rect.size.x):
				var idx := r * width + c
				if coverage[idx] != 0:
					return false  # Overlap
				coverage[idx] = 1

				var pos := Vector2i(c, r)
				if numbers.has(pos):
					if found_number:
						return false  # Two numbers in one rectangle
					if numbers[pos] != area:
						return false  # Number doesn't match area
					found_number = true

		if not found_number:
			return false  # Rectangle has no number

	# Check all cells covered
	for i in coverage.size():
		if coverage[i] == 0:
			return false

	return true


## Solve the puzzle and return a valid solution, or empty array if unsolvable
## Uses backtracking with constraint propagation
static func solve(width: int, height: int, numbers: Dictionary) -> Array[Rect2i]:
	var covered := PackedByteArray()
	covered.resize(width * height)
	covered.fill(0)

	# Convert number positions to an array for ordering
	var num_entries: Array[Dictionary] = []
	for pos in numbers.keys():
		num_entries.append({"pos": pos, "area": numbers[pos]})

	# Sort by area (smaller first = more constrained = faster pruning)
	num_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["area"] < b["area"]
	)

	var result: Array[Rect2i] = []
	if _backtrack(width, height, num_entries, 0, covered, result):
		return result
	return []


static func _backtrack(width: int, height: int, entries: Array[Dictionary], idx: int, covered: PackedByteArray, result: Array[Rect2i]) -> bool:
	if idx >= entries.size():
		# All numbers placed — check if fully covered
		for i in covered.size():
			if covered[i] == 0:
				return false
		return true

	var entry := entries[idx]
	var pos: Vector2i = entry["pos"]
	var area: int = entry["area"]

	# Skip if this cell is already covered by a previous rectangle
	if covered[pos.y * width + pos.x] != 0:
		return _backtrack(width, height, entries, idx + 1, covered, result)

	# Enumerate all rectangles of the correct area that contain this number's position
	var rects := _enumerate_rects_containing(pos, area, width, height, covered)

	for rect in rects:
		# Place rectangle
		_mark_covered(rect, width, covered, 1)
		result.append(rect)

		# Check: no other number in this rectangle (besides the current one)
		var conflict := false
		for e_idx in range(entries.size()):
			if e_idx == idx:
				continue
			var other_pos: Vector2i = entries[e_idx]["pos"]
			if rect.has_point(other_pos):
				conflict = true
				break

		if not conflict:
			if _backtrack(width, height, entries, idx + 1, covered, result):
				return true

		# Undo
		result.pop_back()
		_mark_covered(rect, width, covered, 0)

	return false


static func _enumerate_rects_containing(pos: Vector2i, area: int, width: int, height: int, covered: PackedByteArray) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []

	# Find all (w, h) factor pairs of area
	for w in range(1, area + 1):
		if area % w != 0:
			continue
		var h := area / w

		# Find all positions where a w×h rect contains pos
		var min_col := maxi(0, pos.x - w + 1)
		var max_col := mini(width - w, pos.x)
		var min_row := maxi(0, pos.y - h + 1)
		var max_row := mini(height - h, pos.y)

		for r in range(min_row, max_row + 1):
			for c in range(min_col, max_col + 1):
				var rect := Rect2i(c, r, w, h)
				if _rect_is_clear(rect, width, covered):
					rects.append(rect)

	return rects


static func _rect_is_clear(rect: Rect2i, width: int, covered: PackedByteArray) -> bool:
	for r in range(rect.position.y, rect.position.y + rect.size.y):
		for c in range(rect.position.x, rect.position.x + rect.size.x):
			if covered[r * width + c] != 0:
				return false
	return true


static func _mark_covered(rect: Rect2i, width: int, covered: PackedByteArray, val: int) -> void:
	for r in range(rect.position.y, rect.position.y + rect.size.y):
		for c in range(rect.position.x, rect.position.x + rect.size.x):
			covered[r * width + c] = val
