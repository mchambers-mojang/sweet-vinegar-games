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
	# them throughout the backtracker by filtering with _rect_is_feasible.  This
	# avoids re-enumerating (w,h) pairs at every node — critical for shape-only
	# anchors with many candidates on large grids.
	# Also use the candidate count as the MRV key for static root ordering.
	#
	# is_anchor: static bitmask of all anchor positions (never changes during search).
	# Combined with the live covered array, it replaces the per-node anchor_at rebuild.
	var is_anchor := PackedByteArray()
	is_anchor.resize(width * height)
	is_anchor.fill(0)
	# Per-entry cached fields for O(1) access in the backtracker.
	var uncovered_count := width * height
	var fixed_area_remaining := 0
	var unconstrained_count := 0
	for entry in entries:
		var pos: Vector2i = entry["pos"]
		is_anchor[pos.y * width + pos.x] = 1
		var entry_area: int = int(entry["anchor"].get("area", 0))
		entry["_area"] = entry_area
		entry["_is_unc"] = entry_area == 0
		if entry_area > 0:
			fixed_area_remaining += entry_area
		else:
			unconstrained_count += 1
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
	_count_backtrack(width, height, entries, 0, covered, count, max_count,
			cancel_check, cancel_check.is_valid(), cancelled,
			is_anchor, uncovered_count, fixed_area_remaining, unconstrained_count)
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
## Performance: per-anchor work_cands arrays shrink permanently as placements are
## made (candidates whose cells become covered are removed and never re-visited).
## _passes_anchor_at is applied once at initialisation — it stays sound because
## once anchor k is placed its cell is marked covered, so any candidate containing
## that cell fails _rect_is_clear and is removed naturally, making a second
## anchor_at pass redundant.
## Phase 2 permanently narrows work_cands[owner_idx] instead of accumulating
## required_cells, so Phase 1 on the next iteration immediately sees the
## tighter candidate set at zero extra cost.
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

	# anchor_at: 1 for cells that have an unplaced anchor; cleared when placed.
	var anchor_at := PackedByteArray()
	anchor_at.resize(width * height)
	anchor_at.fill(0)
	var anchor_areas := PackedInt32Array()
	anchor_areas.resize(n)
	var unconstrained_flags := PackedByteArray()
	unconstrained_flags.resize(n)
	# Cache anchor positions to avoid repeated Dictionary lookups inside loops.
	var anchor_pos: Array[Vector2i] = []
	var uncovered_count := width * height
	var fixed_area_remaining := 0
	var unconstrained_count := 0
	for j in range(n):
		var ap: Vector2i = entries[j]["pos"]
		anchor_pos.append(ap)
		anchor_at[ap.y * width + ap.x] = 1
		var j_area: int = int(entries[j]["anchor"].get("area", 0))
		anchor_areas[j] = j_area
		if j_area > 0:
			fixed_area_remaining += j_area
			unconstrained_flags[j] = 0
		else:
			unconstrained_count += 1
			unconstrained_flags[j] = 1

	# Compute initial area_limit.
	var area_limit := uncovered_count - fixed_area_remaining - maxi(0, unconstrained_count - 1)

	# Build per-anchor work_cands from base_candidates, filtered once by anchor_at.
	# Applying _passes_anchor_at here rather than on every iteration is correct:
	# when anchor k is placed its cell becomes covered, so any candidate containing
	# it is subsequently excluded by _rect_is_clear — a second anchor_at check
	# would yield the same result and is therefore redundant.
	var work_cands: Array = []
	for i in range(n):
		var pos: Vector2i = anchor_pos[i]
		var is_unc: bool = unconstrained_flags[i] != 0
		var wc: Array[Rect2i] = []
		for rect in base_candidates[i]:
			if is_unc and rect.size.x * rect.size.y > area_limit:
				break  # base_candidates area-sorted ascending for unconstrained
			if _passes_anchor_at(rect, pos, anchor_at, width):
				wc.append(rect)
		work_cands.append(wc)
		if wc.is_empty():
			return false

	var changed := true
	while changed:
		if do_cancel and cancel_check.call():
			return false
		changed = false

		# Recompute area_limit (may have tightened since last placement).
		var al := uncovered_count - fixed_area_remaining - maxi(0, unconstrained_count - 1)

		# ------------------------------------------------------------------
		# Phase 1: Forced single candidate
		# Filter work_cands[i] by current coverage, removing invalid entries
		# permanently (they never become valid again once cells are covered).
		# The area_limit break also prunes permanently since al only decreases.
		# ------------------------------------------------------------------
		for i in range(n):
			if placed[i] != 0:
				continue
			var is_unc: bool = unconstrained_flags[i] != 0
			var new_wc: Array[Rect2i] = []
			for rect in work_cands[i]:
				if is_unc and rect.size.x * rect.size.y > al:
					break  # area-sorted; all remaining are also too large
				if _rect_is_clear(rect, width, covered):
					new_wc.append(rect)
			work_cands[i] = new_wc
			if new_wc.is_empty():
				return false
			if new_wc.size() == 1:
				var pos: Vector2i = anchor_pos[i]
				_mark_covered(new_wc[0], width, covered, 1)
				placed[i] = 1
				uncovered_count -= new_wc[0].size.x * new_wc[0].size.y
				if is_unc:
					unconstrained_count -= 1
				else:
					fixed_area_remaining -= anchor_areas[i]
				anchor_at[pos.y * width + pos.x] = 0
				al = uncovered_count - fixed_area_remaining - maxi(0, unconstrained_count - 1)
				changed = true

		if changed:
			continue

		if do_cancel and cancel_check.call():
			return false

		# ------------------------------------------------------------------
		# Phase 2: Cell-ownership elimination
		# owner_map: flat PackedInt32Array indexed by cell.
		#   -1 = no unplaced anchor candidate reaches this cell
		#    k = unique anchor index (0..n-1) can cover this cell
		#   -2 = multiple anchors can cover this cell
		# work_cands[i] is already coverage-filtered by Phase 1, so no
		# per-candidate _rect_is_clear call is needed here.
		# ------------------------------------------------------------------
		var owner_map := PackedInt32Array()
		owner_map.resize(width * height)
		owner_map.fill(-1)

		al = uncovered_count - fixed_area_remaining - maxi(0, unconstrained_count - 1)
		for i in range(n):
			if placed[i] != 0:
				continue
			var is_unc: bool = unconstrained_flags[i] != 0
			for rect in work_cands[i]:
				if is_unc and rect.size.x * rect.size.y > al:
					break
				for r in range(rect.position.y, rect.position.y + rect.size.y):
					for c in range(rect.position.x, rect.position.x + rect.size.x):
						var idx := r * width + c
						# work_cands[i] is coverage-clean (Phase 1 filtered it),
						# so all cells here are uncovered — no covered-check needed.
						var cur := owner_map[idx]
						if cur == -1:
							owner_map[idx] = i
						elif cur != i:
							owner_map[idx] = -2  # multiple owners
			if do_cancel and cancel_check.call():
				return false

		# For each cell with a unique owner, permanently restrict that anchor's
		# work_cands to candidates containing the cell.  Phase 1 on the next
		# iteration automatically uses the narrowed set — no required_cells needed.
		# Combined coverage re-filter: earlier cells in this loop may have triggered
		# placements that covered some of work_cands[owner_idx], so we re-apply
		# _rect_is_clear here while building the restricted set.
		for cell_idx in range(owner_map.size()):
			if covered[cell_idx] != 0:
				continue
			var owner_idx := owner_map[cell_idx]
			if owner_idx < 0:
				continue  # -1 (none) or -2 (multiple owners)
			if placed[owner_idx] != 0:
				continue
			var cell := Vector2i(cell_idx % width, cell_idx / width)
			# Single pass: simultaneously remove coverage-invalid candidates and
			# collect those that contain the uniquely-owned cell.
			var new_wc: Array[Rect2i] = []
			var restricted: Array[Rect2i] = []
			for rect in work_cands[owner_idx]:
				if not _rect_is_clear(rect, width, covered):
					continue  # permanently invalid (cells now covered)
				new_wc.append(rect)
				if rect.has_point(cell):
					restricted.append(rect)
			work_cands[owner_idx] = new_wc
			if new_wc.is_empty():
				return false
			if restricted.is_empty():
				return false
			if restricted.size() == 1:
				# Forced: place immediately.
				var opos: Vector2i = anchor_pos[owner_idx]
				var is_unc_o: bool = unconstrained_flags[owner_idx] != 0
				work_cands[owner_idx] = restricted
				_mark_covered(restricted[0], width, covered, 1)
				placed[owner_idx] = 1
				uncovered_count -= restricted[0].size.x * restricted[0].size.y
				if is_unc_o:
					unconstrained_count -= 1
				else:
					fixed_area_remaining -= anchor_areas[owner_idx]
				anchor_at[opos.y * width + opos.x] = 0
				al = uncovered_count - fixed_area_remaining - maxi(0, unconstrained_count - 1)
				changed = true
			elif restricted.size() < new_wc.size():
				# Not yet forced, but permanently narrow the candidate set.
				work_cands[owner_idx] = restricted
				changed = true

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
		cancel_check: Callable, do_cancel: bool, cancelled: Array,
		is_anchor: PackedByteArray,
		uncovered_count: int, fixed_area_remaining: int, unconstrained_count: int) -> void:
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
	var is_unc: bool = entry.get("_is_unc", false)
	var entry_area: int = int(entry.get("_area", 0))

	if covered[pos.y * width + pos.x] != 0:
		_count_backtrack(width, height, entries, idx + 1, covered, count, max_count,
				cancel_check, do_cancel, cancelled, is_anchor,
				uncovered_count, fixed_area_remaining, unconstrained_count)
		return

	# Sound upper bound: in any valid tiling, fixed-area anchors consume exactly
	# fixed_area_remaining cells and each of the other unconstrained_count − 1
	# unconstrained anchors needs ≥ 1 cell.  The current unconstrained anchor can
	# cover at most the remainder — so candidates sorted by area asc can break early.
	var area_limit := uncovered_count - fixed_area_remaining - maxi(0, unconstrained_count - 1)

	# Filter base candidates using _rect_is_feasible: a single-pass check that
	# combines the coverage test (_rect_is_clear) and the anchor-conflict test
	# (no other unplaced anchor inside the rect).  Using the static is_anchor
	# bitmask + the live covered array replaces the per-node anchor_at rebuild.
	var rects: Array[Rect2i] = []
	for rect in entry.get("_base_cands", []):
		if is_unc and rect.size.x * rect.size.y > area_limit:
			break  # _base_cands sorted by area asc for unconstrained
		if _rect_is_feasible(rect, pos, is_anchor, covered, width):
			rects.append(rect)
	if do_cancel and cancel_check.call():
		cancelled[0] = true
		return

	for rect in rects:
		if count[0] >= max_count or cancelled[0]:
			return
		var rect_area := rect.size.x * rect.size.y
		_mark_covered(rect, width, covered, 1)

		# Update incremental bookkeeping after placing this rect.
		var new_uncovered := uncovered_count - rect_area
		var new_fixed := fixed_area_remaining
		var new_unc := unconstrained_count
		if is_unc:
			new_unc -= 1
		else:
			new_fixed -= entry_area

		# Forward checking: verify every remaining unplaced anchor still has at
		# least one feasible candidate.  Use the same is_anchor + covered approach
		# with a shared fi_area_limit (sound for ALL remaining unconstrained anchors:
		# each of the new_unc − 1 others needs ≥ 1 cell).
		var fi_area_limit := new_uncovered - new_fixed - maxi(0, new_unc - 1)
		var feasible := true
		for fi in range(idx + 1, entries.size()):
			if cancelled[0]:
				break
			var fpos: Vector2i = entries[fi]["pos"]
			if covered[fpos.y * width + fpos.x] != 0:
				continue  # anchor already covered — skip
			if not _has_any_feasible_cand_fast(entries[fi], is_anchor, covered, width, fi_area_limit):
				feasible = false
				break
		if do_cancel and cancel_check.call():
			cancelled[0] = true
			_mark_covered(rect, width, covered, 0)
			return
		if feasible:
			_count_backtrack(width, height, entries, idx + 1, covered, count, max_count,
					cancel_check, do_cancel, cancelled, is_anchor,
					new_uncovered, new_fixed, new_unc)

		_mark_covered(rect, width, covered, 0)


## Fast feasibility check for forward-checking in the backtracker.
## Iterates pre-computed base candidates (already area-sorted for unconstrained
## anchors) and returns true as soon as one passes _rect_is_feasible.
## For unconstrained anchors, breaks early when candidate area exceeds area_limit
## (the sound upper bound derived from the global coverage constraint).
static func _has_any_feasible_cand_fast(
		entry: Dictionary,
		is_anchor: PackedByteArray, covered: PackedByteArray,
		width: int, area_limit: int) -> bool:
	var pos: Vector2i = entry["pos"]
	var fi_is_unc: bool = entry.get("_is_unc", false)
	for crect in entry.get("_base_cands", []):
		if fi_is_unc and crect.size.x * crect.size.y > area_limit:
			break  # sorted by area asc for unconstrained entries
		if _rect_is_feasible(crect, pos, is_anchor, covered, width):
			return true
	return false


## Combined single-pass feasibility test: returns true when [param rect]
## (a) has all cells uncovered and (b) contains no unplaced anchor other than
## [param self_pos].  An unplaced anchor is detected via the static
## [param is_anchor] bitmask together with the live [param covered] array —
## no separate anchor_at rebuild is needed.
static func _rect_is_feasible(
		rect: Rect2i, self_pos: Vector2i,
		is_anchor: PackedByteArray, covered: PackedByteArray,
		grid_width: int) -> bool:
	for r in range(rect.position.y, rect.position.y + rect.size.y):
		for c in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := r * grid_width + c
			if covered[cell] != 0:
				return false  # cell already taken
			if c != self_pos.x or r != self_pos.y:
				if is_anchor[cell] != 0:
					return false  # another unplaced anchor inside this rect
	return true


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
		# size, so no area cap is applied — the sound area_limit forward-checking
		# bound in _count_backtrack prunes infeasible branches instead.
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
