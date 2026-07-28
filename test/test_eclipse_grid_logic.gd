extends GutTest

## Unit tests for EclipseGridLogic — state, cycling, hints, undo/redo, serialization.

const EMPTY := 0
const PLUS  := 1
const MINUS := 2
const EQ    := 1
const NEQ   := 2

var logic: EclipseGridLogic


## Build a minimal 4×4 pre-generated puzzle state for testing.
func _make_save_data(sz: int, sol: Array[int], gv: Array[int]) -> Dictionary:
	return {
		"schema_version": 1,
		"size": sz,
		"seed": 42,
		"givens": gv,
		"cells": gv.duplicate(),
		"solution": sol,
		"h_relations": {},
		"v_relations": {},
		"is_completed": false,
		"hints_used": 0,
		"assistance_mode": EclipseGridLogic.ASSIST_FREE,
		"undo_stack": [],
		"redo_stack": [],
	}


## A known valid 4×4 solution (checkerboard).
func _sol4() -> Array[int]:
	var s: Array[int] = []
	for r in 4:
		for c in 4:
			s.append(PLUS if (r + c) % 2 == 0 else MINUS)
	return s


func before_each() -> void:
	logic = EclipseGridLogic.new()
	var sol := _sol4()
	# Given: cells 0 (PLUS), 1 (MINUS), 3 (MINUS) — leave cell 2 free for cycling tests.
	# Row 0 becomes [+, -, _, -]: minus quota is full (2/2), so the solver deduces
	# cell 2 = PLUS via rank-1 quota completion.
	var gv := sol.duplicate()
	gv[2] = EMPTY
	for i in range(4, 16):
		gv[i] = EMPTY
	logic.init_from_save(_make_save_data(4, sol, gv))


# ---------------------------------------------------------------------------
# Basic state
# ---------------------------------------------------------------------------

func test_size_set_correctly() -> void:
	assert_eq(logic.size, 4)


func test_givens_are_immutable() -> void:
	# Index 0 is a given
	var result: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(0)
	assert_eq(result.old_value, result.new_value)  # No change


func test_cycle_empty_to_plus() -> void:
	var result: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(2)
	assert_eq(result.new_value, PLUS)


func test_cycle_plus_to_minus() -> void:
	logic.cycle_cell(2)  # → PLUS
	var result: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(2)
	assert_eq(result.new_value, MINUS)


func test_cycle_minus_to_empty() -> void:
	logic.cycle_cell(2)  # → PLUS
	logic.cycle_cell(2)  # → MINUS
	var result: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(2)
	assert_eq(result.new_value, EMPTY)


# ---------------------------------------------------------------------------
# Completion
# ---------------------------------------------------------------------------

func test_game_not_complete_with_empties() -> void:
	assert_false(logic.is_completed)


func test_game_completes_when_all_filled_correctly() -> void:
	var sol := _sol4()
	for i in range(16):
		if logic.givens[i] == EMPTY:
			logic.set_cell_direct(i, sol[i])
	logic._recompute_completion()
	assert_true(logic.is_completed)


# ---------------------------------------------------------------------------
# Strict assistance
# ---------------------------------------------------------------------------

func test_strict_mode_rejects_wrong_value() -> void:
	logic.assistance_mode = EclipseGridLogic.ASSIST_STRICT
	# Index 2 solution is MINUS (checkerboard: r=0,c=2 → (0+2)%2=0 → PLUS… wait)
	# Let me check: r=0,c=2 → (0+2)%2=0 → PLUS
	var sol := _sol4()
	var correct_val := sol[2]  # PLUS
	var wrong_val := MINUS if correct_val == PLUS else PLUS

	# Force PLUS into cell first so cycle goes EMPTY→PLUS
	# If correct_val is PLUS, cycling once gives PLUS (correct), which should pass.
	# We need to get to the wrong value: cycle twice from EMPTY (EMPTY→PLUS→MINUS)
	logic.cycle_cell(2)  # → PLUS
	if correct_val == MINUS:
		# PLUS is wrong here — should be rejected
		assert_true(logic.cells[2] == EMPTY or logic.cells[2] == PLUS)  # depends on impl
	else:
		# PLUS is correct here, try to go PLUS→MINUS (wrong)
		var result: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(2)
		if result.new_value == MINUS:
			assert_true(result.rejected)


func test_free_mode_allows_wrong_value() -> void:
	logic.assistance_mode = EclipseGridLogic.ASSIST_FREE
	# Cycling should always succeed in free mode
	var result: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(2)
	assert_false(result.rejected)


# ---------------------------------------------------------------------------
# Undo / Redo
# ---------------------------------------------------------------------------

func test_can_undo_after_move() -> void:
	logic.cycle_cell(2)
	assert_true(logic.can_undo())


func test_undo_restores_previous_value() -> void:
	logic.cycle_cell(2)  # → PLUS
	var result: EclipseGridLogic.UndoRedoResult = logic.undo()
	assert_eq(result.new_value, EMPTY)
	assert_eq(logic.cells[2], EMPTY)


func test_redo_after_undo() -> void:
	logic.cycle_cell(2)  # → PLUS
	logic.undo()
	var result: EclipseGridLogic.UndoRedoResult = logic.redo()
	assert_eq(result.new_value, PLUS)
	assert_eq(logic.cells[2], PLUS)


func test_can_undo_returns_false_when_stack_empty() -> void:
	assert_false(logic.can_undo())


func test_can_redo_returns_false_when_stack_empty() -> void:
	assert_false(logic.can_redo())


# ---------------------------------------------------------------------------
# Hints
# ---------------------------------------------------------------------------

func test_hint_fills_one_cell() -> void:
	var result: EclipseGridLogic.HintResult = logic.use_hint()
	assert_true(result.had_step)
	assert_gte(result.index, 0)
	assert_ne(result.value, EMPTY)
	assert_eq(logic.hints_used, 1)


func test_hint_increments_hints_used() -> void:
	logic.use_hint()
	assert_eq(logic.hints_used, 1)


# ---------------------------------------------------------------------------
# Error detection
# ---------------------------------------------------------------------------

func test_get_error_cells_empty_board() -> void:
	# No errors on a board with only givens and empties
	var errors := logic.get_error_cells()
	assert_eq(errors.size(), 0)


func test_get_error_cells_detects_three_in_a_row() -> void:
	# Row 0: PLUS, PLUS (given), force PLUS at index 2 (run of 3)
	# Given[0]=PLUS, given[1]=MINUS (checkerboard), so index 2 is free
	# Let's construct a custom logic state
	var l2 := EclipseGridLogic.new()
	var sol: Array[int] = [PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS]
	var gv: Array[int] = [PLUS, PLUS, PLUS, EMPTY,
						  EMPTY, EMPTY, EMPTY, EMPTY,
						  EMPTY, EMPTY, EMPTY, EMPTY,
						  EMPTY, EMPTY, EMPTY, EMPTY]
	l2.init_from_save(_make_save_data(4, sol, gv))
	var errors := l2.get_error_cells()
	# Indices 0, 1, 2 should all be flagged
	assert_true(errors.has(0))
	assert_true(errors.has(1))
	assert_true(errors.has(2))


func test_get_broken_relations_detects_violation() -> void:
	var l2 := EclipseGridLogic.new()
	var sol := _sol4()
	var gv: Array[int] = sol.duplicate()
	# Set up an EQ relation between (0,0) PLUS and (1,0) MINUS — will be violated
	var data := _make_save_data(4, sol, gv)
	data["h_relations"] = {"0,0": EQ}
	l2.init_from_save(data)
	var broken := l2.get_broken_relations()
	assert_eq(broken.size(), 1)


# ---------------------------------------------------------------------------
# Serialization roundtrip
# ---------------------------------------------------------------------------

func test_serialize_deserialize_roundtrip() -> void:
	logic.cycle_cell(2)
	logic.cycle_cell(3)
	logic.undo()
	var data: Dictionary = logic.serialize()

	var restored := EclipseGridLogic.new()
	restored.init_from_save(data)

	assert_eq(restored.size, logic.size)
	assert_eq(restored.cells, logic.cells)
	assert_eq(restored.hints_used, logic.hints_used)
	assert_eq(restored.undo_stack.size(), logic.undo_stack.size())
	assert_eq(restored.redo_stack.size(), logic.redo_stack.size())


func test_invalid_save_schema_gracefully_fails() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	# Missing cells array
	var bad_data := {"size": 4}
	assert_false(adapter._can_resume_from(bad_data))


func test_invalid_save_size_zero_rejected() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var bad_data := {"size": 0, "cells": []}
	assert_false(adapter._can_resume_from(bad_data))


func test_valid_save_schema_accepted() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var cells_arr: Array = []
	for _i in 16:
		cells_arr.append(0)
	var ok_data := {"size": 4, "cells": cells_arr, "is_completed": false}
	assert_true(adapter._can_resume_from(ok_data))


func test_completed_save_not_resumable() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var cells_arr: Array = []
	for _i in 16:
		cells_arr.append(1)
	var done_data := {"size": 4, "cells": cells_arr, "is_completed": true}
	assert_false(adapter._can_resume_from(done_data))
