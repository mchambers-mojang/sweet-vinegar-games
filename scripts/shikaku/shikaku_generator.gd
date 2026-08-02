class_name ShikakuGenerator
extends RefCounted

## Generates Shikaku puzzles by building a valid partition then deriving anchor clues.
## Standard mode: area-only anchors.
## Shapes mode: mix of area-only, shape-only, and combined anchors with uniqueness guarantee.

const MIN_AREA := 2
## Maximum outer attempts to find a human-solvable Shapes puzzle.
const MAX_OUTER_ATTEMPTS := 8
## Maximum attempts to find a uniquely-solvable Standard puzzle.
const MAX_STANDARD_ATTEMPTS := 50


## Size-dependent maximum rectangle area for the partition step.
## Larger grids use larger caps to keep anchor counts manageable: a 15×15 grid
## with MAX_AREA=8 yields ~45 anchors while MAX_AREA=15 gives ~25-28, which
## dramatically reduces is_human_solvable call count and candidate enumeration.
static func max_area_for_size(grid_w: int, grid_h: int) -> int:
	var cells := grid_w * grid_h
	if cells <= 64:   # ≤ 8×8
		return 8
	if cells <= 100:  # 10×10
		return 10
	if cells <= 144:  # 12×12
		return 12
	return 15         # 15×15


## Generate a puzzle for the given grid size and rule set.
## Returns { "width", "height", "anchors": Dictionary, "solution": Array[Rect2i] }
## anchors: { Vector2i -> {area: int, shape: int} }
##   area == 0 means no area constraint; shape == ShikakuLogic.SHAPE_ABSENT means no shape constraint.
##
## Pass [param cancel_check] to abort early (e.g. when the owning scene exits).
## Returns an empty Dictionary if cancelled.
static func generate(width: int, height: int, seed: int = -1, rule_set: int = ShikakuLogic.RULE_SET_STANDARD, cancel_check: Callable = Callable()) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()

	var max_area := max_area_for_size(width, height)

	if rule_set == ShikakuLogic.RULE_SET_SHAPES:
		return _generate_shapes(width, height, rng, cancel_check, max_area)

	# Standard mode: verify uniqueness and human-solvability, retrying until a
	# valid puzzle is found or MAX_STANDARD_ATTEMPTS is exhausted.
	for _attempt in range(MAX_STANDARD_ATTEMPTS):
		if cancel_check.is_valid() and cancel_check.call():
			return {}
		var solution := _generate_partition(width, height, rng, cancel_check, max_area)
		if solution.is_empty():
			if cancel_check.is_valid() and cancel_check.call():
				return {}
			continue
		var anchors := _derive_standard_anchors(solution, rng)
		var n := ShikakuSolver.count_solutions(width, height, anchors, 2, cancel_check, max_area)
		if n == -1:
			return {}
		if n != 1:
			continue
		if not ShikakuSolver.is_human_solvable(width, height, anchors, cancel_check, max_area):
			if cancel_check.is_valid() and cancel_check.call():
				return {}
			continue
		return {
			"width": width,
			"height": height,
			"anchors": anchors,
			"solution": solution,
		}
	return {}


## Generate a Shapes mode puzzle, retrying until the result is uniquely and
## human-solvable (or until MAX_OUTER_ATTEMPTS exhausted).
## Returns {} if all attempts fail or if cancelled.
## Human-solvability is maintained throughout _derive_shapes_anchors (which
## commits each minimization only when it preserves human-solvability), so no
## separate final check is needed.
static func _generate_shapes(width: int, height: int, rng: RandomNumberGenerator, cancel_check: Callable, max_area: int) -> Dictionary:
	for _outer in range(MAX_OUTER_ATTEMPTS):
		if cancel_check.is_valid() and cancel_check.call():
			return {}
		var solution := _generate_partition(width, height, rng, cancel_check, max_area)
		if solution.is_empty():
			if cancel_check.is_valid() and cancel_check.call():
				return {}
			continue
		# _derive_shapes_anchors returns {} when the initial full-clue puzzle is
		# not human-solvable (and therefore cannot be minimised safely), or when cancelled.
		# On success it guarantees the returned anchors dict is human-solvable, which
		# also implies uniqueness (forced placements lead to exactly one solution).
		var anchors := _derive_shapes_anchors(solution, rng, width, height, cancel_check, max_area)
		if anchors.is_empty():
			if cancel_check.is_valid() and cancel_check.call():
				return {}
			continue
		return {
			"width": width,
			"height": height,
			"anchors": anchors,
			"solution": solution,
		}
	# All attempts exhausted without a human-solvable uniquely-solvable puzzle.
	return {}


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
## preserving human-solvability (which implies a unique solution).
## Using is_human_solvable (O(linear propagation)) instead of count_solutions
## (O(exponential backtracking)) for each minimization step keeps generation fast.
## [param max_area] is passed as max_area_hint to is_human_solvable so that
## unconstrained-anchor candidate enumeration is capped at the partition's
## maximum rectangle area — dramatically reducing per-call cost on large grids.
## Returns {} if the initial full-clue puzzle is not human-solvable, or if cancelled.
static func _derive_shapes_anchors(
		solution: Array[Rect2i], rng: RandomNumberGenerator,
		width: int, height: int, cancel_check: Callable = Callable(),
		max_area: int = 8) -> Dictionary:
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

	# Verify that the initial full-clue puzzle is human-solvable.
	# Human-solvability implies uniqueness (forced placements yield exactly one
	# solution), so this replaces the expensive count_solutions initial check.
	# If the initial combined puzzle is not human-solvable, reject this partition.
	if not ShikakuSolver.is_human_solvable(width, height, anchors, cancel_check, max_area):
		return {}

	# Second pass: try to minimize each anchor.
	# Commit a minimization only when the resulting puzzle remains human-solvable.
	# Because each committed step is verified, the final anchors dict is
	# guaranteed to be human-solvable (and therefore uniquely solvable) by induction.
	for d in anchor_data:
		if cancel_check.is_valid() and cancel_check.call():
			return {}
		var pos: Vector2i = d["pos"]
		var orig_area: int = d["area"]
		var orig_shape: int = d["shape"]

		# Try shape-only (drop area).
		if orig_shape != ShikakuLogic.SHAPE_ABSENT and orig_shape != ShikakuLogic.SHAPE_ANY:
			var test_anchors := anchors.duplicate()
			test_anchors[pos] = {"area": 0, "shape": orig_shape}
			if ShikakuSolver.is_human_solvable(width, height, test_anchors, cancel_check, max_area):
				anchors[pos] = {"area": 0, "shape": orig_shape}
				continue

		# Try area-only (drop shape).
		var test_anchors_ao := anchors.duplicate()
		test_anchors_ao[pos] = {"area": orig_area, "shape": ShikakuLogic.SHAPE_ABSENT}
		if ShikakuSolver.is_human_solvable(width, height, test_anchors_ao, cancel_check, max_area):
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


static func _generate_partition(width: int, height: int, rng: RandomNumberGenerator, cancel_check: Callable = Callable(), max_area: int = 8) -> Array[Rect2i]:
	for _attempt in range(200):
		if cancel_check.is_valid() and cancel_check.call():
			return []
		var result := _try_partition(width, height, rng, cancel_check, max_area)
		if result.size() > 0:
			return result
	return _try_partition(width, height, rng, cancel_check, max_area)


static func _try_partition(width: int, height: int, rng: RandomNumberGenerator, cancel_check: Callable = Callable(), max_area: int = 8) -> Array[Rect2i]:
	var do_cancel := cancel_check.is_valid()
	var covered := PackedByteArray()
	covered.resize(width * height)
	covered.fill(0)
	var rectangles: Array[Rect2i] = []

	while true:
		if do_cancel and cancel_check.call():
			return []
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
				if area < MIN_AREA or area > max_area:
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
