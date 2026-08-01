extends GutTest

## Regression tests for CrownGridSaveAdapter validation (fix 6).

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _valid_save(size: int = 6) -> Dictionary:
	var regions: Array = []
	for i in range(size * size):
		regions.append(i % size)
	var solution: Array = []
	for i in range(size):
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
