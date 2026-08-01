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


# Helper: write data into the adapter's backing store and call can_resume().
func _check_resume(data: Dictionary) -> bool:
	# NumberPathSaveAdapter inherits GameSaveAdapter which reads from a stored file.
	# We test _can_resume_from by calling it directly since it is a protected method
	# accessible via GDScript reflection.
	return adapter.call("_can_resume_from", data)
