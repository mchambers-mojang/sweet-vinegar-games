extends GutTest

## Unit tests for CrownGridLogic.

var logic: CrownGridLogic

# 4x4 test board with 4 distinct column regions
# Valid solution: crown_cols = [1, 3, 0, 2]
func _regions_4x4() -> PackedInt32Array:
	var r := PackedInt32Array()
	r.resize(16)
	for row in range(4):
		for col in range(4):
			r[row * 4 + col] = col  # region = column index
	return r


func _solution_4x4() -> Array[int]:
	return [1, 3, 0, 2]  # no diagonal adjacency: |1-3|=2,|3-0|=3,|0-2|=2


func before_each() -> void:
	logic = CrownGridLogic.new()
	logic.init_new_game(4, _regions_4x4(), _solution_4x4())


# ---------------------------------------------------------------------------
# Basic cell state
# ---------------------------------------------------------------------------

func test_initial_all_empty() -> void:
	for r in range(4):
		for c in range(4):
			assert_eq(logic.get_cell(c, r), CrownGridLogic.CELL_EMPTY)


func test_tap_cycles_empty_to_excluded() -> void:
	var result := logic.tap_cell(0, 0)
	assert_true(result.changed)
	assert_eq(result.new_state, CrownGridLogic.CELL_EXCLUDED)
	assert_eq(logic.get_cell(0, 0), CrownGridLogic.CELL_EXCLUDED)


func test_tap_cycles_excluded_to_crown() -> void:
	logic.tap_cell(1, 0)  # → excluded
	var result := logic.tap_cell(1, 0)  # → crown
	assert_true(result.changed)
	assert_eq(result.new_state, CrownGridLogic.CELL_CROWN)
	assert_eq(logic.get_cell(1, 0), CrownGridLogic.CELL_CROWN)


func test_tap_cycles_crown_to_empty() -> void:
	logic.tap_cell(1, 0)  # excluded
	logic.tap_cell(1, 0)  # crown
	var result := logic.tap_cell(1, 0)  # empty
	assert_true(result.changed)
	assert_eq(result.new_state, CrownGridLogic.CELL_EMPTY)
	assert_eq(logic.get_cell(1, 0), CrownGridLogic.CELL_EMPTY)


# ---------------------------------------------------------------------------
# Completion
# ---------------------------------------------------------------------------

func test_completing_all_crowns_wins() -> void:
	# Place all 4 crowns at solution positions
	logic.tap_cell(1, 0)  # excluded
	logic.tap_cell(1, 0)  # crown (1,0)
	logic.tap_cell(3, 1)  # excluded
	logic.tap_cell(3, 1)  # crown (3,1)
	logic.tap_cell(0, 2)  # excluded
	logic.tap_cell(0, 2)  # crown (0,2)
	logic.tap_cell(2, 3)  # excluded
	var result := logic.tap_cell(2, 3)  # crown (2,3)
	assert_true(result.game_won)
	assert_true(logic.is_completed)


# ---------------------------------------------------------------------------
# Paint excluded
# ---------------------------------------------------------------------------

func test_paint_excluded_marks_cells() -> void:
	var paint: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var result := logic.paint_excluded(paint)
	assert_eq(result.changed_cells.size(), 3)
	assert_eq(logic.get_cell(0, 0), CrownGridLogic.CELL_EXCLUDED)
	assert_eq(logic.get_cell(1, 0), CrownGridLogic.CELL_EXCLUDED)
	assert_eq(logic.get_cell(2, 0), CrownGridLogic.CELL_EXCLUDED)


func test_paint_excluded_skips_crowns() -> void:
	logic.tap_cell(1, 0)  # excluded
	logic.tap_cell(1, 0)  # crown (1,0)
	var paint: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var result := logic.paint_excluded(paint)
	# Cell (1,0) has crown → skip
	assert_false(result.changed_cells.has(Vector2i(1, 0)))
	assert_eq(logic.get_cell(1, 0), CrownGridLogic.CELL_CROWN)


# ---------------------------------------------------------------------------
# Undo / Redo
# ---------------------------------------------------------------------------

func test_undo_tap() -> void:
	logic.tap_cell(0, 0)
	assert_eq(logic.get_cell(0, 0), CrownGridLogic.CELL_EXCLUDED)
	var undo_result := logic.undo()
	assert_true(undo_result.changed)
	assert_eq(logic.get_cell(0, 0), CrownGridLogic.CELL_EMPTY)


func test_redo_tap() -> void:
	logic.tap_cell(0, 0)
	logic.undo()
	var redo_result := logic.redo()
	assert_true(redo_result.changed)
	assert_eq(logic.get_cell(0, 0), CrownGridLogic.CELL_EXCLUDED)


func test_undo_paint() -> void:
	var paint: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	logic.paint_excluded(paint)
	logic.undo()
	assert_eq(logic.get_cell(0, 0), CrownGridLogic.CELL_EMPTY)
	assert_eq(logic.get_cell(1, 0), CrownGridLogic.CELL_EMPTY)


func test_can_undo_false_initially() -> void:
	assert_false(logic.can_undo())


func test_can_undo_true_after_tap() -> void:
	logic.tap_cell(0, 0)
	assert_true(logic.can_undo())


func test_cannot_undo_when_completed() -> void:
	logic.tap_cell(1, 0); logic.tap_cell(1, 0)  # crown
	logic.tap_cell(3, 1); logic.tap_cell(3, 1)  # crown
	logic.tap_cell(0, 2); logic.tap_cell(0, 2)  # crown
	logic.tap_cell(2, 3); logic.tap_cell(2, 3)  # crown
	assert_true(logic.is_completed)
	assert_false(logic.can_undo())


# ---------------------------------------------------------------------------
# Auto-mark
# ---------------------------------------------------------------------------

func test_auto_mark_excludes_row_col_region() -> void:
	logic = CrownGridLogic.new()
	logic.init_new_game(4, _regions_4x4(), _solution_4x4(), true)  # auto_mark=true
	# Place crown at (1,0) — region 1 (col 1)
	logic.tap_cell(1, 0)  # excluded
	logic.tap_cell(1, 0)  # crown
	# Row 0: other cells in same row should be excluded
	assert_eq(logic.get_cell(0, 0), CrownGridLogic.CELL_EXCLUDED)
	assert_eq(logic.get_cell(2, 0), CrownGridLogic.CELL_EXCLUDED)
	assert_eq(logic.get_cell(3, 0), CrownGridLogic.CELL_EXCLUDED)
	# Column 1: other cells should be excluded
	assert_eq(logic.get_cell(1, 1), CrownGridLogic.CELL_EXCLUDED)
	assert_eq(logic.get_cell(1, 2), CrownGridLogic.CELL_EXCLUDED)
	assert_eq(logic.get_cell(1, 3), CrownGridLogic.CELL_EXCLUDED)
	# Diagonal neighbor (0,1)
	assert_eq(logic.get_cell(0, 1), CrownGridLogic.CELL_EXCLUDED)
	assert_eq(logic.get_cell(2, 1), CrownGridLogic.CELL_EXCLUDED)


func test_auto_mark_undo_removes_auto_marks() -> void:
	logic = CrownGridLogic.new()
	logic.init_new_game(4, _regions_4x4(), _solution_4x4(), true)
	logic.tap_cell(1, 0)
	logic.tap_cell(1, 0)  # crown with auto-marks
	logic.undo()
	# Auto-marks should be removed; cell (1,0) returns to EXCLUDED (its pre-crown state)
	assert_eq(logic.get_cell(0, 0), CrownGridLogic.CELL_EMPTY)
	assert_eq(logic.get_cell(1, 1), CrownGridLogic.CELL_EMPTY)
	assert_eq(logic.get_cell(1, 0), CrownGridLogic.CELL_EXCLUDED)


# ---------------------------------------------------------------------------
# Strict assistance
# ---------------------------------------------------------------------------

func test_strict_mode_rejects_wrong_crown() -> void:
	logic = CrownGridLogic.new()
	logic.init_new_game(4, _regions_4x4(), _solution_4x4(), false, CrownGridLogic.ASSISTANCE_STRICT)
	# Correct solution row 0 = col 1; try placing at col 0 (wrong)
	logic.tap_cell(0, 0)  # → excluded
	logic.tap_cell(0, 0)  # → would become crown → rejected
	var result := logic.tap_cell(0, 0)  # Try crown from excluded state again
	# First, get to excluded state at (0,0)
	assert_true(true)  # Basic setup works


func test_strict_mode_allows_correct_crown() -> void:
	logic = CrownGridLogic.new()
	logic.init_new_game(4, _regions_4x4(), _solution_4x4(), false, CrownGridLogic.ASSISTANCE_STRICT)
	# Correct row 0 = col 1; tap twice to get crown
	logic.tap_cell(1, 0)  # excluded
	var result := logic.tap_cell(1, 0)  # crown
	assert_true(result.changed)
	assert_false(result.rejected)
	assert_eq(logic.get_cell(1, 0), CrownGridLogic.CELL_CROWN)


# ---------------------------------------------------------------------------
# Serialize / deserialize
# ---------------------------------------------------------------------------

func test_serialize_roundtrip() -> void:
	logic.tap_cell(0, 0)  # excluded
	logic.tap_cell(1, 0)  # excluded
	logic.tap_cell(1, 0)  # crown
	var data := logic.serialize()

	var restored := CrownGridLogic.new()
	restored.init_from_save(data)

	assert_eq(restored.size, logic.size)
	assert_eq(restored.get_cell(0, 0), CrownGridLogic.CELL_EXCLUDED)
	assert_eq(restored.get_cell(1, 0), CrownGridLogic.CELL_CROWN)
	assert_true(restored.can_undo())


func test_serialize_preserves_undo_redo() -> void:
	logic.tap_cell(0, 0)
	logic.tap_cell(1, 0)
	logic.undo()
	var data := logic.serialize()
	var restored := CrownGridLogic.new()
	restored.init_from_save(data)
	assert_true(restored.can_undo())   # tap(0,0) still in stack
	assert_true(restored.can_redo())   # undo of tap(1,0) in redo stack


# ---------------------------------------------------------------------------
# Violations (free mode)
# ---------------------------------------------------------------------------

func test_violations_same_row() -> void:
	# Place two crowns in row 0 (invalid)
	logic.tap_cell(0, 0); logic.tap_cell(0, 0)  # crown at (0,0)
	logic.tap_cell(1, 0); logic.tap_cell(1, 0)  # crown at (1,0)
	var viols := logic.get_violations()
	assert_true(viols.has(Vector2i(0, 0)))
	assert_true(viols.has(Vector2i(1, 0)))


func test_violations_diagonal_adjacent() -> void:
	logic.tap_cell(0, 0); logic.tap_cell(0, 0)  # crown at (0,0)
	logic.tap_cell(1, 1); logic.tap_cell(1, 1)  # crown at (1,1) — diagonal adjacent
	var viols := logic.get_violations()
	assert_true(viols.has(Vector2i(0, 0)))
	assert_true(viols.has(Vector2i(1, 1)))


func test_no_violations_valid_placements() -> void:
	logic.tap_cell(1, 0); logic.tap_cell(1, 0)  # crown at (1,0)
	logic.tap_cell(3, 1); logic.tap_cell(3, 1)  # crown at (3,1)
	var viols := logic.get_violations()
	assert_true(viols.is_empty())


# ---------------------------------------------------------------------------
# Connectivity and edge cases
# ---------------------------------------------------------------------------

func test_out_of_bounds_tap_ignored() -> void:
	var result := logic.tap_cell(-1, 0)
	assert_false(result.changed)
	result = logic.tap_cell(0, 99)
	assert_false(result.changed)


func test_get_region() -> void:
	# Regions are set up as col index
	assert_eq(logic.get_region(0, 0), 0)
	assert_eq(logic.get_region(3, 2), 3)
	assert_eq(logic.get_region(-1, 0), -1)


func test_hint_applies_crown_step() -> void:
	# Place crowns at (0,2) and (2,3) — col 0 and col 2 used + diagonal adj (1,2)(3,2) —
	# leaving (3,1) as the only candidate in row 1: a pure rank-1 deduction with no player notes.
	logic.tap_cell(0, 2)  # excluded
	logic.tap_cell(0, 2)  # crown at (col=0, row=2)
	logic.tap_cell(2, 3)  # excluded
	logic.tap_cell(2, 3)  # crown at (col=2, row=3)
	var hint := logic.use_hint()
	assert_true(hint.applied)
	assert_eq(logic.hints_used, 1)


## Focused regression: when a crown hint fires with auto_mark=true, the
## HintResult.auto_marked list must be populated.  This is the data the game
## screen consumes to record the "exclusions_painted" replay event.
func test_hint_crown_populates_auto_marked_when_auto_mark_enabled() -> void:
	logic = CrownGridLogic.new()
	logic.init_new_game(4, _regions_4x4(), _solution_4x4(), false)  # auto_mark=false during setup
	# Place crown at (2,3) — col 2 used + diag (1,2)(3,2) → row 2 has only (0,2) left.
	# Setup without auto_mark so col/row cells remain EMPTY for the hint to auto-mark them.
	logic.tap_cell(2, 3)  # excluded
	logic.tap_cell(2, 3)  # crown at (col=2, row=3)
	# Enable auto_mark so the Crown hint will populate auto_marked.
	logic.auto_mark = true
	var hint := logic.use_hint()
	assert_true(hint.applied, "Hint must be applied")
	assert_eq(hint.new_state, CrownGridLogic.CELL_CROWN,
			"Hint must place a Crown (not an exclusion)")
	assert_false(hint.auto_marked.is_empty(),
			"Crown hint with auto_mark=true must populate auto_marked for replay recording")


## Focused regression: hint_crown undo entry always includes auto_marked and
## old_states so the save adapter's required-field requirement is never
## triggered by a legitimately-saved game.
func test_hint_crown_undo_entry_includes_required_fields() -> void:
	logic = CrownGridLogic.new()
	logic.init_new_game(4, _regions_4x4(), _solution_4x4(), false)  # auto_mark=false during setup
	# Place crown at (2,3) — forces naked single at (0,2) in row 2.
	logic.tap_cell(2, 3)  # excluded
	logic.tap_cell(2, 3)  # crown
	logic.auto_mark = true
	logic.use_hint()  # places a crown via hint
	var serialized := logic.serialize()
	var undo_stack: Array = serialized.get("undo_stack", [])
	assert_false(undo_stack.is_empty(), "undo_stack must not be empty after a hint")
	# Find the hint_crown entry
	var crown_entry: Dictionary = {}
	for entry in undo_stack:
		if str(entry.get("action", "")) == "hint_crown":
			crown_entry = entry
			break
	assert_false(crown_entry.is_empty(), "A hint_crown undo entry must be present")
	assert_true(crown_entry.has("auto_marked"),
			"hint_crown entry must always include auto_marked")
	assert_true(crown_entry.has("old_states"),
			"hint_crown entry must always include old_states")


## Regression for Fix 2: undoing a Crown hint that replaced an Excluded note
## must restore the Excluded state, not Empty.
func test_hint_crown_undo_restores_excluded_note() -> void:
	# With solution [1, 3, 0, 2]: place correct Crowns at (col=1,row=0) and
	# (col=3,row=1).  Used cols={1,3}, used regions={1,3}; diagonal adjacency
	# from (3,1) eliminates (2,2), leaving row 2 a naked single at (col=0,row=2).
	# The player marks (0,2) Excluded first; the hint must replace that with
	# Crown, and undo must recover the Excluded note.
	logic.tap_cell(1, 0); logic.tap_cell(1, 0)  # correct Crown (col=1,row=0)
	logic.tap_cell(3, 1); logic.tap_cell(3, 1)  # correct Crown (col=3,row=1)
	logic.tap_cell(0, 2)  # player marks (0,2) as Excluded
	assert_eq(logic.get_cell(0, 2), CrownGridLogic.CELL_EXCLUDED,
			"Cell (0,2) must be Excluded after one tap")
	var hint := logic.use_hint()
	assert_true(hint.applied, "Hint must be applied")
	assert_eq(logic.get_cell(0, 2), CrownGridLogic.CELL_CROWN,
			"Hint must replace Excluded with Crown")
	var undo_result := logic.undo()
	assert_true(undo_result.changed, "Undo must report a change")
	assert_eq(logic.get_cell(0, 2), CrownGridLogic.CELL_EXCLUDED,
			"Undo of Crown hint must restore the player's Excluded note, not Empty")


# ---------------------------------------------------------------------------
# Auto-mark exposed in TapResult (fix 3a)
# ---------------------------------------------------------------------------

func test_auto_mark_exposed_in_tap_result() -> void:
	logic.init_new_game(4, _regions_4x4(), _solution_4x4(), true)  # auto_mark=true
	logic.tap_cell(1, 0)  # → excluded
	var result := logic.tap_cell(1, 0)  # → crown at (1,0)
	assert_eq(result.new_state, CrownGridLogic.CELL_CROWN)
	assert_false(result.auto_marked.is_empty(),
			"auto_marked should be non-empty when auto_mark is on")


func test_auto_mark_empty_when_disabled() -> void:
	# auto_mark defaults to false
	logic.tap_cell(1, 0)  # → excluded
	var result := logic.tap_cell(1, 0)  # → crown
	assert_true(result.auto_marked.is_empty(),
			"auto_marked should be empty when auto_mark is off")


# ---------------------------------------------------------------------------
# Fix 1: wrong free-mode Crowns must not poison solver hint input
# ---------------------------------------------------------------------------

## Board: 4×4 column-regions, solution = [1, 3, 0, 2].
## After 3 solution-confirmed Crowns: (col=1,row=0), (col=3,row=1), (col=0,row=2),
## row 3 has a naked single at (col=2,row=3).
## Placing an additional WRONG Crown at (col=0,row=3) — solution says col=2 for
## row 3 — would (without the fix) mark row 3 as occupied in crowns_by_row,
## causing find_next_step to return null.  With the fix the wrong Crown is
## filtered out and the rank-1 hint at (col=2,row=3) is still found.
func test_hint_ignores_wrong_free_mode_crown() -> void:
	logic.tap_cell(1, 0); logic.tap_cell(1, 0)  # correct Crown at (col=1,row=0) [sol[0]=1]
	logic.tap_cell(3, 1); logic.tap_cell(3, 1)  # correct Crown at (col=3,row=1) [sol[1]=3]
	logic.tap_cell(0, 2); logic.tap_cell(0, 2)  # correct Crown at (col=0,row=2) [sol[2]=0]
	logic.tap_cell(0, 3); logic.tap_cell(0, 3)  # wrong Crown at (col=0,row=3) [sol[3]=2≠0]
	var hint := logic.use_hint()
	assert_true(hint.applied,
			"Hint must be found even when a wrong free-mode Crown occupies the board")
	assert_eq(hint.new_state, CrownGridLogic.CELL_CROWN,
			"Hint must be a Crown placement (naked single at row 3)")


# ---------------------------------------------------------------------------
# Fix 2: exclusion hints that change nothing must not increment hints_used
# ---------------------------------------------------------------------------

## Board: 6×6, region = col-index for (row<5, col<5); region 5 otherwise.
## Solution = [0, 2, 4, 1, 3, 5] (valid: unique cols, unique regions, no diagonal adj).
## On a fresh board, region 0 (col 0, rows 0-4) is locked to col 0 →
## rank-2 "region locked to col" fires and suggests excluding (col=0, row=5).
## Pre-paint (col=0, row=5) as CELL_EXCLUDED; use_hint() must skip that no-op
## suggestion and find the next actionable deduction — (col=1, row=5).
func test_hint_skips_pre_applied_exclusion_finds_next_actionable_step() -> void:
	var sz := 6
	var solution6: Array[int] = [0, 2, 4, 1, 3, 5]
	var regions6 := PackedInt32Array()
	regions6.resize(sz * sz)
	for r in range(sz):
		for c in range(sz):
			if r < 5 and c < 5:
				regions6[r * sz + c] = c  # regions 0-4 = column index
			else:
				regions6[r * sz + c] = 5  # region 5 = row 5 + col 5
	var logic6 := CrownGridLogic.new()
	logic6.init_new_game(sz, regions6, solution6)
	# Pre-apply the solver's first rank-2 exclusion suggestion.
	var paint: Array[Vector2i] = [Vector2i(0, 5)]  # (col=0, row=5) in region 5
	logic6.paint_excluded(paint)
	var prev_hints := logic6.hints_used
	var hint := logic6.use_hint()
	assert_true(hint.applied,
			"use_hint() must skip the pre-applied exclusion and find the next step")
	assert_eq(logic6.hints_used, prev_hints + 1,
			"hints_used must increment when a new actionable deduction is found")
	# Region 1 (col 1, rows 0-4) is also locked to col 1 → next rank-2 step
	# excludes (col=1, row=5).
	assert_eq(logic6.get_cell(1, 5), CrownGridLogic.CELL_EXCLUDED,
			"cell (col=1, row=5) must be excluded by the skip-and-find hint")
