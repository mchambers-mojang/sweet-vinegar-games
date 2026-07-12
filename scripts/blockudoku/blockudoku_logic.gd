class_name BlockudokuLogic
extends RefCounted

## Pure game logic for Blockudoku — no autoloads, no nodes, no signals, no side effects.
## Takes state + player action and returns a result object.
## The Game Screen is the orchestrator: it feeds actions here, then dispatches
## side effects (sound, haptics, replay, effects, saves) based on the result.

const GRID_SIZE := 9
const BOX_SIZE := 3
const BLOCKS_PER_SET := 3

# Config (set at construction, not read from autoloads)
var rotation_mode: bool = false

# Game state
var board_grid: Array[int] = []
var score: int = 0
var turns: int = 0
var combo_count: int = 0
var is_game_over: bool = false
var available_blocks: Array[Array] = []
var blocks_placed_this_set: int = 0

# Undo/redo history — owned here so all games store history in the logic layer.
var _undo_stack: UndoStack = UndoStack.new()


## Result returned by try_place().  Carries everything the orchestrator needs
## to dispatch side effects and update UI — no rule logic belongs there.
class PlaceResult:
	var valid: bool = false
	var cells_placed: int = 0
	var score_delta: int = 0
	var lines_cleared: int = 0
	var boxes_cleared: int = 0
	var total_cells_cleared: int = 0
	var combo: int = 0
	var combo_bonus: int = 0
	## True when all 3 blocks in the current set were placed; the orchestrator
	## should call deal_blocks() with fresh shapes, then check can_any_piece_fit().
	var new_blocks_dealt: bool = false
	## True when no remaining piece can be placed (computed only when
	## new_blocks_dealt is false, because new shapes may open valid moves).
	var game_over: bool = false
	## Array of Vector2i — positions of cells just placed (for visual effects)
	var placed_cells: Array = []
	## Array of Vector2i — positions of cells cleared (for visual effects)
	var clear_cells: Array = []


func _init(p_rotation_mode: bool = false) -> void:
	rotation_mode = p_rotation_mode
	_init_grid()


func _init_grid() -> void:
	board_grid.resize(GRID_SIZE * GRID_SIZE)
	board_grid.fill(0)


func reset() -> void:
	_init_grid()
	score = 0
	turns = 0
	combo_count = 0
	is_game_over = false
	available_blocks = []
	blocks_placed_this_set = 0
	_undo_stack.clear()


# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

## Validate and execute a placement.  Returns result with all info needed to
## dispatch side effects.  State is mutated only on a valid placement.
func try_place(block_index: int, grid_pos: Vector2i) -> PlaceResult:
	var result := PlaceResult.new()

	if block_index < 0 or block_index >= available_blocks.size():
		return result
	var shape: Array = available_blocks[block_index]
	if shape.is_empty():
		return result
	if not can_place(shape, grid_pos.x, grid_pos.y):
		return result

	result.valid = true
	result.cells_placed = shape.size()

	# Compute placed cell positions for visual effects
	for cell in shape:
		var c: Vector2i = cell
		result.placed_cells.append(Vector2i(grid_pos.x + c.x, grid_pos.y + c.y))

	# Place on grid
	_place_on_grid(shape, grid_pos)

	# Score for placement (one point per cell placed)
	score += shape.size()
	result.score_delta += shape.size()
	turns += 1

	# Remove placed block from available set
	available_blocks[block_index] = []
	blocks_placed_this_set += 1

	# Check and clear full lines/columns/boxes
	var clear_result := _check_and_clear_grid()
	var cleared: int = clear_result["cleared"]
	var lines: int = clear_result["lines"]
	var boxes: int = clear_result["boxes"]
	result.lines_cleared = lines
	result.boxes_cleared = boxes
	result.total_cells_cleared = cleared
	result.clear_cells = clear_result["cells"]

	if cleared > 0:
		combo_count += 1
		var combo_bonus := combo_count * 10 if combo_count > 1 else 0
		var clear_score := (lines + boxes) * 18 + cleared + combo_bonus
		score += clear_score
		result.score_delta += clear_score
		result.combo = combo_count
		result.combo_bonus = combo_bonus
	else:
		combo_count = 0

	# New set of blocks needed?
	if blocks_placed_this_set >= BLOCKS_PER_SET:
		result.new_blocks_dealt = true
		# Game-over cannot be determined here: the orchestrator must call
		# deal_blocks() with fresh shapes and then check can_any_piece_fit().
	else:
		# Check game over with remaining pieces
		if not _has_valid_move_for_remaining():
			is_game_over = true
			result.game_over = true

	return result


## Rotate the block at block_index clockwise. Mutates available_blocks in place.
## Returns true if the shape was non-empty and the rotation was applied.
func apply_rotation(block_index: int) -> bool:
	if block_index < 0 or block_index >= available_blocks.size():
		return false
	var shape: Array = available_blocks[block_index]
	if shape.is_empty():
		return false
	available_blocks[block_index] = _rotate_clockwise(shape)
	return true


## Return the rotated shape WITHOUT mutating state (for preview / replay).
func try_rotate(block_index: int) -> Array:
	if block_index < 0 or block_index >= available_blocks.size():
		return []
	var shape: Array = available_blocks[block_index]
	if shape.is_empty():
		return []
	return _rotate_clockwise(shape)


# ---------------------------------------------------------------------------
# Block dealing
# ---------------------------------------------------------------------------

## Replace available_blocks with the given shapes and reset blocks_placed_this_set.
## Called by the orchestrator after PlaceResult.new_blocks_dealt == true.
func deal_blocks(new_shapes: Array[Array]) -> void:
	available_blocks = new_shapes.duplicate(true)
	blocks_placed_this_set = 0


# ---------------------------------------------------------------------------
# Game-over queries
# ---------------------------------------------------------------------------

## True if at least one remaining (non-empty) piece has a valid placement,
## considering rotation_mode.
func can_any_piece_fit() -> bool:
	var remaining: Array = []
	for s in available_blocks:
		if (s as Array).size() > 0:
			remaining.append(s)
	return _check_valid_move(remaining)


## True if at least one of the given shapes can be placed somewhere on the board.
func has_valid_placement(shapes: Array) -> bool:
	for shape in shapes:
		for r in GRID_SIZE:
			for c in GRID_SIZE:
				if can_place(shape, c, r):
					return true
	return false


# ---------------------------------------------------------------------------
# Placement validation (public so the orchestrator can pre-validate)
# ---------------------------------------------------------------------------

func can_place(shape: Array, grid_col: int, grid_row: int) -> bool:
	for cell in shape:
		var c: Vector2i = cell
		var col := grid_col + c.x
		var row := grid_row + c.y
		if col < 0 or col >= GRID_SIZE or row < 0 or row >= GRID_SIZE:
			return false
		if board_grid[row * GRID_SIZE + col] != 0:
			return false
	return true


# ---------------------------------------------------------------------------
# Undo/redo history
# ---------------------------------------------------------------------------

## True if there is a move to undo.
func can_undo() -> bool:
	return _undo_stack.can_undo()


## True if there is a move to redo.
func can_redo() -> bool:
	return _undo_stack.can_redo()


## Record a before/after move pair in the undo stack (clears redo history).
func push_move(before: Dictionary, after: Dictionary) -> void:
	_undo_stack.push({"before": before, "after": after})


## Pop the most recent move for undo; returns the "before" state to restore.
## Returns an empty dict if there is nothing to undo.
func undo_move() -> Dictionary:
	var entry := _undo_stack.undo()
	return entry.get("before", {})


## Pop the most recent undone move for redo; returns the "after" state to restore.
## Returns an empty dict if there is nothing to redo.
func redo_move() -> Dictionary:
	var entry := _undo_stack.redo()
	return entry.get("after", {})


## Clear only the redo history (e.g. when a game-over path invalidates redo
## without recording a new undo entry).
func clear_redo() -> void:
	_undo_stack.clear_redo()


## Clear both undo and redo history (e.g. on new game or resume).
func clear_undo_history() -> void:
	_undo_stack.clear()


# ---------------------------------------------------------------------------
# State serialisation (for undo/redo and save/load)
# ---------------------------------------------------------------------------

func get_state() -> Dictionary:
	return {
		"board_grid": board_grid.duplicate(),
		"score": score,
		"turns": turns,
		"combo_count": combo_count,
		"is_game_over": is_game_over,
		"available_blocks": _serialize_blocks(available_blocks),
		"blocks_placed_this_set": blocks_placed_this_set,
	}


func set_state(data: Dictionary) -> void:
	var raw_grid: Array = data.get("board_grid", [])
	board_grid.resize(GRID_SIZE * GRID_SIZE)
	if raw_grid.size() == GRID_SIZE * GRID_SIZE:
		for i in raw_grid.size():
			board_grid[i] = int(raw_grid[i])
	else:
		board_grid.fill(0)
	score = data.get("score", 0)
	turns = data.get("turns", 0)
	combo_count = data.get("combo_count", 0)
	is_game_over = data.get("is_game_over", false)
	available_blocks = _deserialize_blocks(data.get("available_blocks", []))
	blocks_placed_this_set = data.get("blocks_placed_this_set", 0)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _place_on_grid(shape: Array, grid_pos: Vector2i) -> void:
	for cell in shape:
		var c: Vector2i = cell
		board_grid[(grid_pos.y + c.y) * GRID_SIZE + (grid_pos.x + c.x)] = 1


func _check_and_clear_grid() -> Dictionary:
	var rows_to_clear: Array[int] = []
	var cols_to_clear: Array[int] = []
	var boxes_to_clear: Array[Vector2i] = []

	for r in GRID_SIZE:
		var row_full := true
		for c in GRID_SIZE:
			if board_grid[r * GRID_SIZE + c] == 0:
				row_full = false
				break
		if row_full:
			rows_to_clear.append(r)

	for c in GRID_SIZE:
		var col_full := true
		for r in GRID_SIZE:
			if board_grid[r * GRID_SIZE + c] == 0:
				col_full = false
				break
		if col_full:
			cols_to_clear.append(c)

	for box_r in range(0, GRID_SIZE, BOX_SIZE):
		for box_c in range(0, GRID_SIZE, BOX_SIZE):
			var box_full := true
			for r in range(box_r, box_r + BOX_SIZE):
				for c in range(box_c, box_c + BOX_SIZE):
					if board_grid[r * GRID_SIZE + c] == 0:
						box_full = false
						break
				if not box_full:
					break
			if box_full:
				boxes_to_clear.append(Vector2i(box_c, box_r))

	if rows_to_clear.is_empty() and cols_to_clear.is_empty() and boxes_to_clear.is_empty():
		return {"cleared": 0, "lines": 0, "boxes": 0, "cells": []}

	var clear_set: Dictionary = {}
	for r in rows_to_clear:
		for c in GRID_SIZE:
			clear_set[Vector2i(c, r)] = true
	for c in cols_to_clear:
		for r in GRID_SIZE:
			clear_set[Vector2i(c, r)] = true
	for box_pos in boxes_to_clear:
		for r in range(box_pos.y, box_pos.y + BOX_SIZE):
			for c in range(box_pos.x, box_pos.x + BOX_SIZE):
				clear_set[Vector2i(c, r)] = true

	for p in clear_set.keys():
		var pos: Vector2i = p
		board_grid[pos.y * GRID_SIZE + pos.x] = 0

	var lines := rows_to_clear.size() + cols_to_clear.size()
	var boxes := boxes_to_clear.size()
	var cells: Array[Vector2i] = []
	for key in clear_set.keys():
		cells.append(key)
	return {"cleared": clear_set.size(), "lines": lines, "boxes": boxes, "cells": cells}


func _has_valid_move_for_remaining() -> bool:
	var remaining: Array = []
	for s in available_blocks:
		if (s as Array).size() > 0:
			remaining.append(s)
	return _check_valid_move(remaining)


func _check_valid_move(shapes: Array) -> bool:
	if rotation_mode:
		for shape in shapes:
			var rotated: Array = shape
			for _rot in 4:
				if has_valid_placement([rotated]):
					return true
				rotated = _rotate_clockwise(rotated)
		return false
	else:
		return has_valid_placement(shapes)


## Rotate a shape 90° clockwise and normalise to origin.
## Inlined from BlockudokuShapes to keep this module self-contained.
static func _rotate_clockwise(shape: Array) -> Array[Vector2i]:
	var rotated: Array[Vector2i] = []
	for cell in shape:
		var c: Vector2i = cell
		rotated.append(Vector2i(c.y, -c.x))
	# Normalise
	var min_x := 999
	var min_y := 999
	for c in rotated:
		min_x = mini(min_x, c.x)
		min_y = mini(min_y, c.y)
	var result: Array[Vector2i] = []
	for c in rotated:
		result.append(Vector2i(c.x - min_x, c.y - min_y))
	return result


func _serialize_blocks(blocks: Array) -> Array:
	var data: Array = []
	for shape in blocks:
		data.append(_serialize_shape(shape))
	return data


func _serialize_shape(shape: Array) -> Array:
	var data: Array = []
	for cell in shape:
		var c: Vector2i = cell
		data.append({"x": c.x, "y": c.y})
	return data


func _deserialize_blocks(data: Array) -> Array[Array]:
	var blocks: Array[Array] = []
	for block_data in data:
		blocks.append(_deserialize_shape(block_data))
	return blocks


func _deserialize_shape(data: Array) -> Array:
	var shape: Array = []
	for cell_data in data:
		if cell_data is Dictionary:
			shape.append(Vector2i(int(cell_data.get("x", 0)), int(cell_data.get("y", 0))))
	return shape
