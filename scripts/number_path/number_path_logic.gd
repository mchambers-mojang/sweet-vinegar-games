class_name NumberPathLogic
extends RefCounted

## Core logic for Number Path.
## Owns: path state, move/truncate results, checkpoint ordering, barrier checks,
## contradiction detection, hints, completion flag, and UndoStack.
## Board input translates pointer movement to cell transitions; it never
## decides rule validity.

# --- Tier constants ---
const TIER_EASY := 0
const TIER_MEDIUM := 1
const TIER_HARD := 2
const TIER_EXPERT := 3

# --- State ---
var grid_width: int = 0
var grid_height: int = 0
var tier: int = TIER_EASY
var random_seed: int = 0

## Ordered checkpoint cells: checkpoints[0] = start (number 1), last = finish.
## Each entry: {"x": int, "y": int, "n": int}
var checkpoints: Array[Dictionary] = []

## Barrier set: Array of {"r": int, "c": int, "dir": int} where dir is
## DIR_RIGHT (barrier on right edge of (r,c)) or DIR_DOWN (barrier on bottom).
var barriers: Array[Dictionary] = []

## Canonical single solution path: Array[Vector2i]
var solution_path: Array[Vector2i] = []

## Current player path: Array[Vector2i]
var current_path: Array[Vector2i] = []

var is_completed: bool = false
var hints_used: int = 0
var has_contradiction: bool = false

var _undo_stack: UndoStack = UndoStack.new()

# Barrier direction constants
const DIR_RIGHT := 0
const DIR_DOWN := 1

# --- Inner result classes ---

class ExtendResult:
	var accepted: bool = false
	var game_won: bool = false
	var contradiction: bool = false

class TruncateResult:
	var truncated: bool = false
	var new_length: int = 0

class HintResult:
	var cell: Vector2i = Vector2i(-1, -1)
	var valid: bool = false
	var game_won: bool = false
	var contradiction_highlighted: bool = false

class UndoRedoResult:
	var performed: bool = false
	var action: String = ""


# --- Initialisation ---

func init_new_game(w: int, h: int, t: int, seed_val: int, gen_data: Dictionary) -> void:
	grid_width = w
	grid_height = h
	tier = t
	random_seed = seed_val
	checkpoints = _deserialize_checkpoints(gen_data.get("checkpoints", []))
	barriers = _deserialize_barriers(gen_data.get("barriers", []))
	solution_path = _deserialize_path(gen_data.get("solution_path", []))
	current_path.clear()
	# Start the path at checkpoint 1
	if not checkpoints.is_empty():
		var start := checkpoints[0]
		current_path.append(Vector2i(int(start.get("x", 0)), int(start.get("y", 0))))
	is_completed = false
	hints_used = 0
	has_contradiction = false
	_undo_stack.clear()


func init_from_save(data: Dictionary) -> void:
	grid_width = int(data.get("width", 5))
	grid_height = int(data.get("height", 5))
	tier = int(data.get("tier", TIER_EASY))
	random_seed = int(data.get("random_seed", 0))
	checkpoints = _deserialize_checkpoints(data.get("checkpoints", []))
	barriers = _deserialize_barriers(data.get("barriers", []))
	solution_path = _deserialize_path(data.get("solution_path", []))
	current_path = _deserialize_path(data.get("current_path", []))
	is_completed = bool(data.get("is_completed", false))
	hints_used = int(data.get("hints_used", 0))
	has_contradiction = bool(data.get("has_contradiction", false))
	var undo_entries := _deserialize_undo_stack(data.get("undo_stack", []))
	var redo_entries := _deserialize_undo_stack(data.get("redo_stack", []))
	_undo_stack.load_entries(undo_entries, redo_entries)
	_validate_path()


func serialize() -> Dictionary:
	return {
		"width": grid_width,
		"height": grid_height,
		"tier": tier,
		"random_seed": random_seed,
		"checkpoints": _serialize_checkpoints(checkpoints),
		"barriers": _serialize_barriers(barriers),
		"solution_path": _serialize_path(solution_path),
		"current_path": _serialize_path(current_path),
		"is_completed": is_completed,
		"hints_used": hints_used,
		"has_contradiction": has_contradiction,
		"undo_stack": _serialize_undo_stack(_undo_stack.get_undo_entries()),
		"redo_stack": _serialize_undo_stack(_undo_stack.get_redo_entries()),
	}


# --- Path manipulation ---

## Try to extend path to the given cell.
## Returns ExtendResult.
func try_extend(cell: Vector2i) -> ExtendResult:
	var result := ExtendResult.new()
	if is_completed:
		return result
	if current_path.is_empty():
		return result

	var head: Vector2i = current_path[current_path.size() - 1]

	# Must be orthogonally adjacent
	if not _are_adjacent(head, cell):
		return result

	# Must not cross a barrier
	if _has_barrier_between(head, cell):
		return result

	# Must be in bounds
	if not _in_bounds(cell):
		return result

	# Must not revisit a cell already in the path
	if _is_in_path(cell):
		result.contradiction = true
		has_contradiction = true
		return result

	# Checkpoint order: if cell is a checkpoint, it must be the next expected one
	var cp_index := _checkpoint_index_at(cell)
	if cp_index >= 0:
		var next_cp := _next_checkpoint_index()
		if cp_index != next_cp:
			result.contradiction = true
			has_contradiction = true
			return result

	# Accepted
	var _pre_snap := _serialize_path(current_path)
	current_path.append(cell)
	_undo_stack.push({
		"action": "extend",
		"pre_snapshot": _pre_snap,
		"post_snapshot": _serialize_path(current_path),
	})
	result.accepted = true
	has_contradiction = false
	_check_completion()
	result.game_won = is_completed
	return result


## Try to truncate path back to the given cell (backward drag).
## The cell must be in the current path; path is trimmed to that cell.
## Returns TruncateResult.
func try_truncate(cell: Vector2i) -> TruncateResult:
	var result := TruncateResult.new()
	if is_completed:
		return result
	if current_path.is_empty():
		return result

	# The start cell (checkpoint 1) cannot be removed
	var start_cell: Vector2i = current_path[0]
	if cell == start_cell:
		return result

	# Find cell index in path
	var target_idx := -1
	for i in range(current_path.size() - 1, -1, -1):
		if current_path[i] == cell:
			target_idx = i
			break

	if target_idx < 0:
		return result

	# Don't truncate if cell is already the head
	if target_idx == current_path.size() - 1:
		return result

	var _pre_snap := _serialize_path(current_path)
	# Keep 0..target_idx
	while current_path.size() > target_idx + 1:
		current_path.pop_back()
	_undo_stack.push({
		"action": "truncate",
		"pre_snapshot": _pre_snap,
		"post_snapshot": _serialize_path(current_path),
	})
	result.truncated = true
	result.new_length = current_path.size()
	has_contradiction = false
	return result


## Undo last extend or truncate.
func undo() -> UndoRedoResult:
	var result := UndoRedoResult.new()
	if not _undo_stack.can_undo():
		return result
	var entry := _undo_stack.undo()
	# pre_snapshot holds the state before the action; fall back to legacy path_snapshot
	var snap: Variant = entry.get("pre_snapshot", entry.get("path_snapshot", []))
	current_path = _deserialize_path(snap)
	has_contradiction = false
	result.performed = true
	result.action = str(entry.get("action", ""))
	return result


## Redo last undone operation.
func redo() -> UndoRedoResult:
	var result := UndoRedoResult.new()
	if not _undo_stack.can_redo():
		return result
	var entry := _undo_stack.redo()
	# post_snapshot holds the state after the action; fall back to legacy path_snapshot
	var snap: Variant = entry.get("post_snapshot", entry.get("path_snapshot", []))
	current_path = _deserialize_path(snap)
	has_contradiction = false
	result.performed = true
	result.action = str(entry.get("action", ""))
	return result


func can_undo() -> bool:
	return not is_completed and _undo_stack.can_undo()


func can_redo() -> bool:
	return not is_completed and _undo_stack.can_redo()


# --- Hints ---

## Use a hint: extend path by one correct cell, or highlight contradiction.
func use_hint() -> HintResult:
	var result := HintResult.new()
	if is_completed:
		return result

	# If current path contradicts every solution, highlight contradiction
	if not _current_path_matches_solution_prefix():
		result.contradiction_highlighted = true
		has_contradiction = true
		return result

	# Find the next correct cell
	var next_cell := _get_next_solution_cell()
	if next_cell == Vector2i(-1, -1):
		return result

	var extend := try_extend(next_cell)
	if not extend.accepted:
		return result

	hints_used += 1
	result.cell = next_cell
	result.valid = true
	result.game_won = extend.game_won
	return result


func can_hint() -> bool:
	return not is_completed


# --- Queries ---

func get_head() -> Vector2i:
	if current_path.is_empty():
		return Vector2i(-1, -1)
	return current_path[current_path.size() - 1]


func get_start() -> Vector2i:
	if current_path.is_empty():
		return Vector2i(-1, -1)
	return current_path[0]


func is_cell_in_path(cell: Vector2i) -> bool:
	return _is_in_path(cell)


func get_path_index(cell: Vector2i) -> int:
	for i in range(current_path.size()):
		if current_path[i] == cell:
			return i
	return -1


func has_barrier_between(a: Vector2i, b: Vector2i) -> bool:
	return _has_barrier_between(a, b)


func get_checkpoint_number_at(cell: Vector2i) -> int:
	for cp in checkpoints:
		var cx := int(cp.get("x", -1))
		var cy := int(cp.get("y", -1))
		if cx == cell.x and cy == cell.y:
			return int(cp.get("n", -1))
	return -1


# --- Private helpers ---

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_width and cell.y < grid_height


func _are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return (dx == 1 and dy == 0) or (dx == 0 and dy == 1)


func _is_in_path(cell: Vector2i) -> bool:
	for c in current_path:
		if c == cell:
			return true
	return false


func _has_barrier_between(a: Vector2i, b: Vector2i) -> bool:
	# a and b must be orthogonally adjacent
	if a.x == b.x:
		# vertical adjacency
		var top := a if a.y < b.y else b
		for barrier in barriers:
			if int(barrier.get("r", -1)) == top.y and int(barrier.get("c", -1)) == top.x and int(barrier.get("dir", -1)) == DIR_DOWN:
				return true
	else:
		# horizontal adjacency
		var left := a if a.x < b.x else b
		for barrier in barriers:
			if int(barrier.get("r", -1)) == left.y and int(barrier.get("c", -1)) == left.x and int(barrier.get("dir", -1)) == DIR_RIGHT:
				return true
	return false


func _checkpoint_index_at(cell: Vector2i) -> int:
	for i in range(checkpoints.size()):
		var cp: Dictionary = checkpoints[i]
		if int(cp.get("x", -1)) == cell.x and int(cp.get("y", -1)) == cell.y:
			return i
	return -1


## Return the index of the next checkpoint the path must visit.
## Returns -1 if all checkpoints have been visited.
func _next_checkpoint_index() -> int:
	# Count how many checkpoints are already in the path
	var visited := 0
	for cp in checkpoints:
		var cv := Vector2i(int(cp.get("x", -1)), int(cp.get("y", -1)))
		if _is_in_path(cv):
			visited += 1
		else:
			break
	if visited >= checkpoints.size():
		return -1
	return visited


func _check_completion() -> void:
	if current_path.size() != grid_width * grid_height:
		return
	# All checkpoints must be in path in order
	for cp in checkpoints:
		var cv := Vector2i(int(cp.get("x", -1)), int(cp.get("y", -1)))
		if not _is_in_path(cv):
			return
	# Head must be at last checkpoint
	var last_cp: Dictionary = checkpoints[checkpoints.size() - 1]
	var last_cell := Vector2i(int(last_cp.get("x", -1)), int(last_cp.get("y", -1)))
	if get_head() != last_cell:
		return
	is_completed = true


func _current_path_matches_solution_prefix() -> bool:
	if solution_path.is_empty():
		return true
	if current_path.size() > solution_path.size():
		return false
	for i in range(current_path.size()):
		if current_path[i] != solution_path[i]:
			return false
	return true


func _get_next_solution_cell() -> Vector2i:
	if solution_path.size() <= current_path.size():
		return Vector2i(-1, -1)
	return solution_path[current_path.size()]


func _validate_path() -> void:
	# Verify path integrity: in-bounds, adjacent, no revisits, no barrier crossings,
	# and checkpoints visited in order.
	if current_path.is_empty():
		return
	var seen: Dictionary = {}
	var prev: Vector2i = Vector2i(-1, -1)
	var valid_path: Array[Vector2i] = []
	var next_cp_idx := 0
	for cell in current_path:
		if not _in_bounds(cell):
			break
		if seen.has(cell):
			break
		if prev != Vector2i(-1, -1):
			if not _are_adjacent(prev, cell):
				break
			if _has_barrier_between(prev, cell):
				break
		# Checkpoint ordering: if this cell is a checkpoint it must be the next expected one
		var cp_idx := _checkpoint_index_at(cell)
		if cp_idx >= 0:
			if cp_idx != next_cp_idx:
				break
			next_cp_idx += 1
		seen[cell] = true
		valid_path.append(cell)
		prev = cell
	current_path = valid_path


# --- Serialisation helpers ---

func _serialize_checkpoints(cps: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cp in cps:
		result.append(cp.duplicate())
	return result


func _deserialize_checkpoints(data: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				result.append(entry.duplicate())
	return result


func _serialize_barriers(bs: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for b in bs:
		result.append(b.duplicate())
	return result


func _deserialize_barriers(data: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				result.append(entry.duplicate())
	return result


func _serialize_path(path: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in path:
		result.append({"x": cell.x, "y": cell.y})
	return result


func _deserialize_path(data: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				result.append(Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))))
			elif entry is Vector2i:
				result.append(entry)
	return result


func _serialize_undo_stack(entries: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		result.append({
			"action": str(entry.get("action", "")),
			"pre_snapshot": entry.get("pre_snapshot", entry.get("path_snapshot", [])).duplicate(true),
			"post_snapshot": entry.get("post_snapshot", entry.get("path_snapshot", [])).duplicate(true),
		})
	return result


func _deserialize_undo_stack(data: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				result.append({
					"action": str(entry.get("action", "")),
					"pre_snapshot": entry.get("pre_snapshot", entry.get("path_snapshot", [])).duplicate(true),
					"post_snapshot": entry.get("post_snapshot", entry.get("path_snapshot", [])).duplicate(true),
				})
	return result
