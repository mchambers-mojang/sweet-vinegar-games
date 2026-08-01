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


## Build a minimal complete adapter-test save dict for 4×4 with known-good values.
## All fields required by the updated save adapter are present.
func _make_adapter_data_4x4() -> Dictionary:
	var sol := _sol4()
	var sol_arr: Array = []
	for v in sol:
		sol_arr.append(v)
	# givens: index 0 = PLUS, index 1 = MINUS (matches sol4 checkerboard)
	var givens_arr: Array = []
	for _i in 16:
		givens_arr.append(EMPTY)
	givens_arr[0] = PLUS   # sol4[0] = PLUS
	givens_arr[1] = MINUS  # sol4[1] = MINUS
	# cells must match givens at every given position
	var cells_arr: Array = []
	for i in 16:
		cells_arr.append(givens_arr[i])
	return {
		"size": 4,
		"cells": cells_arr,
		"givens": givens_arr,
		"solution": sol_arr,
		"is_completed": false,
	}


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
	var sol := _sol4()
	var correct_val := sol[2]  # PLUS (r=0,c=2 → (0+2)%2=0 → PLUS)

	# Cycling from EMPTY once: if PLUS is correct, it should be placed.
	# If PLUS is wrong (i.e. correct_val is MINUS), the implementation advances past
	# PLUS to MINUS automatically, so we should land on MINUS (not get rejected).
	var result: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(2)

	if correct_val == PLUS:
		# First cycle gives the correct PLUS — no rejection
		assert_false(result.rejected)
		assert_eq(result.new_value, PLUS)
		# Second cycle: PLUS → wrong MINUS — should be rejected
		var r2: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(2)
		assert_true(r2.rejected)
	else:
		# correct_val == MINUS: first cycle skips over wrong PLUS, lands on correct MINUS
		assert_false(result.rejected)
		assert_eq(result.new_value, MINUS)


func test_strict_mode_minus_reachable_when_plus_is_wrong() -> void:
	## Regression test for the strict-mode MINUS-trap bug:
	## when PLUS is the wrong glyph, cycling from EMPTY must still reach MINUS
	## without the player being stuck retrying PLUS forever.
	var l2 := EclipseGridLogic.new()
	# Build a puzzle where cell index 0 correct value is MINUS.
	# Solution row 0: -, +, -, + (all MINUS at even indices for a non-checkerboard).
	var sol: Array[int] = [MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS]
	# Only cell 0 is empty (free to cycle)
	var gv: Array[int] = sol.duplicate()
	gv[0] = EMPTY
	l2.init_from_save(_make_save_data(4, sol, gv))
	l2.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	# Cell 0 solution is MINUS. First cycle (EMPTY→PLUS) is wrong.
	# The fix must skip PLUS and land on MINUS.
	var result: EclipseGridLogic.SetGlyphResult = l2.cycle_cell(0)
	assert_false(result.rejected, "Correct value must not be reported as rejected")
	assert_eq(result.new_value, MINUS, "Must skip wrong PLUS and land on correct MINUS")
	assert_eq(l2.cells[0], MINUS, "Cell must be set to MINUS")


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
	var ok_data := _make_adapter_data_4x4()
	assert_true(adapter._can_resume_from(ok_data))


func test_completed_save_not_resumable() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var done_data := _make_adapter_data_4x4()
	done_data["is_completed"] = true
	assert_false(adapter._can_resume_from(done_data))


# ---------------------------------------------------------------------------
# Save adapter — comprehensive validation (regression for corrupt-save crash)
# ---------------------------------------------------------------------------

func test_save_adapter_rejects_unsupported_size() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var cells_arr: Array = []
	for _i in 25:
		cells_arr.append(0)
	# Size 5 is not a supported board size
	var bad_data := {"size": 5, "cells": cells_arr}
	assert_false(adapter._can_resume_from(bad_data))


func test_save_adapter_rejects_invalid_cell_value() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var cells_arr: Array = []
	for _i in 16:
		cells_arr.append(0)
	cells_arr[3] = 99  # invalid glyph
	var bad_data := {"size": 4, "cells": cells_arr}
	assert_false(adapter._can_resume_from(bad_data))


func test_save_adapter_rejects_wrong_cells_length() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var cells_arr: Array = [0, 1, 0]  # too short for 4×4
	var bad_data := {"size": 4, "cells": cells_arr}
	assert_false(adapter._can_resume_from(bad_data))


func test_save_adapter_rejects_invalid_relation_value() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var cells_arr: Array = []
	for _i in 16:
		cells_arr.append(0)
	# Relation value 99 is not EQ(1) or NEQ(2)
	var bad_data := {
		"size": 4,
		"cells": cells_arr,
		"h_relations": {"0,0": 99},
	}
	assert_false(adapter._can_resume_from(bad_data))


func test_save_adapter_rejects_out_of_bounds_relation_key() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var cells_arr: Array = []
	for _i in 16:
		cells_arr.append(0)
	# Column 3 has no right neighbour in a 4×4 board — out of bounds
	var bad_data := {
		"size": 4,
		"cells": cells_arr,
		"h_relations": {"3,0": 1},
	}
	assert_false(adapter._can_resume_from(bad_data))


func test_save_adapter_accepts_valid_relations() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var ok_data := _make_adapter_data_4x4()
	ok_data["h_relations"] = {"0,0": 1, "1,1": 2}
	ok_data["v_relations"] = {"0,0": 2}
	assert_true(adapter._can_resume_from(ok_data))


# ---------------------------------------------------------------------------
# Save adapter — new validation rules (regression for #2 round of findings)
# ---------------------------------------------------------------------------

func test_save_adapter_rejects_missing_givens() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var data := _make_adapter_data_4x4()
	data.erase("givens")
	assert_false(adapter._can_resume_from(data),
		"Save without givens must be rejected")


func test_save_adapter_rejects_missing_solution() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var data := _make_adapter_data_4x4()
	data.erase("solution")
	assert_false(adapter._can_resume_from(data),
		"Save without solution must be rejected")


func test_save_adapter_rejects_empty_value_in_solution() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var data := _make_adapter_data_4x4()
	var sol_arr: Array = data["solution"].duplicate()
	sol_arr[3] = EMPTY  # Solution must be fully filled - no EMPTY allowed
	data["solution"] = sol_arr
	assert_false(adapter._can_resume_from(data),
		"Solution array containing EMPTY must be rejected")


func test_save_adapter_rejects_malformed_coordinate_string() -> void:
	## "notanumber,0" used to parse as (0,0) via int("notanumber")->0, silently
	## accepting an out-of-range key as valid.
	var adapter := EclipseGridSaveAdapter.new()
	var data := _make_adapter_data_4x4()
	data["h_relations"] = {"notanumber,0": 1}
	assert_false(adapter._can_resume_from(data),
		"Non-numeric coordinate string must be rejected")


func test_save_adapter_rejects_cells_inconsistent_with_givens() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var data := _make_adapter_data_4x4()
	# givens[0] = PLUS, but cells[0] is set to MINUS -- inconsistency
	var cells_arr: Array = data["cells"].duplicate()
	cells_arr[0] = MINUS
	data["cells"] = cells_arr
	assert_false(adapter._can_resume_from(data),
		"cells conflicting with givens must be rejected")


# ---------------------------------------------------------------------------
# Strict mode -- erasure of a correct glyph (regression for Fix 4)
# ---------------------------------------------------------------------------

func test_strict_mode_allows_erasing_correct_plus() -> void:
	## In strict mode, cycling PLUS (correct) should produce EMPTY (erase),
	## not a rejection.  Before the fix, the MINUS->EMPTY advance was rejected.
	var l := EclipseGridLogic.new()
	var sol := _sol4()
	var gv: Array[int] = sol.duplicate()
	gv[2] = EMPTY
	for i in range(4, 16):
		gv[i] = EMPTY
	l.init_from_save(_make_save_data(4, sol, gv))
	l.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	# Place the correct PLUS at cell 2
	var place_result := l.cycle_cell(2)
	assert_eq(place_result.new_value, PLUS, "First tap should place correct PLUS")
	assert_false(place_result.rejected, "Placing correct PLUS must not be rejected")

	# Now erase it -- should transition to EMPTY without rejection
	var erase_result := l.cycle_cell(2)
	assert_eq(erase_result.new_value, EMPTY, "Second tap (erase) should produce EMPTY")
	assert_false(erase_result.rejected, "Erasing a correct glyph must not be rejected")


# ---------------------------------------------------------------------------
# Solver -- analyze() must not mutate its input (regression for Fix 2)
# ---------------------------------------------------------------------------

func test_analyze_does_not_mutate_input_cells() -> void:
	## analyze() should never write to the array it receives; all enumeration
	## for Rank 3/4 must operate on internal copies.
	var cells: Array[int] = [PLUS, MINUS, EMPTY, MINUS,
							 EMPTY, EMPTY, EMPTY, EMPTY,
							 EMPTY, EMPTY, EMPTY, EMPTY,
							 EMPTY, EMPTY, EMPTY, EMPTY]
	var snapshot: Array[int] = cells.duplicate()
	EclipseGridSolver.analyze(4, cells, {}, {})
	assert_eq(cells, snapshot,
		"analyze() must leave the input cells array unchanged")
