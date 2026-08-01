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

func test_disconnected_region_rejected() -> void:
	# Create a 4x4 save where region 0 has cells [0,0] and [1,3] (not 4-connected)
	var sz := 4
	var regions: Array = []
	for r in range(sz):
		for c in range(sz):
			# Region 0: only (0,0) and (3,1) — not connected; all others in 1–3
			if r == 0 and c == 0:
				regions.append(0)
			elif r == 3 and c == 1:
				regions.append(0)
			else:
				# Distribute the rest evenly into regions 1, 2, 3
				var cell_idx := r * sz + c
				regions.append(1 + (cell_idx % 3))
	# Build a solution that matches the region topology for regions 1-3
	# (This save will fail the topology check before connectivity if region counts are wrong.)
	# Instead, use a simpler setup with N=4 and cleanly split regions, but make one disconnected.
	# 4x4, 4 regions. Make region 0 = col 0 rows 0,1 + col 3 rows 2,3 (disconnected).
	var r2: Array = []
	for row in range(sz):
		for col in range(sz):
			if col == 0 and row < 2:
				r2.append(0)
			elif col == 3 and row >= 2:
				r2.append(0)
			elif col <= 1:
				r2.append(1)
			elif col == 2:
				r2.append(2)
			else:
				r2.append(3)
	# Verify topology: region 0 present (yes), regions 1,2,3 present (yes)
	# Region 0 cells: (0,0),(0,1),(3,2),(3,3) — two disconnected parts
	var sol: Array = [1, 3, 0, 2]  # some valid crown assignment
	var d := {
		"size": sz,
		"tier": 0,
		"regions": r2,
		"solution": sol,
		"cells": [],
		"is_completed": false,
	}
	for i in range(sz * sz):
		(d["cells"] as Array).append(0)
	assert_false(adapter._can_resume_from(d))


func test_connected_regions_accepted() -> void:
	# 4x4 with 4 regions in columns: region i = column i (each col is contiguous → connected)
	var sz := 4
	var regions: Array = []
	for r in range(sz):
		for c in range(sz):
			regions.append(c)
	# Valid no-diagonal-adjacency solution for column regions
	var sol: Array = [0, 2, 1, 3]
	# (0,0)→(2,1):diff=2 ✓, (2,1)→(1,2):diff=1 ✓ wait—adjacent!
	# Use [0, 2, 0, ...] — no, need all unique cols
	# Try [1, 3, 0, 2]: (1,0)→(3,1):diff=2 ✓, (3,1)→(0,2):diff=3 ✓, (0,2)→(2,3):diff=2 ✓
	sol = [1, 3, 0, 2]
	var d := {
		"size": sz,
		"tier": 0,
		"regions": regions,
		"solution": sol,
		"cells": [],
		"is_completed": false,
	}
	for i in range(sz * sz):
		(d["cells"] as Array).append(0)
	assert_true(adapter._can_resume_from(d))


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
