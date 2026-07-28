class_name CrownGridLogic
extends RefCounted

## Core game state for Crown Grid. No Node or autoload dependencies.
##
## Cell state:
##   CELL_EMPTY    = 0  — untouched
##   CELL_EXCLUDED = 1  — player note (X mark)
##   CELL_CROWN    = 2  — player-placed crown
##
## Auto-mark: when enabled, placing a Crown automatically marks all same-row,
## same-column, same-region, and diagonally-adjacent cells as Excluded.
## Those auto-marks are stored in the undo entry and reverted atomically.
##
## Assistance modes:
##   ASSISTANCE_FREE   = 0  — highlights contradictions (free mode)
##   ASSISTANCE_STRICT = 1  — rejects incorrect Crown placements

const CELL_EMPTY := 0
const CELL_EXCLUDED := 1
const CELL_CROWN := 2

const ASSISTANCE_FREE := 0
const ASSISTANCE_STRICT := 1

var size: int = 0
var regions: PackedInt32Array = PackedInt32Array()
var solution: Array[int] = []  # crown_cols[row] = col

# Per-cell state: flat PackedByteArray, index = row*size+col
var cells: PackedByteArray = PackedByteArray()

var is_completed: bool = false
var hints_used: int = 0
var auto_mark: bool = false
var assistance_mode: int = ASSISTANCE_FREE

var _undo_stack: UndoStack = UndoStack.new()


# ---------------------------------------------------------------------------
# Result types
# ---------------------------------------------------------------------------

class TapResult:
	var changed: bool = false
	var cell: Vector2i = Vector2i(-1, -1)
	var new_state: int = CELL_EMPTY
	var game_won: bool = false
	var rejected: bool = false  # strict-mode crown rejection


class PaintResult:
	var changed_cells: Array[Vector2i] = []
	var game_won: bool = false


class HintResult:
	var applied: bool = false
	var cell: Vector2i = Vector2i(-1, -1)
	var new_state: int = CELL_EMPTY
	var auto_marked: Array[Vector2i] = []
	var changed_cells: Array[Vector2i] = []
	var game_won: bool = false


class UndoRedoResult:
	var action_type: String = ""
	var changed: bool = false


# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------

func init_new_game(p_size: int, p_regions: PackedInt32Array, p_solution: Array[int], p_auto_mark: bool = false, p_assistance: int = ASSISTANCE_FREE) -> void:
	size = p_size
	regions = p_regions.duplicate()
	solution = p_solution.duplicate()
	cells = PackedByteArray()
	cells.resize(size * size)
	cells.fill(CELL_EMPTY)
	is_completed = false
	hints_used = 0
	auto_mark = p_auto_mark
	assistance_mode = p_assistance
	_undo_stack.clear()


func init_from_save(data: Dictionary) -> void:
	size = int(data.get("size", 6))
	var reg_arr = data.get("regions", PackedInt32Array())
	if reg_arr is Array:
		regions = PackedInt32Array()
		for v in reg_arr:
			regions.append(int(v))
	else:
		regions = reg_arr as PackedInt32Array
	var sol_arr = data.get("solution", [])
	solution = []
	for v in sol_arr:
		solution.append(int(v))
	var cells_arr = data.get("cells", PackedByteArray())
	if cells_arr is Array:
		cells = PackedByteArray()
		for v in cells_arr:
			cells.append(int(v))
	else:
		cells = cells_arr as PackedByteArray
	if cells.size() != size * size:
		cells = PackedByteArray()
		cells.resize(size * size)
		cells.fill(CELL_EMPTY)
	is_completed = bool(data.get("is_completed", false))
	hints_used = int(data.get("hints_used", 0))
	auto_mark = bool(data.get("auto_mark", false))
	assistance_mode = int(data.get("assistance_mode", ASSISTANCE_FREE))
	var undo_entries := _deserialize_stack(data.get("undo_stack", []))
	var redo_entries := _deserialize_stack(data.get("redo_stack", []))
	_undo_stack.load_entries(undo_entries, redo_entries)
	_recompute_completion()


func serialize() -> Dictionary:
	return {
		"size": size,
		"regions": Array(regions),
		"solution": solution.duplicate(),
		"cells": Array(cells),
		"is_completed": is_completed,
		"hints_used": hints_used,
		"auto_mark": auto_mark,
		"assistance_mode": assistance_mode,
		"undo_stack": _serialize_stack(_undo_stack.get_undo_entries()),
		"redo_stack": _serialize_stack(_undo_stack.get_redo_entries()),
	}


# ---------------------------------------------------------------------------
# Gameplay actions
# ---------------------------------------------------------------------------

## Cycle the cell at (col, row): Empty → Excluded → Crown → Empty.
## In strict-mode, placing a Crown that is incorrect returns rejected=true.
func tap_cell(col: int, row: int) -> TapResult:
	var result := TapResult.new()
	if is_completed or col < 0 or col >= size or row < 0 or row >= size:
		return result
	var idx := row * size + col
	var current := int(cells[idx])
	var next := _next_state(current)

	# Strict assistance: reject incorrect crown
	if next == CELL_CROWN and assistance_mode == ASSISTANCE_STRICT:
		if solution.size() == size and int(solution[row]) != col:
			result.rejected = true
			return result

	result.cell = Vector2i(col, row)
	result.new_state = next
	result.changed = true

	var old_states: Dictionary = {}
	old_states[Vector2i(col, row)] = current

	cells[idx] = next

	var auto_marked: Array[Vector2i] = []
	if next == CELL_CROWN and auto_mark:
		auto_marked = _apply_auto_marks(col, row)
		for cell in auto_marked:
			old_states[cell] = CELL_EMPTY

	_undo_stack.push({
		"action": "tap",
		"cell": Vector2i(col, row),
		"from": current,
		"to": next,
		"auto_marked": auto_marked,
		"old_states": old_states,
	})

	_recompute_completion()
	result.game_won = is_completed
	return result


## Paint Excluded marks over a sequence of cells (drag gesture).
## Does not overwrite Crowns. Returns all cells that changed.
func paint_excluded(paint_cells: Array[Vector2i]) -> PaintResult:
	var result := PaintResult.new()
	if is_completed or paint_cells.is_empty():
		return result

	var changed: Array[Vector2i] = []
	var old_states: Dictionary = {}

	for cell in paint_cells:
		if cell.x < 0 or cell.x >= size or cell.y < 0 or cell.y >= size:
			continue
		var idx := cell.y * size + cell.x
		if int(cells[idx]) == CELL_EMPTY:
			old_states[cell] = CELL_EMPTY
			cells[idx] = CELL_EXCLUDED
			changed.append(cell)

	if changed.is_empty():
		return result

	_undo_stack.push({
		"action": "paint",
		"changed": changed,
		"old_states": old_states,
	})

	result.changed_cells = changed
	_recompute_completion()
	result.game_won = is_completed
	return result


## Apply a single hint step.
func use_hint() -> HintResult:
	var result := HintResult.new()
	if is_completed:
		return result

	# Build current board state for solver
	var crowns_by_row: Array = []
	crowns_by_row.resize(size)
	crowns_by_row.fill(-1)
	var excluded: Dictionary = {}
	for r in range(size):
		for c in range(size):
			var st := int(cells[r * size + c])
			if st == CELL_CROWN:
				crowns_by_row[r] = c
			elif st == CELL_EXCLUDED:
				excluded[Vector2i(c, r)] = true

	var step := CrownGridSolver.find_next_step(size, regions, crowns_by_row, excluded)
	if step == null:
		return result

	hints_used += 1
	result.applied = true

	if step.result == CrownGridSolver.CELL_CROWN and not step.affected_cells.is_empty():
		var hint_cell: Vector2i = step.affected_cells[0]
		result.cell = hint_cell
		result.new_state = CELL_CROWN
		var old_states: Dictionary = {}
		old_states[hint_cell] = int(cells[hint_cell.y * size + hint_cell.x])
		cells[hint_cell.y * size + hint_cell.x] = CELL_CROWN
		var auto_marked: Array[Vector2i] = []
		if auto_mark:
			auto_marked = _apply_auto_marks(hint_cell.x, hint_cell.y)
			for cell in auto_marked:
				old_states[cell] = CELL_EMPTY
		result.auto_marked = auto_marked
		_undo_stack.push({
			"action": "hint_crown",
			"cell": hint_cell,
			"auto_marked": auto_marked,
			"old_states": old_states,
		})
	else:
		var changed: Array[Vector2i] = []
		var old_states: Dictionary = {}
		for cell in step.affected_cells:
			if cell.x >= 0 and cell.x < size and cell.y >= 0 and cell.y < size:
				var idx := cell.y * size + cell.x
				if int(cells[idx]) == CELL_EMPTY:
					old_states[cell] = CELL_EMPTY
					cells[idx] = CELL_EXCLUDED
					changed.append(cell)
		if not changed.is_empty():
			result.changed_cells = changed
			_undo_stack.push({
				"action": "hint_exclude",
				"changed": changed,
				"old_states": old_states,
			})

	_recompute_completion()
	result.game_won = is_completed
	return result


func undo() -> UndoRedoResult:
	var result := UndoRedoResult.new()
	if not can_undo():
		return result
	var entry: Dictionary = _undo_stack.undo()
	_apply_undo_entry(entry)
	result.changed = true
	result.action_type = str(entry.get("action", ""))
	_recompute_completion()
	return result


func redo() -> UndoRedoResult:
	var result := UndoRedoResult.new()
	if not can_redo():
		return result
	var entry: Dictionary = _undo_stack.redo()
	_apply_redo_entry(entry)
	result.changed = true
	result.action_type = str(entry.get("action", ""))
	_recompute_completion()
	return result


func can_undo() -> bool:
	return not is_completed and _undo_stack.can_undo()


func can_redo() -> bool:
	return not is_completed and _undo_stack.can_redo()


func get_cell(col: int, row: int) -> int:
	if col < 0 or col >= size or row < 0 or row >= size:
		return CELL_EMPTY
	return int(cells[row * size + col])


func get_region(col: int, row: int) -> int:
	if col < 0 or col >= size or row < 0 or row >= size or regions.is_empty():
		return -1
	return regions[row * size + col]


## Returns a list of contradiction cells (Crowns that violate rules) in free mode.
func get_violations() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if assistance_mode != ASSISTANCE_FREE:
		return result

	# Collect crown positions
	var crown_cells: Array[Vector2i] = []
	for r in range(size):
		for c in range(size):
			if int(cells[r * size + c]) == CELL_CROWN:
				crown_cells.append(Vector2i(c, r))

	var violations: Dictionary = {}

	# Check row/column/region uniqueness
	for i in range(crown_cells.size()):
		for j in range(i + 1, crown_cells.size()):
			var a: Vector2i = crown_cells[i]
			var b: Vector2i = crown_cells[j]
			var conflict := false
			if a.y == b.y:
				conflict = true
			if a.x == b.x:
				conflict = true
			if not regions.is_empty() and regions[a.y * size + a.x] == regions[b.y * size + b.x]:
				conflict = true
			if absi(a.y - b.y) == 1 and absi(a.x - b.x) == 1:
				conflict = true
			if conflict:
				violations[a] = true
				violations[b] = true

	for cell in violations:
		result.append(cell)
	return result


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _next_state(current: int) -> int:
	match current:
		CELL_EMPTY:
			return CELL_EXCLUDED
		CELL_EXCLUDED:
			return CELL_CROWN
		CELL_CROWN:
			return CELL_EMPTY
		_:
			return CELL_EMPTY


func _apply_auto_marks(crown_col: int, crown_row: int) -> Array[Vector2i]:
	var marked: Array[Vector2i] = []
	var crown_reg := regions[crown_row * size + crown_col]
	var target_cells: Array[Vector2i] = []

	# Row
	for c in range(size):
		if c != crown_col:
			target_cells.append(Vector2i(c, crown_row))
	# Column
	for r in range(size):
		if r != crown_row:
			target_cells.append(Vector2i(crown_col, r))
	# Region
	for r in range(size):
		for c in range(size):
			if regions[r * size + c] == crown_reg and not (r == crown_row and c == crown_col):
				target_cells.append(Vector2i(c, r))
	# Diagonal neighbors
	for dr in [-1, 1]:
		for dc in [-1, 1]:
			var nr := crown_row + dr
			var nc := crown_col + dc
			if nr >= 0 and nr < size and nc >= 0 and nc < size:
				target_cells.append(Vector2i(nc, nr))

	# Deduplicate and apply
	var seen: Dictionary = {}
	for cell in target_cells:
		if seen.has(cell):
			continue
		seen[cell] = true
		var idx := cell.y * size + cell.x
		if int(cells[idx]) == CELL_EMPTY:
			cells[idx] = CELL_EXCLUDED
			marked.append(cell)

	return marked


func _apply_undo_entry(entry: Dictionary) -> void:
	var action := str(entry.get("action", ""))
	match action:
		"tap", "hint_crown":
			var cell: Vector2i = entry.get("cell", Vector2i(-1, -1))
			var old_from: int = int(entry.get("from", CELL_EMPTY))
			if cell.x >= 0:
				cells[cell.y * size + cell.x] = old_from
			# Restore auto-marked cells
			var auto_marked: Array = entry.get("auto_marked", [])
			for am in auto_marked:
				var amc := am as Vector2i
				cells[amc.y * size + amc.x] = CELL_EMPTY
		"paint", "hint_exclude":
			var old_states: Dictionary = entry.get("old_states", {})
			for cell in old_states:
				var v := cell as Vector2i
				cells[v.y * size + v.x] = int(old_states[cell])


func _apply_redo_entry(entry: Dictionary) -> void:
	var action := str(entry.get("action", ""))
	match action:
		"tap":
			var cell: Vector2i = entry.get("cell", Vector2i(-1, -1))
			var to: int = int(entry.get("to", CELL_EMPTY))
			if cell.x >= 0:
				cells[cell.y * size + cell.x] = to
			if to == CELL_CROWN and auto_mark:
				var auto_marked: Array = entry.get("auto_marked", [])
				for am in auto_marked:
					var amc := am as Vector2i
					cells[amc.y * size + amc.x] = CELL_EXCLUDED
		"hint_crown":
			var cell: Vector2i = entry.get("cell", Vector2i(-1, -1))
			if cell.x >= 0:
				cells[cell.y * size + cell.x] = CELL_CROWN
			if auto_mark:
				var auto_marked: Array = entry.get("auto_marked", [])
				for am in auto_marked:
					var amc := am as Vector2i
					cells[amc.y * size + amc.x] = CELL_EXCLUDED
		"paint", "hint_exclude":
			var changed: Array = entry.get("changed", [])
			for cell in changed:
				var v := cell as Vector2i
				cells[v.y * size + v.x] = CELL_EXCLUDED


func _recompute_completion() -> void:
	if regions.is_empty() or solution.is_empty():
		is_completed = false
		return
	var crown_cols: Array[int] = []
	crown_cols.resize(size)
	crown_cols.fill(-1)
	for r in range(size):
		for c in range(size):
			if int(cells[r * size + c]) == CELL_CROWN:
				if crown_cols[r] >= 0:
					# Two crowns in same row
					is_completed = false
					return
				crown_cols[r] = c
	is_completed = CrownGridSolver.validate_solution(size, regions, crown_cols)


# ---------------------------------------------------------------------------
# Serialisation helpers
# ---------------------------------------------------------------------------

func _serialize_stack(stack: Array[Dictionary]) -> Array:
	var result: Array = []
	for entry in stack:
		var e: Dictionary = {}
		e["action"] = str(entry.get("action", ""))
		if entry.has("cell"):
			var c: Vector2i = entry["cell"]
			e["cell"] = [c.x, c.y]
		if entry.has("from"):
			e["from"] = int(entry["from"])
		if entry.has("to"):
			e["to"] = int(entry["to"])
		if entry.has("auto_marked"):
			var am: Array = []
			for v in entry["auto_marked"]:
				var cell := v as Vector2i
				am.append([cell.x, cell.y])
			e["auto_marked"] = am
		if entry.has("old_states"):
			var os_out: Dictionary = {}
			for cell in entry["old_states"]:
				var vc := cell as Vector2i
				os_out["%d,%d" % [vc.x, vc.y]] = int(entry["old_states"][cell])
			e["old_states"] = os_out
		if entry.has("changed"):
			var ch: Array = []
			for v in entry["changed"]:
				var vc := v as Vector2i
				ch.append([vc.x, vc.y])
			e["changed"] = ch
		result.append(e)
	return result


func _deserialize_stack(data: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (data is Array):
		return result
	for raw in data:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = {}
		entry["action"] = str(raw.get("action", ""))
		if raw.has("cell"):
			var ca = raw["cell"]
			if ca is Array and ca.size() >= 2:
				entry["cell"] = Vector2i(int(ca[0]), int(ca[1]))
		if raw.has("from"):
			entry["from"] = int(raw["from"])
		if raw.has("to"):
			entry["to"] = int(raw["to"])
		if raw.has("auto_marked"):
			var am: Array[Vector2i] = []
			for v in raw["auto_marked"]:
				if v is Array and v.size() >= 2:
					am.append(Vector2i(int(v[0]), int(v[1])))
			entry["auto_marked"] = am
		if raw.has("old_states"):
			var os_in: Dictionary = {}
			for key in raw["old_states"]:
				var parts := str(key).split(",")
				if parts.size() == 2:
					os_in[Vector2i(int(parts[0]), int(parts[1]))] = int(raw["old_states"][key])
			entry["old_states"] = os_in
		if raw.has("changed"):
			var ch: Array[Vector2i] = []
			for v in raw["changed"]:
				if v is Array and v.size() >= 2:
					ch.append(Vector2i(int(v[0]), int(v[1])))
			entry["changed"] = ch
		result.append(entry)
	return result
