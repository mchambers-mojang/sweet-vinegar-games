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
		"seed": 42,
		"cells": cells_arr,
		"givens": givens_arr,
		"solution": sol_arr,
		"is_completed": false,
		"assistance_mode": EclipseGridLogic.ASSIST_FREE,
		"undo_stack": [],
		"redo_stack": [],
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

	# Cycling from EMPTY once:
	# - If PLUS is correct: placed without rejection.
	# - If PLUS is wrong (correct_val == MINUS): stored as rejected cycle side-state.
	var result: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(2)

	if correct_val == PLUS:
		# First cycle gives the correct PLUS — no rejection
		assert_false(result.rejected)
		assert_eq(result.new_value, PLUS)
		assert_eq(logic.cells[2], PLUS)
		# Second cycle: PLUS → MINUS (wrong, rejected into cycle side-state)
		var r2: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(2)
		assert_true(r2.rejected, "Wrong MINUS must be marked as rejected")
		assert_eq(r2.new_value, MINUS, "Cycle must advance to MINUS")
		# Third cycle: MINUS → EMPTY (erase, always accepted)
		var r3: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(2)
		assert_false(r3.rejected, "Erasing (→EMPTY) must not be rejected")
		assert_eq(r3.new_value, EMPTY, "Cycle must advance to EMPTY (erase)")
	else:
		# correct_val == MINUS: first cycle tries PLUS (wrong) → rejected into side-state
		assert_true(result.rejected, "Wrong PLUS must be marked as rejected")
		assert_eq(result.new_value, PLUS)
		assert_eq(logic.cells[2], EMPTY, "Wrong PLUS must not enter the accepted board state")
		# Second cycle: PLUS → MINUS (correct, no rejection)
		var r2: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(2)
		assert_false(r2.rejected, "Correct MINUS must not be rejected")
		assert_eq(r2.new_value, MINUS)


func test_strict_mode_minus_reachable_when_plus_is_wrong() -> void:
	## Regression test: when PLUS is the wrong glyph, cycling from EMPTY must still
	## reach MINUS.  The fix places the wrong PLUS (rejected) so that the next tap
	## advances the cycle to MINUS rather than retrying PLUS forever.
	var l2 := EclipseGridLogic.new()
	# Build a puzzle where cell index 0 correct value is MINUS.
	var sol: Array[int] = [MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS]
	var gv: Array[int] = sol.duplicate()
	gv[0] = EMPTY
	l2.init_from_save(_make_save_data(4, sol, gv))
	l2.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	# Cell 0 solution is MINUS. First tap tries PLUS (wrong) → rejected.
	var r1: EclipseGridLogic.SetGlyphResult = l2.cycle_cell(0)
	assert_true(r1.rejected, "Wrong PLUS must be flagged as rejected")
	assert_eq(r1.new_value, PLUS, "Cycle advances to PLUS")
	assert_eq(l2.cells[0], EMPTY, "Rejected PLUS must not enter the accepted board state")

	# Second tap cycles PLUS → MINUS (correct, no rejection).
	var r2: EclipseGridLogic.SetGlyphResult = l2.cycle_cell(0)
	assert_false(r2.rejected, "Correct MINUS must not be rejected")
	assert_eq(r2.new_value, MINUS, "Cycle advances to MINUS")
	assert_eq(l2.cells[0], MINUS, "Cell is set to MINUS")


func test_strict_mode_erase_always_allowed() -> void:
	## EMPTY (erase) must always be accepted in strict mode regardless of the
	## previous cell value.
	var l2 := EclipseGridLogic.new()
	var sol := _sol4()
	var gv: Array[int] = sol.duplicate()
	gv[2] = EMPTY
	l2.init_from_save(_make_save_data(4, sol, gv))
	l2.assistance_mode = EclipseGridLogic.ASSIST_STRICT
	# Place correct PLUS at cell 2 (sol[2] = PLUS for checkerboard)
	l2.cycle_cell(2)  # → PLUS (correct)
	# Cycle to MINUS (wrong, rejected into side-state)
	l2.cycle_cell(2)  # → MINUS
	# Cycle to EMPTY (erase) — must be accepted
	var r: EclipseGridLogic.SetGlyphResult = l2.cycle_cell(2)
	assert_false(r.rejected, "Erase must not be rejected in strict mode")
	assert_eq(r.new_value, EMPTY)


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
# Strict mode -- erasure (regression for round-5 cycle/reject fix)
# ---------------------------------------------------------------------------

func test_strict_mode_allows_erasing_correct_plus() -> void:
	## In strict mode, cycling a correct PLUS must eventually reach EMPTY (erase).
	## PLUS → MINUS stores a rejected cycle position, then the next tap erases.
	var l := EclipseGridLogic.new()
	var sol := _sol4()
	var gv: Array[int] = sol.duplicate()
	gv[2] = EMPTY
	for i in range(4, 16):
		gv[i] = EMPTY
	l.init_from_save(_make_save_data(4, sol, gv))
	l.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	# Tap 1: EMPTY → PLUS (correct for cell 2 in checkerboard, no rejection)
	var r1 := l.cycle_cell(2)
	assert_eq(r1.new_value, PLUS, "First tap must place correct PLUS")
	assert_false(r1.rejected, "Placing correct PLUS must not be rejected")

	# Tap 2: PLUS → MINUS (wrong, rejected into side-state so cycle advances)
	var r2 := l.cycle_cell(2)
	assert_true(r2.rejected, "Wrong MINUS must be marked as rejected")
	assert_eq(r2.new_value, MINUS)

	# Tap 3: MINUS → EMPTY (erase, always accepted)
	var r3 := l.cycle_cell(2)
	assert_false(r3.rejected, "Erase (→EMPTY) must never be rejected")
	assert_eq(r3.new_value, EMPTY, "Third tap must produce EMPTY (erase)")


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


# ---------------------------------------------------------------------------
# Save adapter — Issue 2: assistance_mode, seed, undo/redo stack validation
# ---------------------------------------------------------------------------

func test_save_adapter_rejects_missing_assistance_mode() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var data := _make_adapter_data_4x4()
	data.erase("assistance_mode")
	assert_false(adapter._can_resume_from(data),
		"Save without assistance_mode must be rejected")


func test_save_adapter_rejects_invalid_assistance_mode() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var data := _make_adapter_data_4x4()
	data["assistance_mode"] = 99  # out of [0,1,2]
	assert_false(adapter._can_resume_from(data),
		"Save with assistance_mode=99 must be rejected")


func test_save_adapter_rejects_missing_seed() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var data := _make_adapter_data_4x4()
	data.erase("seed")
	assert_false(adapter._can_resume_from(data),
		"Save without seed must be rejected")


func test_save_adapter_rejects_invalid_undo_stack_entry() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var data := _make_adapter_data_4x4()
	# Entry with an out-of-range index
	data["undo_stack"] = [{"index": 999, "old_value": 0, "new_value": 1}]
	assert_false(adapter._can_resume_from(data),
		"Undo stack entry with invalid index must be rejected")


func test_save_adapter_rejects_undo_stack_entry_with_invalid_value() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var data := _make_adapter_data_4x4()
	data["undo_stack"] = [{"index": 0, "old_value": 0, "new_value": 99}]
	assert_false(adapter._can_resume_from(data),
		"Undo stack entry with invalid new_value must be rejected")


func test_save_adapter_accepts_valid_undo_stack() -> void:
	var adapter := EclipseGridSaveAdapter.new()
	var data := _make_adapter_data_4x4()
	data["undo_stack"] = [{"index": 2, "old_value": 0, "new_value": 1}]
	assert_true(adapter._can_resume_from(data),
		"Valid undo stack entry must be accepted")


# ---------------------------------------------------------------------------
# Logic — Issue 3: hints must not apply values derived from wrong player cells
# ---------------------------------------------------------------------------

func test_hint_applies_correct_value_when_player_has_wrong_cells() -> void:
	## In free mode, the player may place wrong values.  Hints must still return
	## the solution-correct value even when the current cells state is inconsistent.
	var l := EclipseGridLogic.new()
	var sol := _sol4()
	# Leave cell 2 deducible and cell 4 available for a wrong player entry.
	var gv: Array[int] = sol.duplicate()
	gv[2] = EMPTY
	gv[4] = EMPTY
	l.init_from_save(_make_save_data(4, sol, gv))
	l.assistance_mode = EclipseGridLogic.ASSIST_FREE

	# Cell 4 should be MINUS; the hint's clean board must ignore this wrong PLUS.
	l.set_cell_direct(4, PLUS)

	# Row 0 is [+, -, _, -], so quota completion deterministically fills cell 2.
	var result: EclipseGridLogic.HintResult = l.use_hint()
	assert_true(result.had_step, "A solver-supported hint must be available")
	assert_eq(result.index, 2, "Hint must fill the deducible row-0 cell")
	assert_eq(result.value, sol[result.index],
		"Hint value must match the solution even when board has wrong cells")


# ---------------------------------------------------------------------------
# Fix 3 — strict-mode undo must not expose rejected glyphs
# ---------------------------------------------------------------------------

func test_strict_undo_skips_rejected_glyph_solution_plus() -> void:
	## solution[0] = PLUS.
	## Cycle: EMPTY → PLUS (correct, accepted) → MINUS (rejected into side-state) →
	##        EMPTY (erase, accepted).
	## After the accepted EMPTY step, undo should restore to PLUS (not MINUS).
	var l2 := EclipseGridLogic.new()
	var sol: Array[int] = [PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS]
	var gv: Array[int] = sol.duplicate()
	gv[0] = EMPTY
	gv[1] = EMPTY  # Keep the game active while exercising post-placement undo.
	l2.init_from_save(_make_save_data(4, sol, gv))
	l2.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	# EMPTY → PLUS (correct).
	var r1: EclipseGridLogic.SetGlyphResult = l2.cycle_cell(0)
	assert_false(r1.rejected)
	assert_eq(l2.cells[0], PLUS)

	# PLUS → MINUS (wrong, rejected into side-state for cycle advancement).
	var r2: EclipseGridLogic.SetGlyphResult = l2.cycle_cell(0)
	assert_true(r2.rejected, "Wrong MINUS must be rejected")
	assert_eq(l2.cells[0], PLUS, "Rejected value must not replace the accepted PLUS")

	# MINUS → EMPTY (erase, always accepted).
	var r3: EclipseGridLogic.SetGlyphResult = l2.cycle_cell(0)
	assert_false(r3.rejected)
	assert_eq(l2.cells[0], EMPTY)

	# Undo: should restore to PLUS (last correct state), NOT to rejected MINUS.
	assert_true(l2.can_undo(), "Undo must be available after accepted placements")
	var u := l2.undo()
	assert_eq(l2.cells[0], PLUS,
		"Undo after erase must restore PLUS (correct state), not rejected MINUS")
	assert_eq(u.new_value, PLUS,
		"Undo result.new_value must be PLUS (the restored value)")


func test_strict_undo_skips_rejected_glyph_solution_minus() -> void:
	## solution[0] = MINUS.
	## Cycle: EMPTY → PLUS (rejected) → MINUS (correct).
	## After entering correct MINUS, undo must restore to EMPTY, not rejected PLUS.
	var l2 := EclipseGridLogic.new()
	var sol: Array[int] = [MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS]
	var gv: Array[int] = sol.duplicate()
	gv[0] = EMPTY
	gv[1] = EMPTY  # Keep the game active while exercising undo.
	l2.init_from_save(_make_save_data(4, sol, gv))
	l2.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	# EMPTY → PLUS (wrong, rejected).
	var r1: EclipseGridLogic.SetGlyphResult = l2.cycle_cell(0)
	assert_true(r1.rejected, "Wrong PLUS must be rejected")
	assert_eq(l2.cells[0], EMPTY, "Rejected value must not enter the accepted board state")

	# PLUS → MINUS (correct, accepted).
	var r2: EclipseGridLogic.SetGlyphResult = l2.cycle_cell(0)
	assert_false(r2.rejected, "Correct MINUS must be accepted")
	assert_eq(l2.cells[0], MINUS)

	# Undo: must restore to EMPTY, not to rejected PLUS.
	assert_true(l2.can_undo(), "Undo must be available after accepted MINUS")
	l2.undo()
	assert_eq(l2.cells[0], EMPTY,
		"Undo after correct MINUS must restore EMPTY (pre-rejection state), not rejected PLUS")


func test_strict_undo_not_pushed_for_rejected() -> void:
	## Rejected placements must NOT add entries to the undo stack.
	## After a rejected PLUS (cell 0 solution=MINUS), undo stack must remain empty.
	var l2 := EclipseGridLogic.new()
	var sol: Array[int] = [MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS]
	var gv: Array[int] = sol.duplicate()
	gv[0] = EMPTY
	l2.init_from_save(_make_save_data(4, sol, gv))
	l2.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	var r1: EclipseGridLogic.SetGlyphResult = l2.cycle_cell(0)
	assert_true(r1.rejected)
	assert_false(l2.can_undo(),
		"Rejected placement must not add an undo entry — undo stack must remain empty")


# ---------------------------------------------------------------------------
# Fix 4 — broken relation clues are highlighted
# ---------------------------------------------------------------------------

func test_get_broken_relations_eq_violation() -> void:
	## EQ relation requires both cells to be the same glyph.
	## Place PLUS on the left and MINUS on the right → violated.
	var l2 := EclipseGridLogic.new()
	var sol := _sol4()
	var gv: Array[int] = sol.duplicate()
	var data := _make_save_data(4, sol, gv)
	# h_relations: relation between (0,0) and (1,0) must be EQ.
	# sol4 checkerboard: (0,0)=PLUS, (1,0)=MINUS → PLUS ≠ MINUS → EQ violated.
	data["h_relations"] = {"0,0": EQ}
	l2.init_from_save(data)
	var broken: Array[Array] = l2.get_broken_relations()
	assert_eq(broken.size(), 1, "One EQ relation must be reported as broken")
	assert_eq(broken[0][2], true, "Broken relation must be flagged as horizontal")


func test_get_broken_relations_neq_violation() -> void:
	## NEQ relation requires both cells to be different.
	## Place PLUS on both sides → violated.
	var l2 := EclipseGridLogic.new()
	var sol: Array[int] = [PLUS, PLUS, MINUS, MINUS,
						   MINUS, MINUS, PLUS, PLUS,
						   PLUS, PLUS, MINUS, MINUS,
						   MINUS, MINUS, PLUS, PLUS]
	var gv: Array[int] = sol.duplicate()
	var data := _make_save_data(4, sol, gv)
	# h_relations: (0,0)→(1,0) NEQ; sol has PLUS,PLUS → NEQ violated.
	data["h_relations"] = {"0,0": NEQ}
	l2.init_from_save(data)
	var broken: Array[Array] = l2.get_broken_relations()
	assert_eq(broken.size(), 1, "One NEQ relation must be reported as broken")


func test_get_broken_relations_returns_empty_when_none_violated() -> void:
	## EQ relation satisfied: (0,0) and (1,0) are both PLUS in this board.
	var l2 := EclipseGridLogic.new()
	var sol: Array[int] = [PLUS, PLUS, MINUS, MINUS,
						   MINUS, MINUS, PLUS, PLUS,
						   PLUS, PLUS, MINUS, MINUS,
						   MINUS, MINUS, PLUS, PLUS]
	var gv: Array[int] = sol.duplicate()
	var data := _make_save_data(4, sol, gv)
	data["h_relations"] = {"0,0": EQ}  # PLUS=PLUS → satisfied
	l2.init_from_save(data)
	var broken: Array[Array] = l2.get_broken_relations()
	assert_eq(broken.size(), 0, "No broken relations when all clues are satisfied")

# ---------------------------------------------------------------------------
# Fix: use_hint undo entry uses pre-rejection old_value (Issue 3)
# ---------------------------------------------------------------------------

func test_hint_undo_uses_pre_rejection_value_not_rejected_glyph() -> void:
	## A rejected PLUS at a MINUS solution cell lives only in side-state.
	## A hint on that cell must record the accepted EMPTY value for undo.
	var l := EclipseGridLogic.new()
	var sol: Array[int] = [PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS]
	var gv: Array[int] = sol.duplicate()
	gv[1] = EMPTY
	gv[4] = EMPTY  # Keep the game active after the hint.
	l.init_from_save(_make_save_data(4, sol, gv))
	l.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	var rejected := l.cycle_cell(1)  # EMPTY → PLUS (wrong)
	assert_true(rejected.rejected)
	assert_eq(l.cells[1], EMPTY, "Rejected PLUS must remain outside cells[]")

	var hint := l.use_hint()
	assert_true(hint.had_step, "Hint must succeed on the empty cell")
	assert_eq(hint.index, 1, "Hint must target the rejected cell")
	assert_eq(hint.value, MINUS)
	assert_true(l.can_undo())
	var u := l.undo()
	assert_eq(l.cells[1], EMPTY)
	assert_eq(u.new_value, EMPTY,
		"Undo after hint must restore EMPTY (old_value before hint), not a rejected glyph")


func test_hint_undo_old_value_is_empty_even_when_rejected_glyph_present() -> void:
	## A rejected cycle position on one cell must not contaminate the undo entry
	## for a hint applied to another empty cell.
	var l2 := EclipseGridLogic.new()
	var sol: Array[int] = [PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS]
	var gv: Array[int] = sol.duplicate()
	gv[0] = EMPTY
	gv[1] = EMPTY
	gv[4] = EMPTY  # Keep the game active after the hint.
	l2.init_from_save(_make_save_data(4, sol, gv))
	l2.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	# Cycle cell 0: EMPTY→PLUS(accepted)→MINUS(rejected into side-state).
	var _r1 := l2.cycle_cell(0)
	var rejected := l2.cycle_cell(0)
	assert_true(rejected.rejected)
	assert_eq(l2.cells[0], PLUS, "Cell 0 must retain its accepted PLUS")

	# Row 0 is [+, _, +, -], making cell 1 deterministically MINUS.
	var hint := l2.use_hint()
	assert_true(hint.had_step, "Hint must apply")
	assert_eq(hint.index, 1)
	assert_true(l2.can_undo(), "Undo available after hint")
	var u := l2.undo()
	assert_eq(u.new_value, EMPTY, "Hint undo must restore the hinted cell to EMPTY")
	assert_eq(l2.cells[0], PLUS, "Undoing the hint must not expose the rejected MINUS")


func test_strict_mode_rejected_glyph_not_in_cells() -> void:
	## In strict mode, a rejected wrong glyph must NOT appear in cells[].
	## cells[] must stay at the last accepted value (EMPTY if no accepted value yet).
	var sol: Array[int] = [PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS]
	var gv: Array[int] = sol.duplicate()
	gv[0] = EMPTY  # Keep the game active after accepting cell 1.
	gv[1] = EMPTY  # cell 1: solution = MINUS, so tapping PLUS is wrong

	var l := EclipseGridLogic.new()
	l.init_from_save(_make_save_data(4, sol, gv))
	l.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	# EMPTY → PLUS (wrong; sol[1]=MINUS). Must be rejected.
	var r1 := l.cycle_cell(1)
	assert_true(r1.rejected, "PLUS at cell 1 should be rejected (sol=MINUS)")
	assert_eq(r1.new_value, PLUS, "result.new_value reports the rejected glyph")
	assert_eq(l.cells[1], EMPTY,
		"cells[1] must stay EMPTY — rejected glyph must NOT enter cells[]")

	# Tap again: cycle advances from PLUS to MINUS (correct). Must be accepted.
	var r2 := l.cycle_cell(1)
	assert_false(r2.rejected, "MINUS must be accepted")
	assert_eq(l.cells[1], MINUS, "cells[1] must be MINUS after accepted tap")

	# Undo: must return to EMPTY (the accepted state before the first tap).
	assert_true(l.can_undo())
	var u := l.undo()
	assert_eq(l.cells[1], EMPTY,
		"Undo must restore EMPTY (last accepted state), not rejected PLUS")
	assert_eq(u.new_value, EMPTY, "UndoRedoResult.new_value must be EMPTY")


func test_strict_mode_resume_shows_clean_state() -> void:
	## After serialize() + init_from_save() with a pending rejected cycle position,
	## cells[] must remain at the last accepted value (no rejected glyph visible).
	## The next tap must correctly continue the cycle from the rejected position.
	var sol: Array[int] = [PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS]
	var gv: Array[int] = sol.duplicate()
	gv[1] = EMPTY  # cell 1: solution = MINUS

	var l := EclipseGridLogic.new()
	l.init_from_save(_make_save_data(4, sol, gv))
	l.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	# EMPTY → PLUS (wrong, rejected). cells[1] stays EMPTY.
	var _r1 := l.cycle_cell(1)
	assert_eq(l.cells[1], EMPTY, "cells[1] stays EMPTY after rejection")

	# Save and resume.
	var saved := l.serialize()
	var l2 := EclipseGridLogic.new()
	l2.init_from_save(saved)

	# After resume, cells[1] must still be EMPTY (no rejected glyph visible).
	assert_eq(l2.cells[1], EMPTY,
		"After resume, cells[1] must be EMPTY (rejected glyphs never stored in cells[])")

	# Tap once more: cycle advances from PLUS (the rejected position) to MINUS (correct).
	var r2 := l2.cycle_cell(1)
	assert_false(r2.rejected, "MINUS must be accepted after resume")
	assert_eq(l2.cells[1], MINUS,
		"Cell 1 must reach MINUS by continuing cycle from rejected PLUS position")


func test_rejected_cells_survives_save_resume() -> void:
	## _rejected_cells is serialized as "rejected_cells" and restored on resume,
	## preserving the cycle position so the next tap reaches the correct value.
	var sol: Array[int] = [PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS]
	var gv: Array[int] = sol.duplicate()
	gv[0] = EMPTY  # Keep the game active after accepting cell 1.
	gv[1] = EMPTY

	var l1 := EclipseGridLogic.new()
	l1.init_from_save(_make_save_data(4, sol, gv))
	l1.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	# Tap: EMPTY → PLUS (wrong). Rejected cycle at PLUS.
	var _r := l1.cycle_cell(1)
	var saved := l1.serialize()

	# Verify the serialized form has a "rejected_cells" key (not "pre_rejection").
	assert_true(saved.has("rejected_cells"),
		"serialize() must emit 'rejected_cells' key")
	assert_false(saved.has("pre_rejection"),
		"serialize() must NOT emit legacy 'pre_rejection' key")

	var l2 := EclipseGridLogic.new()
	l2.init_from_save(saved)

	# After resume, cells[1] is EMPTY (rejected glyph not in cells[]).
	assert_eq(l2.cells[1], EMPTY, "Resumed cells[1] must be EMPTY")

	# Tap: cycle from restored rejected position (PLUS) → MINUS (correct).
	var r2 := l2.cycle_cell(1)
	assert_false(r2.rejected, "MINUS must be accepted after resume")
	assert_eq(l2.cells[1], MINUS, "Cell 1 must be MINUS (cycle continued from rejected PLUS)")

	# Undo after resume: must revert to EMPTY (the accepted state), not to PLUS.
	assert_true(l2.can_undo())
	var u := l2.undo()
	assert_eq(l2.cells[1], EMPTY,
		"Undo after resume must restore EMPTY, not the rejected PLUS")


func test_save_adapter_accepts_rejected_cells() -> void:
	## A save with a valid rejected_cells dict (string int keys, PLUS/MINUS values)
	## must be accepted by the save adapter.
	var adapter := EclipseGridSaveAdapter.new()
	var sol: Array[int] = [PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS]
	var gv: Array[int] = sol.duplicate()
	gv[0] = EMPTY
	var data := _make_save_data(4, sol, gv)
	data["rejected_cells"] = {"0": PLUS}  # String key → PLUS value
	assert_true(adapter._can_resume_from(data),
		"Save adapter must accept a valid rejected_cells dict")


func test_save_adapter_rejects_rejected_cells_empty_value() -> void:
	## rejected_cells values must be PLUS or MINUS, never EMPTY.
	var adapter := EclipseGridSaveAdapter.new()
	var sol: Array[int] = [PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS]
	var gv: Array[int] = sol.duplicate()
	gv[0] = EMPTY
	var data := _make_save_data(4, sol, gv)
	data["rejected_cells"] = {"0": EMPTY}  # EMPTY is not a valid rejected glyph
	assert_false(adapter._can_resume_from(data),
		"Save adapter must reject rejected_cells with EMPTY value")


func test_save_adapter_rejects_rejected_cells_invalid_key() -> void:
	## A rejected_cells dict with a non-string key must be rejected.
	var adapter := EclipseGridSaveAdapter.new()
	var sol: Array[int] = [PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS]
	var gv: Array[int] = sol.duplicate()
	gv[0] = EMPTY
	var data := _make_save_data(4, sol, gv)
	data["rejected_cells"] = {0: PLUS}  # Int key instead of string — invalid
	assert_false(adapter._can_resume_from(data),
		"Save adapter must reject rejected_cells with non-string key")


# ---------------------------------------------------------------------------
# Fix 4 — _rejected_cells cleared when assistance_mode changes
# ---------------------------------------------------------------------------

func test_rejected_cells_cleared_when_mode_changes() -> void:
	## When assistance_mode is reassigned, any pending rejected cycle state
	## (_rejected_cells) must be cleared so that cycle_cell() restarts from the
	## current accepted cell value rather than from the rejected position.
	var l2 := EclipseGridLogic.new()
	var sol: Array[int] = [MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS,
						   MINUS, PLUS, MINUS, PLUS,
						   PLUS, MINUS, PLUS, MINUS]
	var gv: Array[int] = sol.duplicate()
	gv[0] = EMPTY
	l2.init_from_save(_make_save_data(4, sol, gv))
	l2.assistance_mode = EclipseGridLogic.ASSIST_STRICT

	# Cell 0 solution is MINUS. First tap: PLUS is wrong → rejected, cycle advances.
	var r1: EclipseGridLogic.SetGlyphResult = l2.cycle_cell(0)
	assert_true(r1.rejected, "Wrong PLUS must be rejected in strict mode")
	# cells[0] stays EMPTY; _rejected_cells[0] = PLUS (internal cycle position).
	assert_eq(l2.cells[0], EMPTY,
		"Rejected glyph must not appear in cells[] in strict mode")

	# Switch to free mode: _rejected_cells must be cleared.
	l2.assistance_mode = EclipseGridLogic.ASSIST_FREE

	# Next tap must cycle from the accepted value (EMPTY) → PLUS, not from the
	# rejected position PLUS → MINUS.
	var r2: EclipseGridLogic.SetGlyphResult = l2.cycle_cell(0)
	assert_false(r2.rejected, "Free mode must not reject values")
	assert_eq(r2.new_value, PLUS,
		"Cycle must restart from EMPTY → PLUS after _rejected_cells cleared on mode change")
	assert_eq(l2.cells[0], PLUS,
		"Cell accepts PLUS in free mode after cleared rejected state")
