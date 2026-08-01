extends GutTest

## Unit tests for NumberPathSaveAdapter._can_resume_from validation (fix 3).

var adapter: NumberPathSaveAdapter


func _valid_save() -> Dictionary:
	return {
		"width": 5,
		"height": 5,
		"tier": NumberPathLogic.TIER_EASY,
		"random_seed": 42,
		"checkpoints": [
			{"x": 0, "y": 0, "n": 1},
			{"x": 4, "y": 4, "n": 2},
		],
		"barriers": [],
		"solution_path": _make_path_arr(5, 5),
		"current_path": [{"x": 0, "y": 0}],
		"is_completed": false,
		"hints_used": 0,
		"has_contradiction": false,
		"undo_stack": [],
		"redo_stack": [],
	}


func _make_path_arr(w: int, h: int) -> Array:
	var arr := []
	for r in range(h):
		for c in range(w):
			arr.append({"x": c, "y": r})
	return arr


func before_each() -> void:
	adapter = NumberPathSaveAdapter.new()


func test_valid_save_passes_validation() -> void:
	assert_true(_check_resume(_valid_save()))


func test_invalid_dimensions_rejected() -> void:
	var d := _valid_save()
	d["width"] = 0
	assert_false(_check_resume(d))


func test_negative_dimensions_rejected() -> void:
	var d := _valid_save()
	d["height"] = -3
	assert_false(_check_resume(d))


func test_completed_save_rejected() -> void:
	var d := _valid_save()
	d["is_completed"] = true
	assert_false(_check_resume(d))


func test_invalid_tier_rejected() -> void:
	var d := _valid_save()
	d["tier"] = 99
	assert_false(_check_resume(d))


func test_empty_checkpoints_rejected() -> void:
	var d := _valid_save()
	d["checkpoints"] = []
	assert_false(_check_resume(d))


func test_missing_checkpoints_rejected() -> void:
	var d := _valid_save()
	d.erase("checkpoints")
	assert_false(_check_resume(d))


func test_checkpoint_x_out_of_range_rejected() -> void:
	var d := _valid_save()
	d["checkpoints"] = [{"x": 99, "y": 0, "n": 1}, {"x": 4, "y": 4, "n": 2}]
	assert_false(_check_resume(d))


func test_checkpoint_y_out_of_range_rejected() -> void:
	var d := _valid_save()
	d["checkpoints"] = [{"x": 0, "y": 0, "n": 1}, {"x": 0, "y": 99, "n": 2}]
	assert_false(_check_resume(d))


func test_invalid_checkpoint_n_rejected() -> void:
	var d := _valid_save()
	d["checkpoints"] = [{"x": 0, "y": 0, "n": 0}, {"x": 4, "y": 4, "n": 2}]
	assert_false(_check_resume(d))


func test_invalid_barrier_dir_rejected() -> void:
	var d := _valid_save()
	d["barriers"] = [{"r": 0, "c": 0, "dir": 5}]
	assert_false(_check_resume(d))


func test_barrier_r_out_of_range_rejected() -> void:
	var d := _valid_save()
	d["barriers"] = [{"r": 99, "c": 0, "dir": 0}]
	assert_false(_check_resume(d))


func test_barrier_c_out_of_range_rejected() -> void:
	var d := _valid_save()
	d["barriers"] = [{"r": 0, "c": 99, "dir": 1}]
	assert_false(_check_resume(d))


func test_missing_solution_path_rejected() -> void:
	var d := _valid_save()
	d.erase("solution_path")
	assert_false(_check_resume(d))


func test_wrong_length_solution_path_rejected() -> void:
	var d := _valid_save()
	d["solution_path"] = [{"x": 0, "y": 0}]  # only one cell, should be 25
	assert_false(_check_resume(d))


func test_valid_barriers_accepted() -> void:
	var d := _valid_save()
	d["barriers"] = [
		{"r": 0, "c": 0, "dir": NumberPathLogic.DIR_RIGHT},
		{"r": 1, "c": 1, "dir": NumberPathLogic.DIR_DOWN},
	]
	assert_true(_check_resume(d))


# --- Regression Fix 2: duplicate / non-sequential checkpoints ---

func test_duplicate_checkpoint_coordinates_rejected() -> void:
	var d := _valid_save()
	# Both checkpoints share the same (x,y)
	d["checkpoints"] = [{"x": 0, "y": 0, "n": 1}, {"x": 0, "y": 0, "n": 2}]
	assert_false(_check_resume(d), "Duplicate checkpoint coordinates must be rejected")


func test_non_sequential_checkpoint_n_rejected() -> void:
	var d := _valid_save()
	# n values skip from 1 to 3 — gap in sequence
	d["checkpoints"] = [{"x": 0, "y": 0, "n": 1}, {"x": 4, "y": 4, "n": 3}]
	assert_false(_check_resume(d), "Non-sequential checkpoint n must be rejected")


func test_checkpoint_n_starting_at_zero_rejected() -> void:
	var d := _valid_save()
	d["checkpoints"] = [{"x": 0, "y": 0, "n": 0}, {"x": 4, "y": 4, "n": 1}]
	assert_false(_check_resume(d), "Checkpoint n=0 must be rejected")


func test_checkpoint_n_wrong_order_rejected() -> void:
	var d := _valid_save()
	# n values are swapped: entry 0 has n=2, entry 1 has n=1
	d["checkpoints"] = [{"x": 0, "y": 0, "n": 2}, {"x": 4, "y": 4, "n": 1}]
	assert_false(_check_resume(d), "Checkpoint n not matching sequential position must be rejected")


# --- Regression Fix 2: current_path invariants ---

func test_current_path_not_array_rejected() -> void:
	var d := _valid_save()
	d["current_path"] = "corrupted"
	assert_false(_check_resume(d), "current_path that is not an array must be rejected")


func test_current_path_not_starting_at_cp1_rejected() -> void:
	var d := _valid_save()
	d["current_path"] = [{"x": 1, "y": 0}]  # not at CP1 (0,0)
	assert_false(_check_resume(d), "current_path not starting at CP1 must be rejected")


func test_current_path_with_gap_rejected() -> void:
	var d := _valid_save()
	# (0,0) → (2,0) skips a cell — non-adjacent step
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 2, "y": 0}]
	assert_false(_check_resume(d), "current_path with non-adjacent step must be rejected")


func test_current_path_with_revisit_rejected() -> void:
	var d := _valid_save()
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 0, "y": 0}]
	assert_false(_check_resume(d), "current_path that revisits a cell must be rejected")


func test_current_path_with_barrier_crossing_rejected() -> void:
	var d := _valid_save()
	# Place a barrier on the right edge of (0,0): blocks move (0,0)→(1,0)
	d["barriers"] = [{"r": 0, "c": 0, "dir": NumberPathLogic.DIR_RIGHT}]
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 1, "y": 0}]
	assert_false(_check_resume(d), "current_path crossing a barrier must be rejected")


func test_current_path_with_checkpoint_out_of_order_rejected() -> void:
	# 3-checkpoint save; path visits CP3 before CP2 (only possible via raw inject).
	var d := _valid_save()
	d["width"] = 3
	d["height"] = 2
	d["checkpoints"] = [
		{"x": 0, "y": 0, "n": 1},
		{"x": 2, "y": 0, "n": 2},
		{"x": 1, "y": 1, "n": 3},
	]
	d["solution_path"] = _make_path_arr(3, 2)
	# (0,0)→(0,1)→(1,1) — visits CP3 (1,1) without having visited CP2 (2,0)
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 0, "y": 1}, {"x": 1, "y": 1}]
	assert_false(_check_resume(d), "current_path visiting checkpoint out of order must be rejected")


func test_current_path_valid_accepted() -> void:
	var d := _valid_save()
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 1, "y": 0}]
	assert_true(_check_resume(d), "Valid current_path must be accepted")


func test_empty_current_path_accepted() -> void:
	var d := _valid_save()
	d["current_path"] = []
	assert_true(_check_resume(d), "Empty current_path must be accepted")


# --- Regression Fix 2: undo/redo stack entries ---

func test_undo_stack_not_array_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = "bad"
	assert_false(_check_resume(d), "undo_stack that is not an array must be rejected")


func test_undo_stack_entry_not_dict_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = ["not_a_dict"]
	assert_false(_check_resume(d), "undo_stack entry that is not a dict must be rejected")


func test_undo_stack_snapshot_out_of_bounds_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [{"x": 99, "y": 0}],  # x out of range
	}]
	assert_false(_check_resume(d), "undo_stack snapshot with out-of-bounds cell must be rejected")


func test_redo_stack_snapshot_out_of_bounds_rejected() -> void:
	var d := _valid_save()
	d["redo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 99}],  # y out of range
	}]
	assert_false(_check_resume(d), "redo_stack snapshot with out-of-bounds cell must be rejected")


func test_valid_undo_stack_accepted() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
	}]
	assert_true(_check_resume(d), "Valid undo_stack must be accepted")


# Helper: write data into the adapter's backing store and call can_resume().
func _check_resume(data: Dictionary) -> bool:
	# NumberPathSaveAdapter inherits GameSaveAdapter which reads from a stored file.
	# We test _can_resume_from by calling it directly since it is a protected method
	# accessible via GDScript reflection.
	return adapter.call("_can_resume_from", data)
