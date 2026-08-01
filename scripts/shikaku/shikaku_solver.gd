class_name ShikakuSolver
extends RefCounted

## Validates player solutions and solves puzzles for hints.
## Supports both area-only anchors (Standard mode) and generalized
## anchor clues with optional area and/or shape constraints (Shapes mode).


## Check if a set of rectangles is a valid solution for the given puzzle.
## anchors: { Vector2i -> {area: int, shape: int} }
## area == 0 means no area constraint; shape == SHAPE_ABSENT means no shape constraint.
static func validate_anchors(width: int, height: int, anchors: Dictionary, rectangles: Array[Rect2i]) -> bool:
	var coverage := PackedByteArray()
	coverage.resize(width * height)
	coverage.fill(0)

	for rect in rectangles:
		if rect.position.x < 0 or rect.position.y < 0:
			return false
		if rect.position.x + rect.size.x > width or rect.position.y + rect.size.y > height:
			return false

		var rect_area := rect.size.x * rect.size.y
		var found_anchor := false
		for r in range(rect.position.y, rect.position.y + rect.size.y):
			for c in range(rect.position.x, rect.position.x + rect.size.x):
				var idx := r * width + c
				if coverage[idx] != 0:
					return false
				coverage[idx] = 1
				var pos := Vector2i(c, r)
				if anchors.has(pos):
					if found_anchor:
						return false
					found_anchor = true
					var anchor: Dictionary = anchors[pos]
					var anchor_area: int = int(anchor.get("area", 0))
					var anchor_shape: int = int(anchor.get("shape", ShikakuLogic.SHAPE_ABSENT))
					if anchor_area > 0 and anchor_area != rect_area:
						return false
					if not _shape_matches(rect.size.x, rect.size.y, anchor_shape):
						return false
		if not found_anchor:
			return false

	for i in coverage.size():
		if coverage[i] == 0:
			return false

	return true


## Legacy backward-compatible validate using a numbers dict { Vector2i -> int }.
static func validate(width: int, height: int, numbers: Dictionary, rectangles: Array[Rect2i]) -> bool:
	var anchors: Dictionary = {}
	for pos in numbers.keys():
		anchors[pos] = {"area": int(numbers[pos]), "shape": ShikakuLogic.SHAPE_ABSENT}
	return validate_anchors(width, height, anchors, rectangles)


## Solve the puzzle and return one valid solution, or empty array if unsolvable.
## anchors: { Vector2i -> {area: int, shape: int} }
## Pass [param cancel_check] to abort early; returns [] if cancelled.
static func solve_with_anchors(width: int, height: int, anchors: Dictionary, cancel_check: Callable = Callable()) -> Array[Rect2i]:
	var covered := PackedByteArray()
	covered.resize(width * height)
	covered.fill(0)

	var entries: Array[Dictionary] = _build_entries(anchors)
	var result: Array[Rect2i] = []
	if _backtrack(width, height, entries, 0, covered, result, cancel_check, cancel_check.is_valid()):
		return result
	return []


## Backward-compatible solve using a numbers dict { Vector2i -> int }.
static func solve(width: int, height: int, numbers: Dictionary) -> Array[Rect2i]:
	var anchors: Dictionary = {}
	for pos in numbers.keys():
		anchors[pos] = {"area": int(numbers[pos]), "shape": ShikakuLogic.SHAPE_ABSENT}
	return solve_with_anchors(width, height, anchors)


## Count the number of valid solutions (up to max_count).
## Returns early once max_count solutions are found.
## anchors: { Vector2i -> {area: int, shape: int} }
## Pass [param cancel_check] to abort early; returns -1 if cancelled.
static func count_solutions(width: int, height: int, anchors: Dictionary, max_count: int = 2, cancel_check: Callable = Callable()) -> int:
	var covered := PackedByteArray()
	covered.resize(width * height)
	covered.fill(0)
	var entries: Array[Dictionary] = _build_entries(anchors)
	var count := [0]
	var cancelled := [false]
	_count_backtrack(width, height, entries, 0, covered, count, max_count, cancel_check, cancel_check.is_valid(), cancelled)
	if cancelled[0]:
		return -1
	return count[0]


## Check whether the puzzle can be solved by forced-placement logic alone
## (no backtracking / guessing). Returns true if every anchor can be resolved
## to a unique valid rectangle given successive placements.
## A rectangle is valid only if it covers no other unplaced anchor, matching the
## constraint used in the backtracking solver.
static func is_human_solvable(width: int, height: int, anchors: Dictionary) -> bool:
	var covered := PackedByteArray()
	covered.resize(width * height)
	covered.fill(0)
	var entries: Array[Dictionary] = _build_entries(anchors)
	var placed := PackedByteArray()
	placed.resize(entries.size())
	placed.fill(0)

	var changed := true
	while changed:
		changed = false
		for i in range(entries.size()):
			if placed[i] != 0:
				continue
			var pos: Vector2i = entries[i]["pos"]
			var all_rects := _enumerate_rects_for_anchor(pos, entries[i]["anchor"], width, height, covered)
			# Filter out rects that would capture another unplaced anchor.
			var valid_rects: Array[Rect2i] = []
			for rect in all_rects:
				var conflict := false
				for j in range(entries.size()):
					if j == i or placed[j] != 0:
						continue
					if rect.has_point(entries[j]["pos"] as Vector2i):
						conflict = true
						break
				if not conflict:
					valid_rects.append(rect)
			if valid_rects.size() == 1:
				_mark_covered(valid_rects[0], width, covered, 1)
				placed[i] = 1
				changed = true
			elif valid_rects.is_empty():
				return false

	for i in range(placed.size()):
		if placed[i] == 0:
			return false
	return true


## Build sorted entry list from anchors dict for backtracking.
static func _build_entries(anchors: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for pos in anchors.keys():
		var anchor: Dictionary = anchors[pos]
		entries.append({"pos": pos, "anchor": anchor})
	# Sort: area-constrained first (more constrained = faster pruning),
	# then shape-constrained, then unconstrained.
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var aa: Dictionary = a["anchor"]
		var ba: Dictionary = b["anchor"]
		var a_area: int = int(aa.get("area", 0))
		var b_area: int = int(ba.get("area", 0))
		var a_shape: int = int(aa.get("shape", ShikakuLogic.SHAPE_ABSENT))
		var b_shape: int = int(ba.get("shape", ShikakuLogic.SHAPE_ABSENT))
		var a_score: int = (1 if a_area > 0 else 0) + (1 if a_shape > ShikakuLogic.SHAPE_ABSENT else 0)
		var b_score: int = (1 if b_area > 0 else 0) + (1 if b_shape > ShikakuLogic.SHAPE_ABSENT else 0)
		if a_score != b_score:
			return a_score > b_score
		if a_area > 0 and b_area > 0:
			return a_area < b_area
		return false
	)
	return entries


static func _backtrack(
		width: int, height: int, entries: Array[Dictionary],
		idx: int, covered: PackedByteArray, result: Array[Rect2i],
		cancel_check: Callable, do_cancel: bool) -> bool:
	if do_cancel and cancel_check.call():
		return false

	if idx >= entries.size():
		for i in covered.size():
			if covered[i] == 0:
				return false
		return true

	var entry := entries[idx]
	var pos: Vector2i = entry["pos"]
	var anchor: Dictionary = entry["anchor"]

	if covered[pos.y * width + pos.x] != 0:
		return _backtrack(width, height, entries, idx + 1, covered, result, cancel_check, do_cancel)

	var rects := _enumerate_rects_for_anchor(pos, anchor, width, height, covered)

	for rect in rects:
		_mark_covered(rect, width, covered, 1)
		result.append(rect)

		var conflict := false
		for e_idx in range(entries.size()):
			if e_idx == idx:
				continue
			var other_pos: Vector2i = entries[e_idx]["pos"]
			if rect.has_point(other_pos):
				conflict = true
				break

		if not conflict:
			if _backtrack(width, height, entries, idx + 1, covered, result, cancel_check, do_cancel):
				return true

		result.pop_back()
		_mark_covered(rect, width, covered, 0)

	return false


static func _count_backtrack(
		width: int, height: int, entries: Array[Dictionary],
		idx: int, covered: PackedByteArray, count: Array, max_count: int,
		cancel_check: Callable, do_cancel: bool, cancelled: Array) -> void:
	if count[0] >= max_count:
		return
	if do_cancel and cancel_check.call():
		cancelled[0] = true
		return

	if idx >= entries.size():
		for i in covered.size():
			if covered[i] == 0:
				return
		count[0] += 1
		return

	var entry := entries[idx]
	var pos: Vector2i = entry["pos"]
	var anchor: Dictionary = entry["anchor"]

	if covered[pos.y * width + pos.x] != 0:
		_count_backtrack(width, height, entries, idx + 1, covered, count, max_count, cancel_check, do_cancel, cancelled)
		return

	var rects := _enumerate_rects_for_anchor(pos, anchor, width, height, covered)

	for rect in rects:
		if count[0] >= max_count or cancelled[0]:
			return
		_mark_covered(rect, width, covered, 1)

		var conflict := false
		for e_idx in range(entries.size()):
			if e_idx == idx:
				continue
			var other_pos: Vector2i = entries[e_idx]["pos"]
			if rect.has_point(other_pos):
				conflict = true
				break

		if not conflict:
			_count_backtrack(width, height, entries, idx + 1, covered, count, max_count, cancel_check, do_cancel, cancelled)

		_mark_covered(rect, width, covered, 0)


## Enumerate all candidate rectangles for a given anchor position and clue.
static func _enumerate_rects_for_anchor(
		pos: Vector2i, anchor: Dictionary,
		width: int, height: int, covered: PackedByteArray) -> Array[Rect2i]:
	var anchor_area: int = int(anchor.get("area", 0))
	var anchor_shape: int = int(anchor.get("shape", ShikakuLogic.SHAPE_ABSENT))
	var rects: Array[Rect2i] = []

	if anchor_area > 0:
		# Area-constrained: enumerate all (w,h) factor pairs of that area.
		for w in range(1, anchor_area + 1):
			if anchor_area % w != 0:
				continue
			var h := anchor_area / w
			if not _shape_matches(w, h, anchor_shape):
				continue
			_collect_rects_containing(pos, w, h, width, height, covered, rects)
	else:
		# No area constraint: enumerate all (w,h) pairs that fit in the grid.
		# This must be exhaustive (no area cap) to ensure sound uniqueness checks.
		for w in range(1, width + 1):
			for h in range(1, height + 1):
				if not _shape_matches(w, h, anchor_shape):
					continue
				_collect_rects_containing(pos, w, h, width, height, covered, rects)

	return rects


static func _collect_rects_containing(
		pos: Vector2i, w: int, h: int,
		width: int, height: int, covered: PackedByteArray,
		out: Array[Rect2i]) -> void:
	var min_col := maxi(0, pos.x - w + 1)
	var max_col := mini(width - w, pos.x)
	var min_row := maxi(0, pos.y - h + 1)
	var max_row := mini(height - h, pos.y)
	for r in range(min_row, max_row + 1):
		for c in range(min_col, max_col + 1):
			var rect := Rect2i(c, r, w, h)
			if _rect_is_clear(rect, width, covered):
				out.append(rect)


## True when a w×h rectangle satisfies the given shape constraint.
static func _shape_matches(w: int, h: int, shape: int) -> bool:
	match shape:
		ShikakuLogic.SHAPE_ABSENT, ShikakuLogic.SHAPE_ANY:
			return true
		ShikakuLogic.SHAPE_SQUARE:
			return w == h
		ShikakuLogic.SHAPE_TALL:
			return h > w
		ShikakuLogic.SHAPE_WIDE:
			return w > h
	return false


## Enumerate rectangles of exact area containing pos (backward-compat helper).
static func _enumerate_rects_containing(pos: Vector2i, area: int, width: int, height: int, covered: PackedByteArray) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for w in range(1, area + 1):
		if area % w != 0:
			continue
		var h := area / w
		_collect_rects_containing(pos, w, h, width, height, covered, rects)
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
