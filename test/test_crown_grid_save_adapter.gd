extends GutTest

## Regression tests for CrownGridSaveAdapter validation.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a save dictionary with regions laid out as columns (region i = column i).
## The solution uses an even-first zigzag pattern so no two consecutive crowns
## are diagonally adjacent, making it a valid Crown Grid solution.
## The tier is derived automatically from size so that the tier/size mapping is
## always valid (Easy=6, Medium=7, Hard=8, Expert=9).
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
	var tier: int
	match size:
		6: tier = 0
		7: tier = 1
		8: tier = 2
		9: tier = 3
		_: tier = 0
	return {
		"size": size,
		"tier": tier,
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
	# Each tier must be accepted only when paired with its matching board size.
	var tier_sizes: Dictionary = {0: 6, 1: 7, 2: 8, 3: 9}
	for t in [0, 1, 2, 3]:
		var d := _valid_save(tier_sizes[t])
		assert_true(adapter._can_resume_from(d), "Tier %d with size %d should be accepted" % [t, tier_sizes[t]])


# ---------------------------------------------------------------------------
# Tier/size mismatch validation (fix 3)
# ---------------------------------------------------------------------------

func test_tier_size_mismatch_easy_rejected() -> void:
	# Tier 0 (Easy) requires size 6.  Build a valid size-9 save, then override
	# tier to 0 so only the tier/size mapping check fires.
	var d := _valid_save(9)
	d["tier"] = 0  # Mismatch: tier 0 (Easy) expects size 6, not 9
	assert_false(adapter._can_resume_from(d),
			"Tier 0 (Easy) with size 9 must be rejected")


func test_tier_size_mismatch_expert_rejected() -> void:
	# Tier 3 (Expert) requires size 9. A size-6 save with tier=3 must be rejected.
	var d := _valid_save(6)
	d["tier"] = 3  # Mismatch: Expert expects size 9, not 6
	assert_false(adapter._can_resume_from(d),
			"Tier 3 (Expert) with size 6 must be rejected")


func test_tier_size_medium_correct() -> void:
	# Tier 1 (Medium) with size 7 must be accepted.
	assert_true(adapter._can_resume_from(_valid_save(7)),
			"Tier 1 (Medium) with size 7 must be accepted")


func test_tier_size_hard_correct() -> void:
	# Tier 2 (Hard) with size 8 must be accepted.
	assert_true(adapter._can_resume_from(_valid_save(8)),
			"Tier 2 (Hard) with size 8 must be accepted")


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


# ---------------------------------------------------------------------------
# auto_marked coordinate validation (fix 2)
# ---------------------------------------------------------------------------

func test_tap_entry_auto_marked_oob_coord_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "from": 0, "to": 2,
			"auto_marked": [[99, 0]]}]
	assert_false(adapter._can_resume_from(d),
			"tap entry with out-of-bounds auto_marked coordinate must be rejected")


func test_tap_entry_auto_marked_non_array_element_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "from": 0, "to": 2,
			"auto_marked": ["bad"]}]
	assert_false(adapter._can_resume_from(d),
			"tap entry with non-array auto_marked element must be rejected")


func test_tap_entry_auto_marked_valid_accepted() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "from": 0, "to": 2,
			"auto_marked": [[1, 0], [2, 0]]}]
	assert_true(adapter._can_resume_from(d),
			"tap entry with valid auto_marked coordinates must be accepted")


func test_hint_crown_auto_marked_oob_coord_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "hint_crown", "cell": [0, 0],
			"auto_marked": [[0, 99]]}]
	assert_false(adapter._can_resume_from(d),
			"hint_crown entry with out-of-bounds auto_marked coordinate must be rejected")


func test_hint_crown_auto_marked_valid_accepted() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "hint_crown", "cell": [2, 3],
			"auto_marked": [[0, 3], [1, 3]]}]
	assert_true(adapter._can_resume_from(d),
			"hint_crown entry with valid auto_marked coordinates must be accepted")


# ---------------------------------------------------------------------------
# old_states validation (fix 2)
# ---------------------------------------------------------------------------

func test_tap_old_states_non_dict_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "from": 0, "to": 1,
			"old_states": "bad"}]
	assert_false(adapter._can_resume_from(d),
			"tap entry with non-dict old_states must be rejected")


func test_tap_old_states_oob_key_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "from": 0, "to": 1,
			"old_states": {"99,0": 0}}]
	assert_false(adapter._can_resume_from(d),
			"tap entry with out-of-bounds old_states key must be rejected")


func test_tap_old_states_invalid_value_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "from": 0, "to": 1,
			"old_states": {"0,0": 5}}]
	assert_false(adapter._can_resume_from(d),
			"tap entry with invalid old_states value must be rejected")


func test_tap_old_states_valid_accepted() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "tap", "cell": [0, 0], "from": 0, "to": 1,
			"old_states": {"0,0": 0, "1,0": 0}}]
	assert_true(adapter._can_resume_from(d),
			"tap entry with valid old_states must be accepted")


func test_paint_old_states_non_string_key_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "paint", "changed": [[0, 0]],
			"old_states": {42: 0}}]
	assert_false(adapter._can_resume_from(d),
			"paint entry with non-string old_states key must be rejected")


func test_paint_old_states_malformed_key_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "paint", "changed": [[0, 0]],
			"old_states": {"not_coords": 0}}]
	assert_false(adapter._can_resume_from(d),
			"paint entry with malformed old_states key must be rejected")


func test_paint_old_states_valid_accepted() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "paint", "changed": [[0, 1]],
			"old_states": {"0,1": 0}}]
	assert_true(adapter._can_resume_from(d),
			"paint entry with valid old_states must be accepted")


func test_hint_exclude_old_states_oob_key_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "hint_exclude", "changed": [[0, 0]],
			"old_states": {"0,99": 0}}]
	assert_false(adapter._can_resume_from(d),
			"hint_exclude entry with out-of-bounds old_states key must be rejected")


func test_hint_crown_old_states_invalid_state_value_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{"action": "hint_crown", "cell": [1, 1],
			"old_states": {"1,1": 9}}]
	assert_false(adapter._can_resume_from(d),
			"hint_crown entry with invalid old_states cell state must be rejected")

