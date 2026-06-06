extends GutTest

## Unit tests for undo/redo logic — tested via pure stack operations.
## Since full game screens need scene tree + UI nodes, we test the
## capture/restore state logic in isolation using board scripts directly.

const BlockBoardScript := preload("res://scripts/blockudoku/blockudoku_board.gd")
const ShikakuBoardScript := preload("res://scripts/shikaku/shikaku_board.gd")


# ============================================================
# Blockudoku undo/redo: capture state, mutate, restore
# ============================================================

var block_board: Control


func before_each() -> void:
	block_board = Control.new()
	block_board.set_script(BlockBoardScript)
	block_board.size = Vector2(360, 360)
	add_child_autofree(block_board)
	block_board._init_grid()


func test_blockudoku_state_roundtrip() -> void:
	var shape: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	block_board.place_block(shape, 2, 3)
	var state: Dictionary = block_board.get_state()
	block_board.reset()
	assert_eq(block_board.grid[3 * 9 + 2], 0)
	block_board.set_state(state)
	assert_eq(block_board.grid[3 * 9 + 2], 1)
	assert_eq(block_board.grid[3 * 9 + 3], 1)


func test_blockudoku_undo_redo_stack_simulation() -> void:
	# Simulate undo/redo with before/after states
	var undo_stack: Array[Dictionary] = []

	# Place block and record state
	var before_state: Dictionary = block_board.get_state()
	var shape: Array[Vector2i] = [Vector2i(0, 0)]
	block_board.place_block(shape, 4, 4)
	var after_state: Dictionary = block_board.get_state()
	undo_stack.append({"before": before_state, "after": after_state})

	# Verify placed
	assert_eq(block_board.grid[4 * 9 + 4], 1)

	# Undo
	var move: Dictionary = undo_stack.pop_back()
	block_board.set_state(move["before"])
	assert_eq(block_board.grid[4 * 9 + 4], 0)

	# Redo
	block_board.set_state(move["after"])
	assert_eq(block_board.grid[4 * 9 + 4], 1)


func test_blockudoku_multiple_undo() -> void:
	var undo_stack: Array[Dictionary] = []

	# Move 1: place at (0,0)
	var s1: Dictionary = block_board.get_state()
	block_board.place_block([Vector2i(0, 0)] as Array[Vector2i], 0, 0)
	undo_stack.append({"before": s1, "after": block_board.get_state()})

	# Move 2: place at (5,5)
	var s2: Dictionary = block_board.get_state()
	block_board.place_block([Vector2i(0, 0)] as Array[Vector2i], 5, 5)
	undo_stack.append({"before": s2, "after": block_board.get_state()})

	# Undo move 2
	block_board.set_state(undo_stack.pop_back()["before"])
	assert_eq(block_board.grid[5 * 9 + 5], 0)
	assert_eq(block_board.grid[0], 1)

	# Undo move 1
	block_board.set_state(undo_stack.pop_back()["before"])
	assert_eq(block_board.grid[0], 0)


# ============================================================
# Shikaku undo/redo: add/remove rects
# ============================================================

func test_shikaku_undo_place() -> void:
	var board := Control.new()
	board.set_script(ShikakuBoardScript)
	board.size = Vector2(300, 300)
	add_child_autofree(board)
	board.setup(5, 5, {Vector2i(0, 0): 10, Vector2i(3, 2): 15})

	# Simulate place and undo
	var undo_stack: Array[Dictionary] = []
	var rect := Rect2i(0, 0, 5, 2)
	board.add_rect(rect)
	undo_stack.append({"action": "place", "rect": rect})

	assert_eq(board.placed_rects.size(), 1)

	# Undo: remove the rect
	var entry: Dictionary = undo_stack.pop_back()
	for i in range(board.placed_rects.size() - 1, -1, -1):
		if board.placed_rects[i] == entry["rect"]:
			board.remove_rect(i)
			break
	assert_eq(board.placed_rects.size(), 0)


func test_shikaku_undo_remove() -> void:
	var board := Control.new()
	board.set_script(ShikakuBoardScript)
	board.size = Vector2(300, 300)
	add_child_autofree(board)
	board.setup(5, 5, {Vector2i(0, 0): 10})

	var rect := Rect2i(0, 0, 5, 2)
	board.add_rect(rect)

	# Remove it (simulate user tap to remove)
	board.remove_rect(0)
	var undo_entry := {"action": "remove", "rect": rect}

	assert_eq(board.placed_rects.size(), 0)

	# Undo the removal: re-add
	board.add_rect(undo_entry["rect"])
	assert_eq(board.placed_rects.size(), 1)
	assert_eq(board.placed_rects[0], rect)


func test_shikaku_redo_place() -> void:
	var board := Control.new()
	board.set_script(ShikakuBoardScript)
	board.size = Vector2(300, 300)
	add_child_autofree(board)
	board.setup(5, 5, {Vector2i(0, 0): 10})

	var rect := Rect2i(0, 0, 5, 2)
	board.add_rect(rect)
	# Undo
	board.remove_rect(0)
	assert_eq(board.placed_rects.size(), 0)
	# Redo
	board.add_rect(rect)
	assert_eq(board.placed_rects.size(), 1)
	assert_eq(board.placed_rects[0], rect)


func test_shikaku_multiple_undo_redo() -> void:
	var board := Control.new()
	board.set_script(ShikakuBoardScript)
	board.size = Vector2(300, 300)
	add_child_autofree(board)
	board.setup(5, 5, {Vector2i(0, 0): 10, Vector2i(2, 2): 15})

	var undo_stack: Array[Dictionary] = []
	var redo_stack: Array[Dictionary] = []

	# Place rect A
	var a := Rect2i(0, 0, 5, 2)
	board.add_rect(a)
	undo_stack.append({"action": "place", "rect": a})

	# Place rect B
	var b := Rect2i(0, 2, 5, 3)
	board.add_rect(b)
	undo_stack.append({"action": "place", "rect": b})

	assert_eq(board.placed_rects.size(), 2)

	# Undo B
	var entry_b: Dictionary = undo_stack.pop_back()
	for i in range(board.placed_rects.size() - 1, -1, -1):
		if board.placed_rects[i] == entry_b["rect"]:
			board.remove_rect(i)
			break
	redo_stack.append(entry_b)
	assert_eq(board.placed_rects.size(), 1)

	# Undo A
	var entry_a: Dictionary = undo_stack.pop_back()
	for i in range(board.placed_rects.size() - 1, -1, -1):
		if board.placed_rects[i] == entry_a["rect"]:
			board.remove_rect(i)
			break
	redo_stack.append(entry_a)
	assert_eq(board.placed_rects.size(), 0)

	# Redo A
	var redo_a: Dictionary = redo_stack.pop_back()
	board.add_rect(redo_a["rect"])
	assert_eq(board.placed_rects.size(), 1)
	assert_eq(board.placed_rects[0], a)
