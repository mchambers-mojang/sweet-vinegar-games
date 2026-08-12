class_name NumberPathSolver
extends RefCounted

## Human-style deduction solver for Number Path puzzles.
## Returns solver steps with reasoning rank, and can count solutions
## (with cancellation) for uniqueness verification.

# Reasoning ranks
const RANK_FORCED := 1    # endpoint degree, next checkpoint, one-cell dead-end
const RANK_LOCAL := 2     # two local constraints or simple bottleneck
const RANK_REGION := 3    # remaining-region connectivity or cut analysis
const RANK_GLOBAL := 4    # non-branching chain: checkpoint order + barriers + connectivity

# Resolution-depth boundary between Rank 3 and Rank 4. A branch resolved by an
# immediate sound cut is Rank 2 (depth 0); resolved after one forced move is
# Rank 3 (depth 1); anything needing a longer forced chain is Rank 4 (depth >= 2).
const _RANK3_DEPTH := 1

# --- Public API ---

## Solve a puzzle using human-style deductions.
## max_rank_allowed caps the deduction difficulty the solver may use; if a step
## requires a harder rank than allowed, the solver stops (solved=false). This lets
## the generator probe a puzzle's exact difficulty cheaply (see the depth ladder
## in _deduce_by_depth). rollout_budget bounds the forced-only look-ahead used to
## refute candidates; -1 means width*height (effectively unbounded). Bounding the
## look-ahead keeps every solve cheap and matches how a human resolves a branch
## (a short non-branching chain), and it only ever causes a false negative (never
## certifies a non-unique puzzle), so it is safe for the generator to rely on.
## Returns {"solved": bool, "path": Array[Vector2i], "steps": Array[Dictionary],
##          "max_rank": int}
## Steps: [{"rank": int, "reason": str, "affected": Array[Vector2i], "result": Vector2i}]
static func solve(
		width: int,
		height: int,
		checkpoints: Array[Dictionary],
		barriers: Array[Dictionary],
		max_rank_allowed: int = RANK_GLOBAL,
		rollout_budget: int = -1) -> Dictionary:
	var state := _SolverState.new(width, height, checkpoints, barriers)
	var steps: Array[Dictionary] = []
	var max_rank := 0
	var budget := rollout_budget if rollout_budget >= 0 else width * height

	while not state.is_complete():
		var step := _try_deduce(state, max_rank_allowed, budget)
		if step.is_empty():
			break
		steps.append(step)
		var rank := int(step.get("rank", 0))
		if rank > max_rank:
			max_rank = rank
		var cell: Vector2i = step.get("result", Vector2i(-1, -1))
		if cell == Vector2i(-1, -1):
			break
		state.extend(cell)

	if state.is_complete():
		return {
			"solved": true,
			"path": state.get_path(),
			"steps": steps,
			"max_rank": max_rank,
		}
	return {
		"solved": false,
		"path": state.get_path(),
		"steps": steps,
		"max_rank": max_rank,
	}


## Count the number of valid complete paths.
## cancel_check: Callable() -> bool, returns true to abort.
## Returns -1 if cancelled, 0 if none, or the count (up to max_count).
static func count_solutions(
		width: int,
		height: int,
		checkpoints: Array[Dictionary],
		barriers: Array[Dictionary],
		max_count: int = 2,
		cancel_check: Callable = Callable()) -> int:
	var counter := [0]
	var cancelled := [false]
	var start := _get_start_cell(checkpoints)
	if start == Vector2i(-1, -1):
		return 0

	var visited := PackedByteArray()
	visited.resize(width * height)
	visited.fill(0)

	var path: Array[Vector2i] = [start]
	visited[start.y * width + start.x] = 1

	# Check cancellation before starting any work so that an immediately-set
	# cancel flag is always honoured even on tiny grids that finish in < 500 DFS
	# calls (the periodic check inside _count_dfs would never fire for them).
	if cancel_check.is_valid() and cancel_check.call():
		return -1

	var call_count := [0]
	_count_dfs(width, height, checkpoints, barriers, path, visited,
			counter, cancelled, max_count, cancel_check, call_count)

	if cancelled[0]:
		return -1
	return counter[0]


# --- Private: deduction engine ---

static func _try_deduce(
		state: _SolverState,
		max_rank_allowed: int,
		rollout_budget: int) -> Dictionary:
	# Rank 1: forced moves (single legal neighbor, checkpoint approach, dead-end).
	var step := _rank1_forced(state)
	if not step.is_empty():
		return step
	if max_rank_allowed < RANK_LOCAL:
		return {}
	# Rank 2/3/4: resolve a branch by the shallowest sound refutation depth.
	return _deduce_by_depth(state, max_rank_allowed, rollout_budget)


static func _rank1_forced(state: _SolverState) -> Dictionary:
	var head := state.get_head()
	var candidates := state.free_neighbors(head)

	# Out-of-order checkpoints are not legal candidates. If only one neighbor
	# remains after applying checkpoint order, the next move is forced.
	var legal_candidates: Array[Vector2i] = []
	for candidate in candidates:
		if state.is_checkpoint_valid_next(candidate):
			legal_candidates.append(candidate)
	if legal_candidates.size() == 1:
		var cell: Vector2i = legal_candidates[0]
		return {
			"rank": RANK_FORCED,
			"reason": "single legal neighbor",
			"affected": [head],
			"result": cell,
		}

	# Next unvisited checkpoint has only one reachable approach (the current head).
	# head is always visited, so it never appears in free_neighbors(next_cp).
	# Instead, check if head is directly adjacent to next_cp and then temporarily
	# block next_cp in the BFS to determine whether any of its free neighbours are
	# accessible from head without routing through next_cp.  If none are, head is
	# the sole viable predecessor and we must step there immediately.
	var next_cp := state.next_checkpoint()
	if next_cp != Vector2i(-1, -1) and state.is_adjacent_reachable_from_head(next_cp):
		var cp_free_neighbors := state.free_neighbors(next_cp)
		var cp_idx: int = next_cp.y * state.width + next_cp.x
		state.visited[cp_idx] = 1
		var alt_approach := false
		for nb in cp_free_neighbors:
			if state.can_reach_from_head(nb):
				alt_approach = true
				break
		state.visited[cp_idx] = 0
		if not alt_approach:
			return {
				"rank": RANK_FORCED,
				"reason": "next checkpoint only approach",
				"affected": [next_cp],
				"result": next_cp,
			}

	# Dead-end prevention: if a free neighbor of head has degree 1 (only connected
	# to head), we MUST go there or it becomes permanently isolated.
	var must_visit: Vector2i = Vector2i(-1, -1)
	for nb in candidates:
		if not state.is_checkpoint_valid_next(nb):
			continue
		if state.would_isolate_cell_if_not_extended_to(nb):
			if must_visit == Vector2i(-1, -1):
				must_visit = nb
			else:
				# Two cells with degree 1 — neither can be deferred; no forced move here
				return {}
	if must_visit != Vector2i(-1, -1):
		return {
			"rank": RANK_FORCED,
			"reason": "dead-end prevention",
			"affected": [must_visit],
			"result": must_visit,
		}

	return {}


# Rank 2/3/4 depth ladder.
#
# At a branch (>1 legal candidate) a move is only forced when every alternative
# can be *disproved* by a sound necessary condition — never by guessing which
# branch "looks" better. _refute_depth tentatively takes a candidate, follows
# only forced (Rank-1) moves, and reports the first depth at which the position
# becomes provably impossible. The rank is the shallowest look-ahead needed to
# leave exactly one surviving candidate:
#   depth 0  -> Rank 2 (immediate local/bottleneck contradiction)
#   depth 1  -> Rank 3 (one forced move exposes a region/cut contradiction)
#   depth >=2 -> Rank 4 (a longer non-branching chain of forced moves)
# Because every elimination is a necessary condition, completing a solve with
# these deductions proves the solution is unique.
static func _deduce_by_depth(
		state: _SolverState,
		max_rank_allowed: int,
		rollout_budget: int) -> Dictionary:
	var head := state.get_head()
	var candidates := state.free_neighbors(head)
	var legal: Array[Vector2i] = []
	for nb in candidates:
		if state.is_checkpoint_valid_next(nb):
			legal.append(nb)
	# 0 or 1 legal candidate is already handled as a Rank-1 forced move.
	if legal.size() <= 1:
		return {}

	# Only roll out as deep as the allowed rank could possibly need.
	var budget := 0
	if max_rank_allowed >= RANK_GLOBAL:
		budget = rollout_budget
	elif max_rank_allowed == RANK_REGION:
		budget = _RANK3_DEPTH

	var depths: Array[int] = []
	for nb in legal:
		depths.append(_refute_depth(state, nb, budget))

	# Rank 2: exactly one candidate survives immediate (depth-0) refutation.
	var forced := _single_survivor(legal, depths, 0)
	if forced != Vector2i(-1, -1):
		return {
			"rank": RANK_LOCAL,
			"reason": "local constraint",
			"affected": legal,
			"result": forced,
		}
	if _survivor_count(depths, 0) == 0:
		return {}

	# Rank 3: exactly one candidate survives a one-move-deep refutation.
	if max_rank_allowed >= RANK_REGION:
		forced = _single_survivor(legal, depths, _RANK3_DEPTH)
		if forced != Vector2i(-1, -1):
			return {
				"rank": RANK_REGION,
				"reason": "region connectivity",
				"affected": legal,
				"result": forced,
			}
		if _survivor_count(depths, _RANK3_DEPTH) == 0:
			return {}

	# Rank 4: exactly one candidate survives the full forced-chain refutation.
	if max_rank_allowed >= RANK_GLOBAL:
		forced = _single_survivor(legal, depths, budget)
		if forced != Vector2i(-1, -1):
			return {
				"rank": RANK_GLOBAL,
				"reason": "global chain",
				"affected": legal,
				"result": forced,
			}

	return {}


## Tentatively move to `candidate`, then follow only forced (Rank-1) moves.
## Returns the depth at which the position first becomes provably impossible
## (0 = impossible immediately after the tentative move), or -1 if no
## contradiction is found within `max_budget` forced moves (the candidate
## survives). State is always restored before returning.
static func _refute_depth(state: _SolverState, candidate: Vector2i, max_budget: int) -> int:
	var saved_size := state.path.size()
	state.extend(candidate)
	var depth := 0
	var result := -1
	while true:
		if state.is_complete():
			result = -1
			break
		if _state_invalid(state):
			result = depth
			break
		if depth >= max_budget:
			result = -1
			break
		var mv := _forced_move(state)
		if mv == Vector2i(-1, -1):
			result = -1
			break
		state.extend(mv)
		depth += 1
	state.rollback_to(saved_size)
	return result


## The single Rank-1 forced move from the current head, or (-1,-1) if none.
static func _forced_move(state: _SolverState) -> Vector2i:
	var step := _rank1_forced(state)
	if step.is_empty():
		return Vector2i(-1, -1)
	return step.get("result", Vector2i(-1, -1))


static func _survivor_count(depths: Array[int], budget: int) -> int:
	var count := 0
	for d in depths:
		if d == -1 or d > budget:
			count += 1
	return count


## If exactly one candidate survives refutation at `budget`, return it; else (-1,-1).
static func _single_survivor(
		legal: Array[Vector2i],
		depths: Array[int],
		budget: int) -> Vector2i:
	var found := Vector2i(-1, -1)
	var count := 0
	for i in range(legal.size()):
		if depths[i] == -1 or depths[i] > budget:
			found = legal[i]
			count += 1
			if count > 1:
				return Vector2i(-1, -1)
	return found if count == 1 else Vector2i(-1, -1)


## Bundled sound necessary conditions for completing a Hamiltonian path from the
## current head to the final checkpoint. Any single failure proves the branch is
## dead; none of these ever rejects a genuinely completable position.
static func _state_invalid(state: _SolverState) -> bool:
	return state.head_is_premature_endpoint() \
			or not state.head_reaches_all_free() \
			or not state.degree_condition_ok() \
			or not state.parity_ok()


# --- Private: solution counting DFS ---

static func _count_dfs(
		width: int,
		height: int,
		checkpoints: Array[Dictionary],
		barriers: Array[Dictionary],
		path: Array[Vector2i],
		visited: PackedByteArray,
		counter: Array,
		cancelled: Array,
		max_count: int,
		cancel_check: Callable,
		call_count: Array) -> void:
	if cancelled[0]:
		return
	call_count[0] += 1
	if call_count[0] >= 500000:
		cancelled[0] = true
		return
	if call_count[0] % 500 == 0 and cancel_check.is_valid() and cancel_check.call():
		cancelled[0] = true
		return

	var total := width * height
	if path.size() == total:
		# Check all checkpoints visited in order
		if _checkpoints_satisfied(path, checkpoints):
			counter[0] += 1
		return

	var head: Vector2i = path[path.size() - 1]
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	for d in dirs:
		var nb: Vector2i = head + d
		if nb.x < 0 or nb.y < 0 or nb.x >= width or nb.y >= height:
			continue
		var idx: int = nb.y * width + nb.x
		if visited[idx] != 0:
			continue
		if _has_barrier(barriers, head, nb):
			continue
		# Checkpoint order
		var cp_idx := _checkpoint_at(nb, checkpoints)
		if cp_idx >= 0:
			var expected := _next_cp_index(path, checkpoints)
			if cp_idx != expected:
				continue

		path.append(nb)
		visited[idx] = 1

		# Connectivity pruning: if extending to nb leaves any remaining cell
		# unreachable from nb, this branch can never complete — skip it.
		var remaining_after: int = total - path.size()
		var prune := false
		if remaining_after > 0:
			if _count_reachable_from_static(width, height, visited, barriers, nb) != remaining_after:
				prune = true

		if not prune:
			_count_dfs(width, height, checkpoints, barriers, path, visited,
					counter, cancelled, max_count, cancel_check, call_count)
		if cancelled[0] or counter[0] >= max_count:
			path.pop_back()
			visited[idx] = 0
			return
		path.pop_back()
		visited[idx] = 0


static func _get_start_cell(checkpoints: Array[Dictionary]) -> Vector2i:
	if checkpoints.is_empty():
		return Vector2i(-1, -1)
	var cp: Dictionary = checkpoints[0]
	return Vector2i(int(cp.get("x", -1)), int(cp.get("y", -1)))


static func _checkpoints_satisfied(path: Array[Vector2i], checkpoints: Array[Dictionary]) -> bool:
	if checkpoints.is_empty():
		return true
	# Check last cell is last checkpoint
	var last_cp: Dictionary = checkpoints[checkpoints.size() - 1]
	var last_cell := Vector2i(int(last_cp.get("x", -1)), int(last_cp.get("y", -1)))
	if path.is_empty() or path[path.size() - 1] != last_cell:
		return false
	# All checkpoints in order
	var cp_order_idx := 0
	for cell in path:
		if cp_order_idx < checkpoints.size():
			var cp: Dictionary = checkpoints[cp_order_idx]
			var cv := Vector2i(int(cp.get("x", -1)), int(cp.get("y", -1)))
			if cell == cv:
				cp_order_idx += 1
	return cp_order_idx == checkpoints.size()


static func _checkpoint_at(cell: Vector2i, checkpoints: Array[Dictionary]) -> int:
	for i in range(checkpoints.size()):
		var cp: Dictionary = checkpoints[i]
		if int(cp.get("x", -1)) == cell.x and int(cp.get("y", -1)) == cell.y:
			return i
	return -1


static func _next_cp_index(path: Array[Vector2i], checkpoints: Array[Dictionary]) -> int:
	var visited := 0
	for cp in checkpoints:
		var cv := Vector2i(int(cp.get("x", -1)), int(cp.get("y", -1)))
		var found := false
		for cell in path:
			if cell == cv:
				found = true
				break
		if found:
			visited += 1
		else:
			break
	return visited


static func _has_barrier(barriers: Array[Dictionary], a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		var top := a if a.y < b.y else b
		for barrier in barriers:
			if int(barrier.get("r", -1)) == top.y and int(barrier.get("c", -1)) == top.x and int(barrier.get("dir", -1)) == NumberPathLogic.DIR_DOWN:
				return true
	else:
		var left := a if a.x < b.x else b
		for barrier in barriers:
			if int(barrier.get("r", -1)) == left.y and int(barrier.get("c", -1)) == left.x and int(barrier.get("dir", -1)) == NumberPathLogic.DIR_RIGHT:
				return true
	return false


## BFS from `start` (which is already marked visited) through unvisited cells.
## Returns the count of unvisited cells reachable from start, not counting start itself.
## Used by _count_dfs for connectivity pruning.
static func _count_reachable_from_static(
		width: int, height: int,
		visited: PackedByteArray,
		barriers: Array[Dictionary],
		start: Vector2i) -> int:
	var count := 0
	var seen := PackedByteArray()
	seen.resize(width * height)
	seen.fill(0)
	seen[start.y * width + start.x] = 1
	var queue: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# Seed from start's unvisited neighbours (start itself is already visited)
	for d in dirs:
		var nb: Vector2i = start + d
		if nb.x < 0 or nb.y < 0 or nb.x >= width or nb.y >= height:
			continue
		var idx: int = nb.y * width + nb.x
		if visited[idx] != 0 or seen[idx] != 0 or _has_barrier(barriers, start, nb):
			continue
		seen[idx] = 1
		queue.append(nb)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		count += 1
		for d in dirs:
			var nb: Vector2i = cur + d
			if nb.x < 0 or nb.y < 0 or nb.x >= width or nb.y >= height:
				continue
			var idx: int = nb.y * width + nb.x
			if visited[idx] != 0 or seen[idx] != 0 or _has_barrier(barriers, cur, nb):
				continue
			seen[idx] = 1
			queue.append(nb)
	return count


# --- Solver state helper class ---

class _SolverState:
	var width: int
	var height: int
	var checkpoints: Array[Dictionary]
	var barriers: Array[Dictionary]
	var path: Array[Vector2i]
	var visited: PackedByteArray

	func _init(w: int, h: int, cps: Array[Dictionary], bs: Array[Dictionary]) -> void:
		width = w
		height = h
		checkpoints = cps
		barriers = bs
		path = []
		visited = PackedByteArray()
		visited.resize(w * h)
		visited.fill(0)
		if not cps.is_empty():
			var start := Vector2i(int(cps[0].get("x", 0)), int(cps[0].get("y", 0)))
			path.append(start)
			visited[start.y * w + start.x] = 1

	func get_head() -> Vector2i:
		if path.is_empty():
			return Vector2i(-1, -1)
		return path[path.size() - 1]

	func get_path() -> Array[Vector2i]:
		return path

	func is_complete() -> bool:
		if path.size() != width * height:
			return false
		return NumberPathSolver._checkpoints_satisfied(path, checkpoints)

	func extend(cell: Vector2i) -> void:
		path.append(cell)
		visited[cell.y * width + cell.x] = 1

	func remaining_unvisited() -> int:
		return width * height - path.size()

	func free_neighbors(cell: Vector2i) -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for d in dirs:
			var nb := cell + d
			if nb.x < 0 or nb.y < 0 or nb.x >= width or nb.y >= height:
				continue
			if visited[nb.y * width + nb.x] != 0:
				continue
			if NumberPathSolver._has_barrier(barriers, cell, nb):
				continue
			result.append(nb)
		return result

	func free_neighbor_count_after_extend(cell: Vector2i) -> int:
		# Temporarily mark cell as visited
		visited[cell.y * width + cell.x] = 1
		var count := free_neighbors(cell).size()
		visited[cell.y * width + cell.x] = 0
		return count

	func is_checkpoint_valid_next(cell: Vector2i) -> bool:
		var cp_idx := NumberPathSolver._checkpoint_at(cell, checkpoints)
		if cp_idx < 0:
			return true
		var expected := NumberPathSolver._next_cp_index(path, checkpoints)
		return cp_idx == expected

	func next_checkpoint() -> Vector2i:
		var idx := NumberPathSolver._next_cp_index(path, checkpoints)
		if idx >= checkpoints.size():
			return Vector2i(-1, -1)
		var cp: Dictionary = checkpoints[idx]
		return Vector2i(int(cp.get("x", -1)), int(cp.get("y", -1)))

	func can_reach_from_head(target: Vector2i) -> bool:
		# BFS from head to target through free cells
		var head := get_head()
		if head == Vector2i(-1, -1):
			return false
		var queue: Array[Vector2i] = [head]
		var seen := PackedByteArray()
		seen.resize(width * height)
		seen.fill(0)
		seen[head.y * width + head.x] = 1
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			if cur == target:
				return true
			for nb in free_neighbors(cur):
				if seen[nb.y * width + nb.x] == 0:
					seen[nb.y * width + nb.x] = 1
					queue.append(nb)
		return false

	func is_adjacent_reachable_from_head(cell: Vector2i) -> bool:
		var head := get_head()
		if head == Vector2i(-1, -1):
			return false
		var diff := cell - head
		if abs(diff.x) + abs(diff.y) != 1:
			return false
		if visited[cell.y * width + cell.x] != 0:
			return false
		if NumberPathSolver._has_barrier(barriers, head, cell):
			return false
		return true

	func would_isolate_cell_if_not_extended_to(other: Vector2i) -> bool:
		# Check if 'other' has only one free neighbor (degree 1) in current state
		# (not counting the head which will be extended elsewhere)
		var other_neighbors := free_neighbors(other)
		return other_neighbors.size() == 1 and other_neighbors[0] == get_head()

	## Undo path extensions back to `size` cells, clearing their visited marks.
	## Used to restore state after a speculative refutation rollout.
	func rollback_to(size: int) -> void:
		while path.size() > size:
			var cell: Vector2i = path.pop_back()
			visited[cell.y * width + cell.x] = 0

	func _last_checkpoint() -> Vector2i:
		if checkpoints.is_empty():
			return Vector2i(-1, -1)
		var lc: Dictionary = checkpoints[checkpoints.size() - 1]
		return Vector2i(int(lc.get("x", -1)), int(lc.get("y", -1)))

	## The path must terminate on the final checkpoint. Arriving there while any
	## cell is still unvisited is unrecoverable (we cannot leave and return).
	func head_is_premature_endpoint() -> bool:
		var last_cp := _last_checkpoint()
		if last_cp == Vector2i(-1, -1):
			return false
		return get_head() == last_cp and remaining_unvisited() > 0

	## Every unvisited cell must remain reachable from the head through free cells.
	func head_reaches_all_free() -> bool:
		var remaining := remaining_unvisited()
		if remaining == 0:
			return true
		var head := get_head()
		if head == Vector2i(-1, -1):
			return false
		var seen := PackedByteArray()
		seen.resize(width * height)
		seen.fill(0)
		seen[head.y * width + head.x] = 1
		var queue: Array[Vector2i] = [head]
		var reached := 0
		var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			for d in dirs:
				var nb := cur + d
				if nb.x < 0 or nb.y < 0 or nb.x >= width or nb.y >= height:
					continue
				var idx: int = nb.y * width + nb.x
				if visited[idx] != 0 or seen[idx] != 0:
					continue
				if NumberPathSolver._has_barrier(barriers, cur, nb):
					continue
				seen[idx] = 1
				reached += 1
				queue.append(nb)
		return reached == remaining

	## Degree of `cell` within the remaining graph (unvisited cells + the head,
	## which is the sole visited cell a future path segment can still connect to).
	func _remaining_degree(cell: Vector2i) -> int:
		var head := get_head()
		var deg := 0
		var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for d in dirs:
			var nb := cell + d
			if nb.x < 0 or nb.y < 0 or nb.x >= width or nb.y >= height:
				continue
			if NumberPathSolver._has_barrier(barriers, cell, nb):
				continue
			var idx: int = nb.y * width + nb.x
			if visited[idx] == 0 or nb == head:
				deg += 1
		return deg

	## In a Hamiltonian path from head to the final checkpoint, the two endpoints
	## (head and final checkpoint) need degree >= 1 and every other unvisited cell
	## needs degree >= 2 in the remaining graph. A violation proves impossibility.
	func degree_condition_ok() -> bool:
		var remaining := remaining_unvisited()
		if remaining == 0:
			return true
		var head := get_head()
		if _remaining_degree(head) < 1:
			return false
		var last_cp := _last_checkpoint()
		for y in range(height):
			for x in range(width):
				if visited[y * width + x] != 0:
					continue
				var cell := Vector2i(x, y)
				var deg := _remaining_degree(cell)
				if cell == last_cp:
					if deg < 1:
						return false
				elif deg < 2:
					return false
		return true

	## Bipartite (checkerboard) parity: a path of T nodes from the head alternates
	## colors, so the remaining cells' color counts and the final checkpoint's
	## color are fully determined. A mismatch proves impossibility.
	func parity_ok() -> bool:
		var remaining := remaining_unvisited()
		if remaining == 0:
			return true
		var last_cp := _last_checkpoint()
		if last_cp == Vector2i(-1, -1):
			return true
		# If the terminal checkpoint has already been consumed, this cut cannot
		# reason about the endpoint colour; defer to the other conditions.
		if visited[last_cp.y * width + last_cp.x] != 0:
			return true
		var head := get_head()
		var head_color: int = (head.x + head.y) & 1
		# Nodes remaining to place: the head plus every unvisited cell.
		var total := remaining + 1
		var color_count := [0, 0]
		color_count[head_color] += 1
		for y in range(height):
			for x in range(width):
				if visited[y * width + x] != 0:
					continue
				color_count[(x + y) & 1] += 1
		var expected_head := (total + 1) / 2
		var expected_other := total / 2
		if color_count[head_color] != expected_head:
			return false
		if color_count[1 - head_color] != expected_other:
			return false
		# The final checkpoint sits at position total-1 of the alternating path.
		var last_pos := total - 1
		var expected_last := head_color if (last_pos & 1) == 0 else 1 - head_color
		return ((last_cp.x + last_cp.y) & 1) == expected_last
