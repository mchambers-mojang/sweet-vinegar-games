extends GutTest

## Unit tests for the generic UndoStack module.

const UndoStackScript := preload("res://scripts/utils/undo_stack.gd")

var stack: UndoStack


func before_each() -> void:
	stack = UndoStack.new()


# ============================================================
# push / can_undo / can_redo
# ============================================================

func test_new_stack_is_empty() -> void:
	assert_false(stack.can_undo())
	assert_false(stack.can_redo())
	assert_eq(stack.undo_size(), 0)
	assert_eq(stack.redo_size(), 0)


func test_push_enables_undo() -> void:
	stack.push({"value": 1})
	assert_true(stack.can_undo())
	assert_eq(stack.undo_size(), 1)


func test_push_clears_redo() -> void:
	stack.push({"value": 1})
	stack.undo()  # move entry to redo
	assert_true(stack.can_redo())
	stack.push({"value": 2})  # new action should clear redo
	assert_false(stack.can_redo())


# ============================================================
# undo / redo move behaviour
# ============================================================

func test_undo_returns_pushed_entry() -> void:
	var snap := {"value": 42}
	stack.push(snap)
	var result := stack.undo()
	assert_eq(result["value"], 42)


func test_undo_moves_entry_to_redo() -> void:
	stack.push({"value": 1})
	stack.undo()
	assert_false(stack.can_undo())
	assert_true(stack.can_redo())
	assert_eq(stack.redo_size(), 1)


func test_redo_returns_entry() -> void:
	stack.push({"value": 7})
	stack.undo()
	var result := stack.redo()
	assert_eq(result["value"], 7)


func test_redo_moves_entry_back_to_undo() -> void:
	stack.push({"value": 1})
	stack.undo()
	stack.redo()
	assert_true(stack.can_undo())
	assert_false(stack.can_redo())


func test_undo_empty_returns_empty_dict() -> void:
	var result := stack.undo()
	assert_true(result.is_empty())


func test_redo_empty_returns_empty_dict() -> void:
	var result := stack.redo()
	assert_true(result.is_empty())


# ============================================================
# replace_redo_top / replace_undo_top (Sudoku pattern)
# ============================================================

func test_replace_redo_top_substitutes_entry() -> void:
	stack.push({"value": 0})   # before-state pushed to undo
	stack.undo()                # undo auto-moves {value:0} to redo
	stack.replace_redo_top({"value": 4})  # replace with current state
	var redo_entry := stack.redo()
	assert_eq(redo_entry["value"], 4)


func test_replace_undo_top_substitutes_entry() -> void:
	stack.push({"value": 0})
	stack.undo()
	stack.replace_redo_top({"value": 4})
	stack.redo()                           # moves {value:4} to undo (wrong placeholder)
	stack.replace_undo_top({"value": 0})  # fix up undo top
	var undo_entry := stack.undo()
	assert_eq(undo_entry["value"], 0)


func test_replace_redo_top_no_op_when_empty() -> void:
	stack.replace_redo_top({"value": 99})  # should not crash
	assert_false(stack.can_redo())


func test_replace_undo_top_no_op_when_empty() -> void:
	stack.replace_undo_top({"value": 99})  # should not crash
	assert_false(stack.can_undo())


# ============================================================
# clear / clear_redo
# ============================================================

func test_clear_empties_both_stacks() -> void:
	stack.push({"value": 1})
	stack.push({"value": 2})
	stack.undo()
	stack.clear()
	assert_false(stack.can_undo())
	assert_false(stack.can_redo())


func test_clear_redo_only_clears_redo() -> void:
	stack.push({"value": 1})
	stack.undo()
	stack.clear_redo()
	assert_false(stack.can_redo())
	# The undo entry was already popped, so can_undo() is also false here —
	# just verify we don't crash and redo is gone.
	assert_false(stack.can_redo())


func test_clear_redo_leaves_undo_intact() -> void:
	stack.push({"value": 1})
	stack.push({"value": 2})
	stack.clear_redo()
	assert_true(stack.can_undo())
	assert_eq(stack.undo_size(), 2)


# ============================================================
# get_undo_entries / get_redo_entries / load_entries
# ============================================================

func test_get_undo_entries_returns_internal_array() -> void:
	stack.push({"a": 1})
	stack.push({"b": 2})
	var entries := stack.get_undo_entries()
	assert_eq(entries.size(), 2)
	assert_eq(entries[0]["a"], 1)
	assert_eq(entries[1]["b"], 2)


func test_get_redo_entries_returns_internal_array() -> void:
	stack.push({"x": 5})
	stack.undo()
	var entries := stack.get_redo_entries()
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["x"], 5)


func test_load_entries_replaces_state() -> void:
	stack.push({"old": true})
	var undo_data: Array[Dictionary] = [{"new_undo": 1}, {"new_undo": 2}]
	var redo_data: Array[Dictionary] = [{"new_redo": 9}]
	stack.load_entries(undo_data, redo_data)
	assert_eq(stack.undo_size(), 2)
	assert_eq(stack.redo_size(), 1)
	assert_eq(stack.undo(), {"new_undo": 2})


# ============================================================
# Multi-step sequences
# ============================================================

func test_multiple_undos_in_sequence() -> void:
	stack.push({"step": 1})
	stack.push({"step": 2})
	stack.push({"step": 3})

	assert_eq(stack.undo()["step"], 3)
	assert_eq(stack.undo()["step"], 2)
	assert_eq(stack.undo()["step"], 1)
	assert_false(stack.can_undo())
	assert_eq(stack.redo_size(), 3)


func test_undo_then_redo_sequence() -> void:
	stack.push({"step": 1})
	stack.push({"step": 2})
	stack.undo()
	stack.undo()

	assert_eq(stack.redo()["step"], 1)
	assert_eq(stack.redo()["step"], 2)
	assert_false(stack.can_redo())
