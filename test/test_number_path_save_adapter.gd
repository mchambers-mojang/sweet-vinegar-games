extends GutTest

## Unit tests for NumberPathSaveAdapter._can_resume_from validation.

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
		"solution_path": _make_snake_path_arr(5, 5),
		"current_path": [{"x": 0, "y": 0}],
		"is_completed": false,
		"hints_used": 0,
		"has_contradiction": false,
		"undo_stack": [],
		"redo_stack": [],
	}


## Build a boustrophedon (snake) path that covers all w*h cells.
## Row 0 goes left→right, row 1 right→left, alternating.
## For a 5×5 grid: starts at (0,0) and ends at (4,4).
func _make_snake_path_arr(w: int, h: int) -> Array:
	var arr := []
	for r in range(h):
		if r % 2 == 0:
			for c in range(w):
				arr.append({"x": c, "y": r})
		else:
			for c in range(w - 1, -1, -1):
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
	# DIR_DOWN at (r=0,c=0) blocks (0,0)↔(0,1); snake path doesn't cross it.
	# DIR_DOWN at (r=1,c=1) blocks (1,1)↔(1,2); snake path doesn't cross it.
	d["barriers"] = [
		{"r": 0, "c": 0, "dir": NumberPathLogic.DIR_DOWN},
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
	# Place a DIR_DOWN barrier at (r=0,c=0): blocks move (0,0)↔(0,1).
	# The snake solution path does not cross this edge (it goes right from (0,0)).
	d["barriers"] = [{"r": 0, "c": 0, "dir": NumberPathLogic.DIR_DOWN}]
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 0, "y": 1}]
	assert_false(_check_resume(d), "current_path crossing a barrier must be rejected")


func test_current_path_with_checkpoint_out_of_order_rejected() -> void:
	# 3-checkpoint 3×2 save; current_path visits CP3 before CP2 (raw inject).
	# Snake path for 3×2: (0,0)→(1,0)→(2,0)→(2,1)→(1,1)→(0,1)
	# Checkpoints: CP1=(0,0), CP2=(2,0), CP3=(0,1) all appear in snake order.
	var d := _valid_save()
	d["width"] = 3
	d["height"] = 2
	d["checkpoints"] = [
		{"x": 0, "y": 0, "n": 1},
		{"x": 2, "y": 0, "n": 2},
		{"x": 0, "y": 1, "n": 3},
	]
	d["solution_path"] = _make_snake_path_arr(3, 2)
	# (0,0)→(0,1) is adjacent, but (0,1)=CP3 must not be visited before CP2=(2,0)
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 0, "y": 1}]
	assert_false(_check_resume(d), "current_path visiting checkpoint out of order must be rejected")


func test_current_path_valid_accepted() -> void:
	var d := _valid_save()
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 1, "y": 0}]
	assert_true(_check_resume(d), "Valid current_path must be accepted")


func test_empty_current_path_rejected() -> void:
	var d := _valid_save()
	d["current_path"] = []
	assert_false(_check_resume(d), "Empty current_path must be rejected — game always starts at CP1")


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
	# current_path must match the undo stack's final post_snapshot
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 1, "y": 0}]
	d["undo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
	}]
	assert_true(_check_resume(d), "Valid undo_stack must be accepted")


# --- Barrier edge validation ---

func test_dir_right_barrier_at_last_column_rejected() -> void:
	var d := _valid_save()
	# w=5, last column = 4; DIR_RIGHT there has no cell to the right
	d["barriers"] = [{"r": 0, "c": 4, "dir": NumberPathLogic.DIR_RIGHT}]
	assert_false(_check_resume(d), "DIR_RIGHT barrier at last column must be rejected")


func test_dir_down_barrier_at_last_row_rejected() -> void:
	var d := _valid_save()
	# h=5, last row = 4; DIR_DOWN there has no cell below
	d["barriers"] = [{"r": 4, "c": 0, "dir": NumberPathLogic.DIR_DOWN}]
	assert_false(_check_resume(d), "DIR_DOWN barrier at last row must be rejected")


func test_dir_down_barrier_not_at_last_row_accepted() -> void:
	var d := _valid_save()
	# DIR_DOWN at (r=0,c=1) is structurally valid: r=0 < h-1=4.
	# It blocks (1,0)↔(1,1); the snake path does not cross that edge consecutively.
	d["barriers"] = [{"r": 0, "c": 1, "dir": NumberPathLogic.DIR_DOWN}]
	assert_true(_check_resume(d), "DIR_DOWN barrier not at last row must be accepted")


# --- missing current_path ---

func test_missing_current_path_rejected() -> void:
	var d := _valid_save()
	d.erase("current_path")
	assert_false(_check_resume(d), "Missing current_path must be rejected")


# --- solution_path full validation ---

func test_solution_path_with_non_dict_entry_rejected() -> void:
	var d := _valid_save()
	var sp := _make_snake_path_arr(5, 5)
	sp[3] = "bad"
	d["solution_path"] = sp
	assert_false(_check_resume(d), "solution_path with a non-dict entry must be rejected")


func test_solution_path_with_out_of_bounds_cell_rejected() -> void:
	var d := _valid_save()
	var sp := _make_snake_path_arr(5, 5)
	sp[1] = {"x": 99, "y": 0}
	d["solution_path"] = sp
	assert_false(_check_resume(d), "solution_path with an out-of-bounds cell must be rejected")


func test_solution_path_not_starting_at_cp1_rejected() -> void:
	var d := _valid_save()
	var sp := _make_snake_path_arr(5, 5)
	sp[0] = {"x": 1, "y": 0}  # should be (0,0)=CP1
	d["solution_path"] = sp
	assert_false(_check_resume(d), "solution_path not starting at CP1 must be rejected")


func test_solution_path_with_non_adjacent_step_rejected() -> void:
	var d := _valid_save()
	# Swap two middle entries so consecutive cells are no longer adjacent
	var sp := _make_snake_path_arr(5, 5)
	var tmp = sp[5]
	sp[5] = sp[10]
	sp[10] = tmp
	d["solution_path"] = sp
	assert_false(_check_resume(d), "solution_path with a non-adjacent step must be rejected")


func test_solution_path_with_revisit_rejected() -> void:
	var d := _valid_save()
	# Duplicate cell: replace entry 2 with a copy of entry 1
	var sp := _make_snake_path_arr(5, 5)
	sp[2] = sp[1].duplicate()
	d["solution_path"] = sp
	assert_false(_check_resume(d), "solution_path with a revisited cell must be rejected")


# --- history stack action / transition validation ---

func test_undo_stack_invalid_action_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{
		"action": "unknown_op",
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
	}]
	assert_false(_check_resume(d), "undo_stack entry with unknown action must be rejected")


func test_undo_stack_missing_action_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
	}]
	assert_false(_check_resume(d), "undo_stack entry without action must be rejected")


func test_undo_stack_missing_pre_snapshot_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{
		"action": "extend",
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
	}]
	assert_false(_check_resume(d), "undo_stack entry missing pre_snapshot must be rejected")


func test_undo_stack_missing_post_snapshot_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}],
	}]
	assert_false(_check_resume(d), "undo_stack entry missing post_snapshot must be rejected")


func test_undo_stack_empty_pre_snapshot_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [],
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
	}]
	assert_false(_check_resume(d), "undo_stack entry with empty pre_snapshot must be rejected")


func test_undo_stack_empty_post_snapshot_rejected() -> void:
	var d := _valid_save()
	d["undo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [],
	}]
	assert_false(_check_resume(d), "undo_stack entry with empty post_snapshot must be rejected")


func test_undo_stack_extend_wrong_size_transition_rejected() -> void:
	var d := _valid_save()
	# "extend" requires post.size() == pre.size() + 1; here they're the same size
	d["undo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 0}],
	}]
	assert_false(_check_resume(d), "extend transition with same-size snapshots must be rejected")


func test_undo_stack_truncate_wrong_size_transition_rejected() -> void:
	var d := _valid_save()
	# "truncate" requires post.size() < pre.size(); here post is larger
	d["undo_stack"] = [{
		"action": "truncate",
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
	}]
	assert_false(_check_resume(d), "truncate transition where post > pre must be rejected")


func test_undo_stack_extend_prefix_mismatch_rejected() -> void:
	var d := _valid_save()
	# "extend" requires pre to be a prefix of post; here post[0] differs from pre[0]
	d["undo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [{"x": 1, "y": 0}, {"x": 2, "y": 0}],
	}]
	assert_false(_check_resume(d), "extend transition where pre is not a prefix of post must be rejected")


func test_valid_extend_transition_accepted() -> void:
	var d := _valid_save()
	# current_path must match the undo stack's final post_snapshot
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 1, "y": 0}]
	d["undo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
	}]
	assert_true(_check_resume(d), "Valid extend transition must be accepted")


func test_valid_truncate_transition_accepted() -> void:
	var d := _valid_save()
	# current_path must match the undo stack's final post_snapshot after the truncate
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 1, "y": 0}]
	# Truncation: pre has 3 cells, post has 2 (removed the last)
	d["undo_stack"] = [{
		"action": "truncate",
		"pre_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
	}]
	assert_true(_check_resume(d), "Valid truncate transition must be accepted")


# --- Regression: history stack chaining ---

func test_undo_stack_final_post_not_current_path_rejected() -> void:
	var d := _valid_save()
	# current_path stays at [CP1] = (0,0); post_snapshot is (0,0)→(1,0) — mismatch
	d["undo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
	}]
	assert_false(_check_resume(d), "undo final post != current_path must be rejected")


func test_redo_stack_final_pre_not_current_path_rejected() -> void:
	var d := _valid_save()
	# current_path is (0,0); the redo entry's pre_snapshot is (0,0)→(1,0) — mismatch
	d["redo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}],
	}]
	assert_false(_check_resume(d), "redo final pre != current_path must be rejected")


func test_undo_stack_consecutive_not_chained_rejected() -> void:
	var d := _valid_save()
	# Entry 0: extend (0,0)→(0,0),(1,0) — individually valid
	# Entry 1: extend (0,0),(1,0),(2,0)→(0,0),(1,0),(2,0),(3,0) — individually valid
	# Gap: entry[0].post=(0,0),(1,0) != entry[1].pre=(0,0),(1,0),(2,0)
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}, {"x": 3, "y": 0}]
	d["undo_stack"] = [
		{
			"action": "extend",
			"pre_snapshot": [{"x": 0, "y": 0}],
			"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
		},
		{
			"action": "extend",
			"pre_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}],
			"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}, {"x": 3, "y": 0}],
		},
	]
	assert_false(_check_resume(d), "undo consecutive entries not chained must be rejected")


func test_redo_stack_consecutive_not_chained_rejected() -> void:
	var d := _valid_save()
	# redo[0] = action3: pre=(0,0)→(1,0)→(2,0), post=(0,0)→(1,0)→(2,0)→(3,0)
	# redo[1] = action2: pre=(0,0)→(1,0), post=(0,0)→(1,0)→(2,0)
	# Chaining requires redo[1].post == redo[0].pre. Here redo[1].post=(0,0)→(1,0)→(2,0) == redo[0].pre ✓
	# To break it: change redo[1].post to something that doesn't match redo[0].pre
	# current_path must match redo[1].pre = (0,0)→(1,0)
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 1, "y": 0}]
	d["redo_stack"] = [
		{
			"action": "extend",
			"pre_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}],
			"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}, {"x": 3, "y": 0}],
		},
		{
			"action": "extend",
			"pre_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
			# post should be (0,0)→(1,0)→(2,0) to match redo[0].pre, but we set a mismatch:
			"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 1, "y": 1}],
		},
	]
	assert_false(_check_resume(d), "redo consecutive entries not chained must be rejected")


func test_valid_multi_entry_undo_chain_accepted() -> void:
	# Two undo entries properly chained; current_path == last post_snapshot.
	var d := _valid_save()
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}]
	d["undo_stack"] = [
		{
			"action": "extend",
			"pre_snapshot": [{"x": 0, "y": 0}],
			"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
		},
		{
			"action": "extend",
			"pre_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
			"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}],
		},
	]
	assert_true(_check_resume(d), "Valid multi-entry chained undo_stack must be accepted")


func test_valid_multi_entry_redo_chain_accepted() -> void:
	# Two redo entries properly chained; current_path == last entry's pre_snapshot.
	# Sequence: action1 (CP1→A), action2 (CP1,A→CP1,A,B) — both undone.
	# redo[0] = action1: pre=[CP1], post=[CP1,A]
	# redo[1] = action2: pre=[CP1,A], post=[CP1,A,B]
	# Chaining: redo[1].post=[CP1,A,B] BUT should == redo[0].pre=[CP1] — that's wrong.
	# Correct ordering: redo[0]=action2 (last undone first in redo), redo[1]=action1 (first undone)
	# Wait: undo order is action2 then action1 (LIFO), so redo is pushed [action2, action1].
	# redo.pop_back() → action1 is applied first. So redo=[action2, action1].
	# redo[1]=action1: pre=[CP1], post=[CP1,A]. redo[0]=action2: pre=[CP1,A], post=[CP1,A,B].
	# Chaining: redo[1].post=[CP1,A] == redo[0].pre=[CP1,A] ✓
	# current_path == redo.last().pre = redo[1].pre = [CP1] ✓
	var d := _valid_save()
	d["current_path"] = [{"x": 0, "y": 0}]  # CP1 only — everything undone
	d["redo_stack"] = [
		{
			"action": "extend",
			"pre_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
			"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}],
		},
		{
			"action": "extend",
			"pre_snapshot": [{"x": 0, "y": 0}],
			"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
		},
	]
	assert_true(_check_resume(d), "Valid multi-entry chained redo_stack must be accepted")


func test_valid_undo_and_redo_both_chained_accepted() -> void:
	# Partial undo: one action done (in undo), one undone (in redo).
	# current_path = action1.post = action2.pre
	var d := _valid_save()
	d["current_path"] = [{"x": 0, "y": 0}, {"x": 1, "y": 0}]
	d["undo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
	}]
	d["redo_stack"] = [{
		"action": "extend",
		"pre_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
		"post_snapshot": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 2, "y": 0}],
	}]
	assert_true(_check_resume(d), "Undo and redo stacks both chained to current_path must be accepted")


# Helper: write data into the adapter's backing store and call can_resume().
func _check_resume(data: Dictionary) -> bool:
	# NumberPathSaveAdapter inherits GameSaveAdapter which reads from a stored file.
	# We test _can_resume_from by calling it directly since it is a protected method
	# accessible via GDScript reflection.
	return adapter.call("_can_resume_from", data)
