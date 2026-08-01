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

# --- Public API ---

## Solve a puzzle using human-style deductions.
## Returns {"solved": bool, "path": Array[Vector2i], "steps": Array[Dictionary],
##          "max_rank": int}
## Steps: [{"rank": int, "reason": str, "affected": Array[Vector2i], "result": Vector2i}]
static func solve(
		width: int,
		height: int,
		checkpoints: Array[Dictionary],
		barriers: Array[Dictionary]) -> Dictionary:
	var state := _SolverState.new(width, height, checkpoints, barriers)
	var steps: Array[Dictionary] = []
	var max_rank := 0

	while not state.is_complete():
		var step := _try_deduce(state)
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

	_count_dfs(width, height, checkpoints, barriers, path, visited,
			counter, cancelled, max_count, cancel_check)

	if cancelled[0]:
		return -1
	return counter[0]


# --- Private: deduction engine ---

static func _try_deduce(state: _SolverState) -> Dictionary:
	# Rank 1: forced moves
	var step := _rank1_forced(state)
	if not step.is_empty():
		return step

	# Rank 2: local constraints / bottleneck
	step = _rank2_local(state)
	if not step.is_empty():
		return step

	# Rank 3: region connectivity
	step = _rank3_region(state)
	if not step.is_empty():
		return step

	# Rank 4: global chain
	step = _rank4_global(state)
	return step


static func _rank1_forced(state: _SolverState) -> Dictionary:
	var head := state.get_head()
	var candidates := state.free_neighbors(head)

	# Exactly one free neighbor → forced
	if candidates.size() == 1:
		var cell: Vector2i = candidates[0]
		if not state.is_checkpoint_valid_next(cell):
			return {}
		return {
			"rank": RANK_FORCED,
			"reason": "single free neighbor",
			"affected": [head],
			"result": cell,
		}

	# Next unvisited checkpoint has only one reachable approach
	var next_cp := state.next_checkpoint()
	if next_cp != Vector2i(-1, -1):
		var cp_neighbors := state.free_neighbors(next_cp)
		var reachable: Array[Vector2i] = []
		for nb in cp_neighbors:
			if state.can_reach_from_head(nb):
				reachable.append(nb)
		if reachable.size() == 1 and reachable[0] == head:
			if state.is_adjacent_reachable_from_head(next_cp):
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




static func _rank2_local(state: _SolverState) -> Dictionary:
	var head := state.get_head()
	var candidates := state.free_neighbors(head)
	if candidates.size() < 2:
		return {}

	# Bottleneck: one candidate is the only cell connecting two free regions
	for nb in candidates:
		if not state.is_checkpoint_valid_next(nb):
			continue
		if state.is_bottleneck(nb):
			return {
				"rank": RANK_LOCAL,
				"reason": "bottleneck cell",
				"affected": [nb],
				"result": nb,
			}

	# Two-constraint intersection: only one candidate satisfies both local degree and checkpoint constraints
	var valid: Array[Vector2i] = []
	for nb in candidates:
		if state.is_checkpoint_valid_next(nb):
			if state.free_neighbor_count_after_extend(nb) > 0 or state.remaining_unvisited() == 1:
				valid.append(nb)
	if valid.size() == 1:
		return {
			"rank": RANK_LOCAL,
			"reason": "two-constraint intersection",
			"affected": candidates,
			"result": valid[0],
		}

	return {}


static func _rank3_region(state: _SolverState) -> Dictionary:
	var head := state.get_head()
	var candidates := state.free_neighbors(head)
	if candidates.is_empty():
		return {}

	# Prune candidates that would disconnect the remaining free region
	var valid: Array[Vector2i] = []
	for nb in candidates:
		if not state.is_checkpoint_valid_next(nb):
			continue
		if state.remaining_stays_connected_after(nb):
			valid.append(nb)

	if valid.size() == 1:
		return {
			"rank": RANK_REGION,
			"reason": "region connectivity",
			"affected": candidates,
			"result": valid[0],
		}

	return {}


static func _rank4_global(state: _SolverState) -> Dictionary:
	var head := state.get_head()
	var candidates := state.free_neighbors(head)
	if candidates.is_empty():
		return {}

	# Try each candidate: discard any that cannot lead to a complete Hamiltonian path
	# visiting checkpoints in order without guessing.
	var valid: Array[Vector2i] = []
	for nb in candidates:
		if not state.is_checkpoint_valid_next(nb):
			continue
		if state.can_complete_from(nb):
			valid.append(nb)

	if valid.size() == 1:
		return {
			"rank": RANK_GLOBAL,
			"reason": "global path constraint",
			"affected": candidates,
			"result": valid[0],
		}

	return {}


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
		cancel_check: Callable) -> void:
	if cancelled[0]:
		return
	if cancel_check.is_valid() and cancel_check.call():
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
		_count_dfs(width, height, checkpoints, barriers, path, visited, counter, cancelled, max_count, cancel_check)
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

	func is_bottleneck(cell: Vector2i) -> bool:
		# Check if cell is the only connection between two components of free cells
		# (excluding head's current position which is about to be extended)
		if visited[cell.y * width + cell.x] != 0:
			return false
		# Temporarily mark cell as visited and check if free region splits
		visited[cell.y * width + cell.x] = 1
		var split := _free_region_splits()
		visited[cell.y * width + cell.x] = 0
		return split

	func _free_region_splits() -> bool:
		# Find all free cells (unvisited)
		var free_cells: Array[Vector2i] = []
		for y in range(height):
			for x in range(width):
				if visited[y * width + x] == 0:
					free_cells.append(Vector2i(x, y))
		if free_cells.is_empty():
			return false
		# BFS from first free cell
		var start: Vector2i = free_cells[0]
		var seen := PackedByteArray()
		seen.resize(width * height)
		seen.fill(0)
		var queue: Array[Vector2i] = [start]
		seen[start.y * width + start.x] = 1
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			for d in dirs:
				var nb := cur + d
				if nb.x < 0 or nb.y < 0 or nb.x >= width or nb.y >= height:
					continue
				if visited[nb.y * width + nb.x] != 0:
					continue
				if seen[nb.y * width + nb.x] != 0:
					continue
				if NumberPathSolver._has_barrier(barriers, cur, nb):
					continue
				seen[nb.y * width + nb.x] = 1
				queue.append(nb)
		# If any free cell was not reached, region split
		for cell in free_cells:
			if seen[cell.y * width + cell.x] == 0:
				return true
		return false

	func would_isolate_cell_if_not_extended_to(other: Vector2i) -> bool:
		# Check if 'other' has only one free neighbor (degree 1) in current state
		# (not counting the head which will be extended elsewhere)
		var other_neighbors := free_neighbors(other)
		return other_neighbors.size() == 1 and other_neighbors[0] == get_head()

	func remaining_stays_connected_after(cell: Vector2i) -> bool:
		# Extend to cell and check remaining free cells + head are all connected
		visited[cell.y * width + cell.x] = 1
		var result := not _free_region_splits()
		# Also check head can still reach all free cells
		visited[cell.y * width + cell.x] = 0
		return result

	func can_complete_from(cell: Vector2i) -> bool:
		# Quick connectivity heuristic: after extending to cell,
		# can we reach all remaining cells and checkpoints?
		# _count_reachable_from counts 'cell' itself, so compare against
		# (total - already-visited), which also includes 'cell'.
		visited[cell.y * width + cell.x] = 1
		var reachable := _count_reachable_from(cell)
		var remaining := width * height - path.size()
		visited[cell.y * width + cell.x] = 0
		return reachable == remaining

	func _count_reachable_from(start: Vector2i) -> int:
		var count := 0
		var seen := PackedByteArray()
		seen.resize(width * height)
		seen.fill(0)
		var queue: Array[Vector2i] = [start]
		seen[start.y * width + start.x] = 1
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			count += 1
			var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			for d in dirs:
				var nb := cur + d
				if nb.x < 0 or nb.y < 0 or nb.x >= width or nb.y >= height:
					continue
				if visited[nb.y * width + nb.x] != 0:
					continue
				if seen[nb.y * width + nb.x] != 0:
					continue
				if NumberPathSolver._has_barrier(barriers, cur, nb):
					continue
				seen[nb.y * width + nb.x] = 1
				queue.append(nb)
		return count
