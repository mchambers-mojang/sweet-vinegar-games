extends GutTest

## Regression tests for CrownGridSaveAdapter validation.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a save dictionary with regions laid out as columns (region i = column i).
## The solution uses an even-first zigzag pattern so no two consecutive crowns
## are diagonally adjacent, making it a valid Crown Grid solution.
func _valid_save(size: int = 6) -> Dictionary:
	var regions: Array = []
	for i in range(size * size):
		regions.append(i % size)
	# Even-indexed columns first, then odd — avoids diagonal adjacency in consecutive rows.
	var solution: Array = []
	for i in range(0, size, 2):
		solution.append(i)
	for i in range(1, size, 2):
		solution.append(i)
	var cells: Array = []
	for i in range(size * size):
		cells.append(0)
	return {
		"size": size,
		"tier": 0,
		"regions": regions,
		"solution": solution,
		"cells": cells,
		"is_completed": false,
		"assistance_mode": 0,
	}


var adapter: CrownGridSaveAdapter


func before_each() -> void:
	adapter = CrownGridSaveAdapter.new()


# ---------------------------------------------------------------------------
# Valid save accepted
# ---------------------------------------------------------------------------

func test_valid_save_accepted() -> void:
	assert_true(adapter._can_resume_from(_valid_save()))


func test_valid_save_size_9_accepted() -> void:
	assert_true(adapter._can_resume_from(_valid_save(9)))


# ---------------------------------------------------------------------------
# Completed save rejected
# ---------------------------------------------------------------------------

func test_completed_save_rejected() -> void:
	var d := _valid_save()
	d["is_completed"] = true
	assert_false(adapter._can_resume_from(d))


# ---------------------------------------------------------------------------
# Invalid size
# ---------------------------------------------------------------------------

func test_invalid_size_5_rejected() -> void:
	var d := _valid_save()
	d["size"] = 5
	assert_false(adapter._can_resume_from(d))


func test_invalid_size_10_rejected() -> void:
	var d := _valid_save()
	d["size"] = 10
	assert_false(adapter._can_resume_from(d))


func test_invalid_size_string_rejected() -> void:
	var d := _valid_save()
	d["size"] = "six"
	assert_false(adapter._can_resume_from(d))


# ---------------------------------------------------------------------------
# Invalid tier (fix 6)
# ---------------------------------------------------------------------------

func test_invalid_tier_negative_rejected() -> void:
	var d := _valid_save()
	d["tier"] = -1
	assert_false(adapter._can_resume_from(d))


func test_invalid_tier_4_rejected() -> void:
	var d := _valid_save()
	d["tier"] = 4
	assert_false(adapter._can_resume_from(d))


func test_valid_tiers_accepted() -> void:
	for t in [0, 1, 2, 3]:
		var d := _valid_save()
		d["tier"] = t
		assert_true(adapter._can_resume_from(d), "Tier %d should be accepted" % t)


# ---------------------------------------------------------------------------
# Invalid regions
# ---------------------------------------------------------------------------

func test_regions_wrong_length_rejected() -> void:
	var d := _valid_save()
	d["regions"] = [0, 1, 2]  # Too short
	assert_false(adapter._can_resume_from(d))


func test_regions_missing_rejected() -> void:
	var d := _valid_save()
	d.erase("regions")
	assert_false(adapter._can_resume_from(d))


func test_regions_invalid_id_rejected() -> void:
	var d := _valid_save()
	# Set a region ID that equals size (out of range 0..N-1)
	d["regions"][0] = 99
	assert_false(adapter._can_resume_from(d))


func test_regions_missing_region_id_rejected() -> void:
	# All cells set to region 0, no other region IDs present
	var d := _valid_save(6)
	var regions: Array = []
	for i in range(36):
		regions.append(0)  # Only region 0
	d["regions"] = regions
	assert_false(adapter._can_resume_from(d))


# ---------------------------------------------------------------------------
# Invalid solution
# ---------------------------------------------------------------------------

func test_solution_wrong_length_rejected() -> void:
	var d := _valid_save()
	d["solution"] = [0, 1]  # Too short
	assert_false(adapter._can_resume_from(d))


func test_solution_col_out_of_range_rejected() -> void:
	var d := _valid_save()
	(d["solution"] as Array)[0] = 99
	assert_false(adapter._can_resume_from(d))


# ---------------------------------------------------------------------------
# Invalid cells (fix 6)
# ---------------------------------------------------------------------------

func test_cells_wrong_length_rejected() -> void:
	var d := _valid_save()
	d["cells"] = [0, 1, 2]  # Too short
	assert_false(adapter._can_resume_from(d))


func test_cells_invalid_value_rejected() -> void:
	var d := _valid_save()
	(d["cells"] as Array)[0] = 5  # 5 is not a valid cell state (0/1/2)
	assert_false(adapter._can_resume_from(d))


# ---------------------------------------------------------------------------
# Invalid assistance_mode (fix 6)
# ---------------------------------------------------------------------------

func test_invalid_assistance_mode_rejected() -> void:
	var d := _valid_save()
	d["assistance_mode"] = 5
	assert_false(adapter._can_resume_from(d))


func test_valid_assistance_modes_accepted() -> void:
	for m in [0, 1]:
		var d := _valid_save()
		d["assistance_mode"] = m
		assert_true(adapter._can_resume_from(d), "assistance_mode %d should be accepted" % m)


# ---------------------------------------------------------------------------
# Invalid undo entries (fix 6)
# ---------------------------------------------------------------------------

func test_invalid_undo_entry_non_dict_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = ["not_a_dict"]
	assert_false(adapter._can_resume_from(d))


func test_invalid_undo_entry_unknown_action_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "unknown_action"}]
	assert_false(adapter._can_resume_from(d))


func test_valid_undo_entries_accepted() -> void:
	var d := _valid_save()
	d["undo_stack"] = [
		{"action": "tap", "cell": [1, 0], "from": 0, "to": 1, "auto_marked": [], "old_states": {}},
	]
	assert_true(adapter._can_resume_from(d))


# ---------------------------------------------------------------------------
# Undo entry field validation (new: required fields per action type)
# ---------------------------------------------------------------------------

func test_tap_entry_missing_cell_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "from": 0, "to": 1}]
	assert_false(adapter._can_resume_from(d))


func test_tap_entry_missing_from_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "to": 1}]
	assert_false(adapter._can_resume_from(d))


func test_tap_entry_missing_to_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "from": 0}]
	assert_false(adapter._can_resume_from(d))


func test_paint_entry_missing_changed_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "paint"}]
	assert_false(adapter._can_resume_from(d))


func test_paint_entry_valid_accepted() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "paint", "changed": [[0, 1], [1, 2]], "old_states": {}}]
	assert_true(adapter._can_resume_from(d))


func test_hint_crown_entry_missing_cell_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "hint_crown"}]
	assert_false(adapter._can_resume_from(d))


func test_hint_crown_entry_valid_accepted() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "hint_crown", "cell": [2, 3], "auto_marked": [], "old_states": {}}]
	assert_true(adapter._can_resume_from(d))


func test_hint_exclude_entry_valid_accepted() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "hint_exclude", "changed": [[0, 1]], "old_states": {}}]
	assert_true(adapter._can_resume_from(d))


# ---------------------------------------------------------------------------
# redo_stack validation (new)
# ---------------------------------------------------------------------------

func test_redo_stack_non_array_rejected() -> void:
	var d := _valid_save()
	d["redo_stack"] = "not_an_array"
	assert_false(adapter._can_resume_from(d))


func test_redo_stack_invalid_entry_rejected() -> void:
	var d := _valid_save()
	d["redo_stack"] = [{"action": "unknown_action"}]
	assert_false(adapter._can_resume_from(d))


func test_redo_stack_valid_entries_accepted() -> void:
	var d := _valid_save()
	d["redo_stack"] = [
		{"action": "tap", "cell": [1, 0], "from": 0, "to": 1, "auto_marked": [], "old_states": {}},
	]
	assert_true(adapter._can_resume_from(d))


func test_redo_stack_missing_accepted() -> void:
	var d := _valid_save()
	d.erase("redo_stack")
	assert_true(adapter._can_resume_from(d))


# ---------------------------------------------------------------------------
# Region connectivity validation (new)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Region connectivity validation — 6x6 fixtures (valid board size)
# ---------------------------------------------------------------------------

## Build a 6x6 region array where region 0 is disconnected:
## column 0 rows 0-2 form one piece and column 0 rows 4-5 form another;
## the gap at (row=3, col=0) belongs to region 1, breaking connectivity.
func _disconnected_6x6_regions() -> Array:
	# Start from column layout (region i = column i) then move row 3 col 0 to region 1.
	var regions: Array = []
	for r in range(6):
		for c in range(6):
			if r == 3 and c == 0:
				regions.append(1)  # Region 0 gap — disconnects col 0 into two parts
			else:
				regions.append(c)
	return regions


## Find a valid crown placement for the disconnected layout above.
## Region 0 cells: (0,0),(0,1),(0,2),(0,4),(0,5). Region 0 crown must be in col 0.
## Crown at (col,row): row0→col0(reg0), row1→col2(reg2), row2→col4(reg4),
##                     row3→col1(reg1), row4→col3(reg3), row5→col5(reg5)
## Diagonal checks: (0,0)→(2,1)=diff2✓, (2,1)→(4,2)=diff2✓, (4,2)→(1,3)=diff3✓,
##                  (1,3)→(3,4)=diff2✓, (3,4)→(5,5)=diff2✓
func _disconnected_6x6_solution() -> Array:
	return [0, 2, 4, 1, 3, 5]


func test_disconnected_region_rejected() -> void:
	# 6x6 save where region 0 is split across two non-adjacent pieces.
	var sz := 6
	var regions := _disconnected_6x6_regions()
	var sol := _disconnected_6x6_solution()
	var cells: Array = []
	for i in range(sz * sz):
		cells.append(0)
	var d := {
		"size": sz,
		"tier": 0,
		"regions": regions,
		"solution": sol,
		"cells": cells,
		"is_completed": false,
	}
	# Topology passes (all regions 0-5 present) but connectivity fails.
	assert_false(adapter._can_resume_from(d),
			"Disconnected region 0 in 6x6 save must be rejected")


func test_connected_regions_accepted() -> void:
	# 6x6 with column regions — every region is a single connected column.
	# Uses the standard _valid_save(6) fixture; verifies connectivity check
	# does not incorrectly reject a well-formed board.
	assert_true(adapter._can_resume_from(_valid_save(6)),
			"6x6 save with fully connected column regions must be accepted")


# ---------------------------------------------------------------------------
# Solution compatibility validation (new)
# ---------------------------------------------------------------------------

func test_solution_diagonal_adjacent_rejected() -> void:
	# Solution with consecutive crowns diagonally adjacent: [0, 1, 2, ...] → (0,0)→(1,1) adjacent
	var d := _valid_save()
	# Override solution with consecutive diagonal pattern
	var sz: int = d["size"]
	var bad_sol: Array = []
	for i in range(sz):
		bad_sol.append(i)  # [0,1,2,3,4,5] — (0,0)→(1,1) diag adjacent
	d["solution"] = bad_sol
	assert_false(adapter._can_resume_from(d))


func test_solution_duplicate_column_rejected() -> void:
	var d := _valid_save()
	var sz: int = d["size"]
	var bad_sol: Array = []
	for i in range(sz):
		bad_sol.append(0)  # all crowns in col 0 → duplicate column
	d["solution"] = bad_sol
	assert_false(adapter._can_resume_from(d))


# ---------------------------------------------------------------------------
# cells field is now required (fix 2 regression)
# ---------------------------------------------------------------------------

func test_cells_missing_rejected() -> void:
	var d := _valid_save()
	d.erase("cells")
	assert_false(adapter._can_resume_from(d),
			"Missing cells field must be rejected")


# ---------------------------------------------------------------------------
# Undo entry coordinate out-of-bounds validation (fix 2 regression)
# ---------------------------------------------------------------------------

func test_tap_entry_cell_col_oob_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [99, 0], "from": 0, "to": 1}]
	assert_false(adapter._can_resume_from(d),
			"tap entry with out-of-bounds column must be rejected")


func test_tap_entry_cell_row_oob_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 99], "from": 0, "to": 1}]
	assert_false(adapter._can_resume_from(d),
			"tap entry with out-of-bounds row must be rejected")


func test_tap_entry_invalid_from_state_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "from": 5, "to": 1}]
	assert_false(adapter._can_resume_from(d),
			"tap entry with invalid from state must be rejected")


func test_tap_entry_invalid_to_state_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "from": 0, "to": 9}]
	assert_false(adapter._can_resume_from(d),
			"tap entry with invalid to state must be rejected")


func test_tap_entry_auto_marked_non_array_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "from": 0, "to": 1, "auto_marked": "bad"}]
	assert_false(adapter._can_resume_from(d),
			"tap entry with auto_marked that is not an Array must be rejected")


func test_paint_entry_changed_oob_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "paint", "changed": [[99, 0]]}]
	assert_false(adapter._can_resume_from(d),
			"paint entry with out-of-bounds changed cell must be rejected")


func test_hint_crown_entry_cell_oob_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "hint_crown", "cell": [0, 99]}]
	assert_false(adapter._can_resume_from(d),
			"hint_crown entry with out-of-bounds cell must be rejected")


func test_hint_crown_entry_auto_marked_non_array_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "hint_crown", "cell": [0, 0], "auto_marked": 42}]
	assert_false(adapter._can_resume_from(d),
			"hint_crown entry with auto_marked that is not an Array must be rejected")


func test_hint_exclude_entry_changed_oob_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "hint_exclude", "changed": [[0, 99]]}]
	assert_false(adapter._can_resume_from(d),
			"hint_exclude entry with out-of-bounds changed cell must be rejected")


func test_valid_tap_entry_in_bounds_accepted() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "from": 0, "to": 1, "auto_marked": []}]
	assert_true(adapter._can_resume_from(d),
			"Valid tap entry with in-bounds coordinates must be accepted")

