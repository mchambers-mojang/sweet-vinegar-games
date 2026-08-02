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
	# Pre-compute all candidate rectangles on the empty grid once, then reuse
	# them throughout the backtracker by filtering with _rect_is_clear.  This
	# avoids re-enumerating (w,h) pairs at every node — critical for shape-only
	# anchors with many candidates on large grids.
	# Also use the candidate count as the MRV key for static root ordering.
	var do_cancel_mrv := cancel_check.is_valid()
	for entry in entries:
		if do_cancel_mrv and cancel_check.call():
			return -1
		var cands := _enumerate_rects_for_anchor_empty(entry["pos"], entry["anchor"], width, height)
		if do_cancel_mrv and cancel_check.call():
			return -1
		entry["_base_cands"] = cands
		entry["_mrv"] = cands.size()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("_mrv", 9999)) < int(b.get("_mrv", 9999))
	)
	var count := [0]
	var cancelled := [false]
	_count_backtrack(width, height, entries, 0, covered, count, max_count, cancel_check, cancel_check.is_valid(), cancelled)
	if cancelled[0]:
		return -1
	return count[0]


## Check whether the puzzle can be solved by human-style deduction alone
## (no backtracking / guessing). Uses two propagation passes per iteration:
##
## Phase 1 — Forced single candidate: if an anchor has exactly one valid
## rectangle (given already-placed rects and other unplaced anchors), place it.
##
## Phase 2 — Cell-ownership elimination: for each uncovered cell, compute which
## distinct anchors have at least one valid candidate containing that cell. If
## only one anchor can cover a cell, restrict that anchor's candidates to those
## containing the cell.  When this yields a single candidate, place it; when it
## yields >1 candidates, record the required cell in the entry so subsequent
## Phase 1 passes can use the narrowed candidate set.
##
## Candidates for every anchor are pre-computed once on the empty grid
## (_enumerate_rects_for_anchor_empty, no coverage check) and then filtered by
## current coverage each iteration — a significant speedup for shape-only anchors
## on large grids.  The empty-grid pre-computation itself is fast because it
## skips the per-placement _rect_is_clear scan.
## Returns false when cancelled (conservative: treated as not human-solvable).
static func is_human_solvable(width: int, height: int, anchors: Dictionary, cancel_check: Callable = Callable()) -> bool:
	var do_cancel := cancel_check.is_valid()
	var entries: Array[Dictionary] = _build_entries(anchors)
	# Pre-compute on empty grid using the fast (no _rect_is_clear) variant.
	var base_candidates: Array = []
	for i in range(entries.size()):
		if do_cancel and cancel_check.call():
			return false
		base_candidates.append(_enumerate_rects_for_anchor_empty(
			entries[i]["pos"], entries[i]["anchor"], width, height))
	return _is_human_solvable_from_entries(width, height, entries, base_candidates, cancel_check)


## Internal variant of is_human_solvable that accepts pre-computed base_candidates
## so the expensive empty-grid enumeration phase can be shared across many calls.
## [param entries] must be a parallel array to [param base_candidates] with the
## same ordering; both are treated as read-only — propagation state is kept in
## local work copies so successive calls with the same arrays are independent.
## Intended for the generator's per-anchor minimisation loop, which calls
## is_human_solvable dozens of times with only one anchor changed each call.
##
## Performance notes:
## - anchor_at is maintained incrementally (cleared when an anchor is placed)
##   instead of rebuilt from scratch each while-loop pass.
## - uncovered_count, fixed_area_remaining, unconstrained_count are tracked
##   incrementally so area_limit can be re-derived after every placement.
## - area_limit is a sound upper bound on any unconstrained anchor's area:
##   uncovered − fixed_area_remaining − (other_unconstrained_count).
##   base_candidates for unconstrained anchors are sorted by area ascending
##   (see _enumerate_rects_for_anchor_empty), so iterating up to area_limit
##   and breaking early can reduce candidate work by orders of magnitude.
## - Phase 2 uses PackedInt32Array (direct index) instead of Dictionary to
##   avoid GDScript hash overhead; valid_rects per anchor are cached once and
##   reused in the second-pass restriction step.
static func _is_human_solvable_from_entries(
		width: int, height: int,
		entries: Array[Dictionary],
		base_candidates: Array,
		cancel_check: Callable = Callable()) -> bool:
	var do_cancel := cancel_check.is_valid()
	var covered := PackedByteArray()
	covered.resize(width * height)
	covered.fill(0)
	var n := entries.size()
	var placed := PackedByteArray()
	placed.resize(n)
	placed.fill(0)
	# Work entries: local copy so required_cells do not bleed between calls.
	var work_entries: Array[Dictionary] = []
	for e in entries:
		work_entries.append({"pos": e["pos"], "anchor": e["anchor"]})

	# --- Incremental bookkeeping (avoids full scan on each while-loop pass) ---
	# anchor_at: 1 for cells that have an unplaced anchor; cleared when placed.
	var anchor_at := PackedByteArray()
	anchor_at.resize(width * height)
	anchor_at.fill(0)
	# Per-anchor area and constrained flag for O(1) lookup.
	var anchor_areas := PackedInt32Array()
	anchor_areas.resize(n)
	var unconstrained_flags := PackedByteArray()
	unconstrained_flags.resize(n)
	var uncovered_count := width * height
	var fixed_area_remaining := 0
	var unconstrained_count := 0
	for j in range(n):
		var ap: Vector2i = work_entries[j]["pos"]
		anchor_at[ap.y * width + ap.x] = 1
		var j_area: int = int(work_entries[j]["anchor"].get("area", 0))
		anchor_areas[j] = j_area
		if j_area > 0:
			fixed_area_remaining += j_area
			unconstrained_flags[j] = 0
		else:
			unconstrained_count += 1
			unconstrained_flags[j] = 1

	var changed := true
	while changed:
		if do_cancel and cancel_check.call():
			return false
		changed = false

		# Sound upper bound on area for any single unconstrained anchor.
		# In any valid complete tiling, fixed-area anchors consume exactly
		# fixed_area_remaining cells and each of the other unconstrained anchors
		# needs ≥ 1 cell, so the current one covers at most the remainder.
		# Because base_candidates for unconstrained anchors are area-ascending,
		# we can break early when this limit is exceeded.
		var area_limit := uncovered_count - fixed_area_remaining - maxi(0, unconstrained_count - 1)

		# ------------------------------------------------------------------
		# Phase 1: Forced single candidate
		# Combined coverage + anchor_at filter in a single pass to avoid the
		# intermediate all_rects allocation used in the previous implementation.
		# ------------------------------------------------------------------
		for i in range(n):
			if placed[i] != 0:
				continue
			var pos: Vector2i = work_entries[i]["pos"]
			var is_unc: bool = unconstrained_flags[i] != 0
			var valid_rects: Array[Rect2i] = []
			for rect in base_candidates[i]:
				if is_unc and rect.size.x * rect.size.y > area_limit:
					break  # base_candidates sorted by area asc for unconstrained
				if not _rect_is_clear(rect, width, covered):
					continue
				if not _passes_anchor_at(rect, pos, anchor_at, width):
					continue
				valid_rects.append(rect)
			if valid_rects.is_empty() and do_cancel and cancel_check.call():
				return false
			valid_rects = _apply_required_cells(valid_rects, work_entries[i])
			if valid_rects.size() == 1:
				var placed_rect := valid_rects[0]
				_mark_covered(placed_rect, width, covered, 1)
				placed[i] = 1
				# Update incremental bookkeeping.
				var rect_area := placed_rect.size.x * placed_rect.size.y
				uncovered_count -= rect_area
				if is_unc:
					unconstrained_count -= 1
				else:
					fixed_area_remaining -= anchor_areas[i]
				anchor_at[pos.y * width + pos.x] = 0
				area_limit = uncovered_count - fixed_area_remaining - maxi(0, unconstrained_count - 1)
				changed = true
			elif valid_rects.is_empty():
				return false

		if changed:
			continue

		# ------------------------------------------------------------------
		# Phase 2: Cell-ownership elimination
		# owner_map: flat PackedInt32Array indexed by cell.
		#   -1 = no unplaced anchor candidate reaches this cell
		#    k = unique anchor index (0..n-1) can cover this cell
		#   -2 = multiple anchors can cover this cell
		# Avoids GDScript Dictionary/hash overhead on the inner cell loop.
		# ------------------------------------------------------------------
		var owner_map := PackedInt32Array()
		owner_map.resize(width * height)
		owner_map.fill(-1)

		for i in range(n):
			if placed[i] != 0:
				continue
			var pos: Vector2i = work_entries[i]["pos"]
			var is_unc: bool = unconstrained_flags[i] != 0
			var valid_rects: Array[Rect2i] = []
			for rect in base_candidates[i]:
				if is_unc and rect.size.x * rect.size.y > area_limit:
					break
				if not _rect_is_clear(rect, width, covered):
					continue
				if not _passes_anchor_at(rect, pos, anchor_at, width):
					continue
				valid_rects.append(rect)
			if do_cancel and cancel_check.call():
				return false
			valid_rects = _apply_required_cells(valid_rects, work_entries[i])
			for rect in valid_rects:
				for r in range(rect.position.y, rect.position.y + rect.size.y):
					for c in range(rect.position.x, rect.position.x + rect.size.x):
						var idx := r * width + c
						if covered[idx] != 0:
							continue
						# Deduplicate: record each distinct anchor index at most once.
						var cur := owner_map[idx]
						if cur == -1:
							owner_map[idx] = i
						elif cur != i:
							owner_map[idx] = -2  # multiple owners

		# For each cell with a unique owner, restrict that anchor's candidates.
		# Re-filter from base_candidates (with updated required_cells) so any
		# constraints added earlier in this second pass are reflected.
		for cell_idx in range(owner_map.size()):
			if covered[cell_idx] != 0:
				continue
			var owner_idx := owner_map[cell_idx]
			if owner_idx < 0:
				continue  # -1 (none) or -2 (multiple owners)
			if placed[owner_idx] != 0:
				continue
			var cell := Vector2i(cell_idx % width, cell_idx / width)
			var opos: Vector2i = work_entries[owner_idx]["pos"]
			var is_unc_o: bool = unconstrained_flags[owner_idx] != 0
			var valid_rects: Array[Rect2i] = []
			for rect in base_candidates[owner_idx]:
				if is_unc_o and rect.size.x * rect.size.y > area_limit:
					break
				if not _rect_is_clear(rect, width, covered):
					continue
				if not _passes_anchor_at(rect, opos, anchor_at, width):
					continue
				valid_rects.append(rect)
			valid_rects = _apply_required_cells(valid_rects, work_entries[owner_idx])
			# Keep only candidates that contain the uniquely-owned cell.
			var restricted: Array[Rect2i] = []
			for rect in valid_rects:
				if rect.has_point(cell):
					restricted.append(rect)
			if restricted.size() == 1:
				_mark_covered(restricted[0], width, covered, 1)
				placed[owner_idx] = 1
				var rect_area := restricted[0].size.x * restricted[0].size.y
				uncovered_count -= rect_area
				if is_unc_o:
					unconstrained_count -= 1
				else:
					fixed_area_remaining -= anchor_areas[owner_idx]
				anchor_at[opos.y * width + opos.x] = 0
				area_limit = uncovered_count - fixed_area_remaining - maxi(0, unconstrained_count - 1)
				changed = true
			elif restricted.size() > 1:
				# Cannot place yet, but record that this anchor must cover
				# this cell so Phase 1 can use the narrowed candidate set.
				if not work_entries[owner_idx].has("required_cells"):
					work_entries[owner_idx]["required_cells"] = []
				var req: Array = work_entries[owner_idx]["required_cells"] as Array
				if not req.has(cell):
					req.append(cell)
					changed = true
			elif restricted.is_empty():
				return false

	for i in range(placed.size()):
		if placed[i] == 0:
			return false
	# Verify every grid cell is covered by a placed rectangle.  All anchors
	# being placed is necessary but not sufficient — an area-1 anchor in a
	# larger region would leave uncovered cells.
	for i in covered.size():
		if covered[i] == 0:
			return false
	return true


## Filter [param rects] to those containing every cell in [param entry]'s
## "required_cells" list.  Returns [param rects] unchanged when the list is empty.
static func _apply_required_cells(rects: Array[Rect2i], entry: Dictionary) -> Array[Rect2i]:
	var req_cells: Array = entry.get("required_cells", [])
	if req_cells.is_empty():
		return rects
	var filtered: Array[Rect2i] = []
	for rect in rects:
		var ok := true
		for cell in req_cells:
			if not rect.has_point(cell as Vector2i):
				ok = false
				break
		if ok:
			filtered.append(rect)
	return filtered


## Single-rect variant of _filter_with_anchor_at: returns true when [param rect]
## does not contain any unplaced anchor other than [param self_pos].
## Used by _is_human_solvable_from_entries for a combined filter pass that
## avoids allocating the intermediate all_rects array.
static func _passes_anchor_at(rect: Rect2i, self_pos: Vector2i, anchor_at: PackedByteArray, grid_width: int) -> bool:
	for r in range(rect.position.y, rect.position.y + rect.size.y):
		for c in range(rect.position.x, rect.position.x + rect.size.x):
			if c == self_pos.x and r == self_pos.y:
				continue  # own anchor cell — never a conflict
			if anchor_at[r * grid_width + c] != 0:
				return false
	return true


## Fast O(n_rects × avg_rect_area) filter: reject any rect that covers another
## unplaced anchor's position, using the precomputed [param anchor_at] bitmask
## (1 = an unplaced anchor is at that cell, 0 = free).  [param self_pos] is the
## anchor being placed, so its cell is always allowed inside the candidate rect.
## Placed anchors' cells are covered and never appear in candidates generated by
## _collect_rects_containing, so they do not need to be excluded here.
static func _filter_with_anchor_at(
		rects: Array[Rect2i], self_pos: Vector2i,
		anchor_at: PackedByteArray, grid_width: int) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for rect in rects:
		var ok := true
		for r in range(rect.position.y, rect.position.y + rect.size.y):
			for c in range(rect.position.x, rect.position.x + rect.size.x):
				if c == self_pos.x and r == self_pos.y:
					continue  # own anchor cell — never a conflict
				if anchor_at[r * grid_width + c] != 0:
					ok = false
					break
			if not ok:
				break
		if ok:
			result.append(rect)
	return result


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


## Filter candidate rectangles for anchor [param idx]: remove any that would
## capture another unplaced anchor's position.
static func _filter_anchor_candidates(
		rects: Array[Rect2i], idx: int,
		entries: Array[Dictionary], placed: PackedByteArray) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for rect in rects:
		var conflict := false
		for j in range(entries.size()):
			if j == idx or placed[j] != 0:
				continue
			if rect.has_point(entries[j]["pos"] as Vector2i):
				conflict = true
				break
		if not conflict:
			result.append(rect)
	return result


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

	var rects := _enumerate_rects_for_anchor(pos, anchor, width, height, covered, cancel_check)

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

	if covered[pos.y * width + pos.x] != 0:
		_count_backtrack(width, height, entries, idx + 1, covered, count, max_count, cancel_check, do_cancel, cancelled)
		return

	# Filter pre-computed candidates by current coverage.  Pre-computed on empty
	# grid, so _rect_is_clear is the only filter needed here — conflict checking
	# is handled by the anchor_at bitmask below.
	var rects: Array[Rect2i] = []
	for rect in entry.get("_base_cands", []):
		if _rect_is_clear(rect, width, covered):
			rects.append(rect)
	if do_cancel and cancel_check.call():
		cancelled[0] = true
		return

	# Build anchor_at bitmask for unplaced (uncovered) anchors.  Using a bitmask
	# reduces conflict checking from O(n_entries) per candidate to O(rect_area).
	var anchor_at := PackedByteArray()
	anchor_at.resize(width * height)
	anchor_at.fill(0)
	for e_idx in range(entries.size()):
		if e_idx == idx:
			continue
		var ep: Vector2i = entries[e_idx]["pos"]
		if covered[ep.y * width + ep.x] == 0:
			anchor_at[ep.y * width + ep.x] = 1

	for rect in rects:
		if count[0] >= max_count or cancelled[0]:
			return
		_mark_covered(rect, width, covered, 1)

		# Check conflict: does this rect contain another unplaced anchor?
		var conflict := false
		for r in range(rect.position.y, rect.position.y + rect.size.y):
			for c in range(rect.position.x, rect.position.x + rect.size.x):
				if c == pos.x and r == pos.y:
					continue  # own anchor cell
				if anchor_at[r * width + c] != 0:
					conflict = true
					break
			if conflict:
				break

		if not conflict:
			# Forward checking: before recursing, verify every remaining unplaced
			# anchor still has at least one non-conflicting candidate.  Pruning
			# dead-end branches here is critical for large grids with many
			# unconstrained (shape-only) anchors that each have hundreds of
			# candidate rectangles.
			var feasible := true
			for fi in range(idx + 1, entries.size()):
				var fpos: Vector2i = entries[fi]["pos"]
				if covered[fpos.y * width + fpos.x] != 0:
					continue  # anchor cell already covered – skip
				if not _has_any_feasible_candidate(fi, entries, width, height, covered, cancel_check, do_cancel):
					feasible = false
					break
			if do_cancel and cancel_check.call():
				cancelled[0] = true
				_mark_covered(rect, width, covered, 0)
				return
			if feasible:
				_count_backtrack(width, height, entries, idx + 1, covered, count, max_count, cancel_check, do_cancel, cancelled)

		_mark_covered(rect, width, covered, 0)


## Fast feasibility check for forward-checking in the backtracker.
## Returns true when anchor [param anchor_idx] can still be covered by at least one
## non-conflicting rectangle given the current [param covered] state.
## For unconstrained (shape-only) anchors when this is the only remaining
## unconstrained anchor, computes the exact required area from the global coverage
## constraint instead of iterating all possible areas — a much tighter check.
## When multiple unconstrained anchors remain, iterates areas up to the sound
## upper bound: uncovered_cells − fixed_area_remaining − other_unconstrained_count
## (each other unconstrained anchor needs ≥ 1 cell, so this anchor can have at
## most the remainder — sound for any valid solution regardless of generated size).
## Returns false conservatively when cancelled.
static func _has_any_feasible_candidate(
		anchor_idx: int, entries: Array[Dictionary],
		width: int, height: int, covered: PackedByteArray,
		cancel_check: Callable = Callable(), do_cancel: bool = false) -> bool:
	var pos: Vector2i = entries[anchor_idx]["pos"]
	var anchor: Dictionary = entries[anchor_idx]["anchor"]
	var anchor_area: int = int(anchor.get("area", 0))
	var anchor_shape: int = int(anchor.get("shape", ShikakuLogic.SHAPE_ABSENT))

	if anchor_area > 0:
			# Area-constrained: only divisor pairs to check — very few.
			for w in range(1, anchor_area + 1):
				if anchor_area % w != 0:
					continue
				var h := anchor_area / w
				if not _shape_matches(w, h, anchor_shape):
					continue
				if _has_placement_of_size(pos, w, h, width, height, covered, entries, anchor_idx):
					return true
			return false
	else:
			# No area constraint. Count uncovered cells and how much area the remaining
			# area-constrained anchors will consume. If this is the only unconstrained
			# anchor, its required area is fixed — only check that specific area.
			var uncovered_count := 0
			for c in covered:
				if c == 0:
					uncovered_count += 1

			var other_unconstrained := 0
			var fixed_area_remaining := 0
			for k in range(entries.size()):
				if k == anchor_idx:
					continue
				var kpos: Vector2i = entries[k]["pos"]
				if covered[kpos.y * width + kpos.x] != 0:
					continue  # already placed
				var k_area: int = int(entries[k]["anchor"].get("area", 0))
				if k_area > 0:
					fixed_area_remaining += k_area
				else:
					other_unconstrained += 1

			if other_unconstrained == 0:
				# This is the only remaining unconstrained anchor.  Its area is
				# exactly uncovered_cells minus the area of all future area-constrained
				# placements.  Checking only this required area is far tighter than
				# iterating all sizes from 1 upward and gives near-instant pruning
				# when the shape constraint eliminates that area.
				var required_area := uncovered_count - fixed_area_remaining
				if required_area <= 0:
					return false
				for w in range(1, required_area + 1):
					if required_area % w != 0:
						continue
					var h := required_area / w
					if not _shape_matches(w, h, anchor_shape):
						continue
					if _has_placement_of_size(pos, w, h, width, height, covered, entries, anchor_idx):
						return true
				return false
			else:
				# Multiple unconstrained anchors remain. Iterate by increasing area
				# for fast early exit on dense grids.
				# Sound upper bound: each of the other_unconstrained anchors needs ≥ 1
				# cell, and fixed-area anchors need exactly their stated area.
				# This anchor can therefore cover at most the remaining cells after
				# reserving one cell per other unconstrained anchor and subtracting the
				# fixed-area demand — a tighter, sound cap vs. width*height.
				var area_limit := uncovered_count - fixed_area_remaining - other_unconstrained
				if area_limit <= 0:
					return false
				for area in range(1, area_limit + 1):
					if do_cancel and cancel_check.call():
						return false  # conservative: treat cancelled as infeasible
					for w in range(1, area + 1):
						if area % w != 0:
							continue
						var h := area / w
						if not _shape_matches(w, h, anchor_shape):
							continue
						if _has_placement_of_size(pos, w, h, width, height, covered, entries, anchor_idx):
							return true
				return false


## Returns true when a [param w]×[param h] rectangle that contains [param pos]
## can be placed: all its cells are clear in [param covered] and it does not
## capture any other anchor position.
static func _has_placement_of_size(
		pos: Vector2i, w: int, h: int,
		width: int, height: int, covered: PackedByteArray,
		entries: Array[Dictionary], anchor_idx: int) -> bool:
	var min_col := maxi(0, pos.x - w + 1)
	var max_col := mini(width - w, pos.x)
	var min_row := maxi(0, pos.y - h + 1)
	var max_row := mini(height - h, pos.y)
	for r in range(min_row, max_row + 1):
		for c in range(min_col, max_col + 1):
			var rect := Rect2i(c, r, w, h)
			if not _rect_is_clear(rect, width, covered):
				continue
			var conflict := false
			for j in range(entries.size()):
				if j == anchor_idx:
					continue
				if rect.has_point(entries[j]["pos"] as Vector2i):
					conflict = true
					break
			if not conflict:
				return true
	return false


## Enumerate all candidate rectangles for a given anchor position and clue.
## Returns an empty array early if cancelled.
## For area-constrained anchors: enumerates all (w,h) factor pairs of the area.
## For unconstrained anchors: exhaustively enumerates all (w,h) pairs that fit
## in the grid.  No area cap is applied — alternate solutions may use any valid
## rectangle size, so omitting any size would make uniqueness checks unsound.
static func _enumerate_rects_for_anchor(
		pos: Vector2i, anchor: Dictionary,
		width: int, height: int, covered: PackedByteArray,
		cancel_check: Callable = Callable()) -> Array[Rect2i]:
	var do_cancel := cancel_check.is_valid()
	var anchor_area: int = int(anchor.get("area", 0))
	var anchor_shape: int = int(anchor.get("shape", ShikakuLogic.SHAPE_ABSENT))
	var rects: Array[Rect2i] = []

	if anchor_area > 0:
		# Area-constrained: enumerate all (w,h) factor pairs of that area.
		for w in range(1, anchor_area + 1):
			if do_cancel and cancel_check.call():
				return []
			if anchor_area % w != 0:
				continue
			var h := anchor_area / w
			if not _shape_matches(w, h, anchor_shape):
				continue
			_collect_rects_containing(pos, w, h, width, height, covered, rects)
	else:
		# No area constraint: exhaustively enumerate all (w,h) pairs that fit
		# in the grid.  Alternate solutions may use rectangles of any valid
		# size, so no area cap is applied — see _has_any_feasible_candidate for
		# the sound forward-checking bound used in the backtracker instead.
		for w in range(1, width + 1):
			if do_cancel and cancel_check.call():
				return []
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


## Fast variant of _enumerate_rects_for_anchor for empty grids (covered = all 0).
## Skips the per-placement _rect_is_clear scan (always true on empty grid),
## reducing pre-computation cost from O(n_cands × avg_rect_area) to O(n_cands).
## Used for the one-time base-candidate pre-computation in count_solutions,
## is_human_solvable, and the generator's minimisation loop.
##
## For unconstrained anchors (area == 0) the result is sorted by area ascending.
## This enables _is_human_solvable_from_entries to apply a sound early-stopping
## break when the dynamic area_limit is reached, dramatically reducing the
## candidate work for shape-only anchors on large grids.
static func _enumerate_rects_for_anchor_empty(
		pos: Vector2i, anchor: Dictionary,
		width: int, height: int) -> Array[Rect2i]:
	var anchor_area: int = int(anchor.get("area", 0))
	var anchor_shape: int = int(anchor.get("shape", ShikakuLogic.SHAPE_ABSENT))
	var rects: Array[Rect2i] = []

	if anchor_area > 0:
		for w in range(1, anchor_area + 1):
			if anchor_area % w != 0:
				continue
			var h := anchor_area / w
			if not _shape_matches(w, h, anchor_shape):
				continue
			_collect_rects_containing_empty(pos, w, h, width, height, rects)
	else:
		# Iterate (w,h) pairs in ascending area order so the result is sorted
		# by area.  Outer loop: target area 1..W*H.  Inner loop: divisors dw
		# of target_area with dw ≤ width.  Total inner iterations ≤
		# Σ(a=1..W) a + Σ(a=W+1..W*H) W ≈ W²/2 + W*(W*H-W) ≈ W²*H, which
		# for 15×15 is ~3 300 — similar to the original 15×15=225 nested loop
		# for viable pairs, with the benefit of guaranteed area ordering.
		for target_area in range(1, width * height + 1):
			for dw in range(1, mini(target_area, width) + 1):
				if target_area % dw != 0:
					continue
				var dh := target_area / dw
				if dh > height:
					continue
				if not _shape_matches(dw, dh, anchor_shape):
					continue
				_collect_rects_containing_empty(pos, dw, dh, width, height, rects)

	return rects


## Fast variant of _collect_rects_containing for empty grids.
## Appends all (col, row) window positions without a coverage check.
static func _collect_rects_containing_empty(
		pos: Vector2i, w: int, h: int,
		width: int, height: int,
		out: Array[Rect2i]) -> void:
	var min_col := maxi(0, pos.x - w + 1)
	var max_col := mini(width - w, pos.x)
	var min_row := maxi(0, pos.y - h + 1)
	var max_row := mini(height - h, pos.y)
	for r in range(min_row, max_row + 1):
		for c in range(min_col, max_col + 1):
			out.append(Rect2i(c, r, w, h))


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
