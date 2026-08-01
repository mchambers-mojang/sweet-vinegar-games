extends GutTest

## Tests for the GameSaveAdapter contract, per-game adapters, and the deepened
## GameSaveManager (version tracking, migration, corruption recovery).

const _TEST_SAVES_PATH := "user://test_save_adapters_mgr.cfg"
const _TEST_ADAPTER_PATH := "user://test_save_adapters_gsa.cfg"

var save_mgr: Node
var _original_gsm_path: String


func after_all() -> void:
	if FileAccess.file_exists(_TEST_SAVES_PATH):
		DirAccess.remove_absolute(_TEST_SAVES_PATH)
	if FileAccess.file_exists(_TEST_ADAPTER_PATH):
		DirAccess.remove_absolute(_TEST_ADAPTER_PATH)


func before_each() -> void:
	save_mgr = load("res://scripts/autoload/game_save_manager.gd").new()
	save_mgr.save_path = _TEST_SAVES_PATH
	add_child_autofree(save_mgr)
	save_mgr.clear_all()
	# Redirect the autoload singleton to an isolated test file so adapter
	# tests never touch the real user save data.
	_original_gsm_path = GameSaveManager.save_path
	GameSaveManager.save_path = _TEST_ADAPTER_PATH
	GameSaveManager.clear_all()


func after_each() -> void:
	GameSaveManager.save_path = _original_gsm_path


# ---------------------------------------------------------------------------
# GameSaveManager — version tracking
# ---------------------------------------------------------------------------

func test_save_stamps_version_not_returned_to_caller() -> void:
	save_mgr.save_game("vtest", {"val": 42})
	var loaded: Dictionary = save_mgr.load_game("vtest")
	# Internal version key must be stripped before returning data
	assert_false(loaded.has(GameSaveManager.VERSION_KEY), "VERSION_KEY should not appear in loaded data")
	assert_eq(loaded["val"], 42)


func test_load_returns_correct_data_with_versioned_save() -> void:
	save_mgr.save_game("vtest", {"x": 1, "y": "hello"})
	var loaded: Dictionary = save_mgr.load_game("vtest")
	assert_eq(loaded["x"], 1)
	assert_eq(loaded["y"], "hello")


# ---------------------------------------------------------------------------
# GameSaveManager — migration support
# ---------------------------------------------------------------------------

func test_migration_callable_invoked_for_v0_save() -> void:
	# Arrays are reference types — safe to mutate inside a lambda
	var tracker: Array = [false]
	save_mgr.register_migrator("mig_test", func(data: Dictionary, _v: int) -> Dictionary:
		tracker[0] = true
		return data
	)
	# Write a legacy (v0) save directly — no VERSION_KEY present
	_write_v0_save("mig_test", {"key": "val"})
	save_mgr.load_game("mig_test")
	assert_true(tracker[0], "Migration callable must be invoked for a v0 save")


func test_migration_can_transform_data() -> void:
	save_mgr.register_migrator("mig_transform", func(data: Dictionary, _v: int) -> Dictionary:
		# Rename "old_field" → "new_field" as part of migration
		var result: Dictionary = data.duplicate()
		if result.has("old_field"):
			result["new_field"] = result["old_field"]
			result.erase("old_field")
		return result
	)
	_write_v0_save("mig_transform", {"old_field": 99})
	var loaded: Dictionary = save_mgr.load_game("mig_transform")
	assert_false(loaded.has("old_field"), "old_field should have been renamed")
	assert_eq(loaded["new_field"], 99)


func test_migration_not_called_for_current_version_save() -> void:
	# Arrays are reference types — safe to mutate inside a lambda
	var counter: Array = [0]
	save_mgr.register_migrator("mig_skip", func(data: Dictionary, _v: int) -> Dictionary:
		counter[0] += 1
		return data
	)
	# Save via normal API — this stamps SAVE_VERSION
	save_mgr.save_game("mig_skip", {"k": 1})
	save_mgr.load_game("mig_skip")
	assert_eq(counter[0], 0, "Migration must not be called for a current-version save")


# ---------------------------------------------------------------------------
# GameSaveManager — corruption recovery
# ---------------------------------------------------------------------------

func test_corrupted_file_returns_empty_dict() -> void:
	# Write a corrupt (non-ConfigFile) payload to the save path
	var f := FileAccess.open(save_mgr.save_path, FileAccess.WRITE)
	if f:
		f.store_string("THIS IS NOT A VALID CONFIG FILE !!!")
		f.close()
	var result: Dictionary = save_mgr.load_game("any_game")
	assert_eq(result, {}, "Corrupted file must return empty dict")


func test_has_saved_game_false_for_corrupted_file() -> void:
	var f := FileAccess.open(save_mgr.save_path, FileAccess.WRITE)
	if f:
		f.store_string("GARBAGE")
		f.close()
	assert_false(save_mgr.has_saved_game("any_game"))


# ---------------------------------------------------------------------------
# SudokuSaveAdapter — round-trip
# ---------------------------------------------------------------------------

func test_sudoku_adapter_save_and_restore() -> void:
	var adapter := SudokuSaveAdapter.new()
	var state: Dictionary = {
		"puzzle": _make_array(81, 1),
		"solution": _make_array(81, 5),
		"current_grid": _make_array(81, 0),
		"difficulty": 2,
		"elapsed_time": 75.0,
		"strikes": 0,
		"is_failed": false,
		"hints_used": 1,
	}
	adapter.save(state)
	assert_true(adapter.has_save())
	var restored: Dictionary = adapter.restore()
	assert_eq(restored["difficulty"], 2)
	assert_eq(restored["elapsed_time"], 75.0)
	assert_eq(restored["hints_used"], 1)


func test_sudoku_adapter_clear() -> void:
	var adapter := SudokuSaveAdapter.new()
	adapter.save({"puzzle": _make_array(81, 1), "solution": _make_array(81, 5), "current_grid": _make_array(81, 0)})
	assert_true(adapter.has_save())
	adapter.clear()
	assert_false(adapter.has_save())


func test_sudoku_adapter_can_resume_with_valid_save() -> void:
	var adapter := SudokuSaveAdapter.new()
	adapter.save({"puzzle": _make_array(81, 1), "solution": _make_array(81, 5), "current_grid": _make_array(81, 0)})
	assert_true(adapter.can_resume())


func test_sudoku_adapter_can_resume_false_when_no_save() -> void:
	var adapter := SudokuSaveAdapter.new()
	assert_false(adapter.can_resume())


func test_sudoku_adapter_can_resume_false_for_bad_puzzle_array() -> void:
	var adapter := SudokuSaveAdapter.new()
	# Save a structurally invalid puzzle (wrong size)
	adapter.save({"puzzle": [1, 2, 3], "solution": _make_array(81, 5)})
	assert_false(adapter.can_resume(), "Invalid puzzle array must not be resumable")


func test_sudoku_adapter_get_difficulty() -> void:
	var adapter := SudokuSaveAdapter.new()
	adapter.save({"puzzle": _make_array(81, 1), "solution": _make_array(81, 5), "current_grid": _make_array(81, 0), "difficulty": 3})
	assert_eq(adapter.get_difficulty(), 3)


func test_sudoku_adapter_get_difficulty_default_zero_when_no_save() -> void:
	var adapter := SudokuSaveAdapter.new()
	assert_eq(adapter.get_difficulty(), 0)


# ---------------------------------------------------------------------------
# ShikakuSaveAdapter — round-trip
# ---------------------------------------------------------------------------

func test_shikaku_adapter_save_and_restore() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var state: Dictionary = {
		"width": 10,
		"height": 10,
		"numbers": {"0,0": 2, "5,5": 4},
		"solution": [],
		"placed_rects": [],
		"random_seed": 12345,
		"hints_used": 0,
		"is_completed": false,
		"elapsed_time": 42.5,
	}
	adapter.save(state)
	assert_true(adapter.has_save())
	var restored: Dictionary = adapter.restore()
	assert_eq(restored["width"], 10)
	assert_eq(restored["random_seed"], 12345)
	assert_eq(restored["elapsed_time"], 42.5)


func test_shikaku_adapter_clear() -> void:
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 5, "height": 5})
	assert_true(adapter.has_save())
	adapter.clear()
	assert_false(adapter.has_save())


func test_shikaku_adapter_can_resume_with_valid_save() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors})
	assert_true(adapter.can_resume())


func test_shikaku_adapter_can_resume_false_when_no_save() -> void:
	var adapter := ShikakuSaveAdapter.new()
	assert_false(adapter.can_resume())


func test_shikaku_adapter_can_resume_false_when_completed() -> void:
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 10, "height": 10, "is_completed": true})
	assert_false(adapter.can_resume(), "A completed shikaku game must not be resumable")


func test_shikaku_adapter_can_resume_false_for_bad_dimensions() -> void:
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 0, "height": 0})
	assert_false(adapter.can_resume(), "Zero dimensions must not be resumable")


func test_shikaku_adapter_can_resume_false_for_anchor_out_of_bounds() -> void:
	var adapter := ShikakuSaveAdapter.new()
	# Anchor at (20, 20) is outside 10×10 grid.
	var anchors := {"20,20": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors})
	assert_false(adapter.can_resume(), "Anchor outside grid bounds must not be resumable")


func test_shikaku_adapter_can_resume_false_for_negative_area() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": -1, "shape": ShikakuLogic.SHAPE_ABSENT}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors})
	assert_false(adapter.can_resume(), "Negative area must not be resumable")


func test_shikaku_adapter_can_resume_false_for_invalid_shape_enum() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": 99}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors})
	assert_false(adapter.can_resume(), "Unknown shape enum must not be resumable")


func test_shikaku_adapter_can_resume_false_for_empty_clue_component() -> void:
	var adapter := ShikakuSaveAdapter.new()
	# Anchor with area=0 and shape=ABSENT has no constraint — invalid.
	var anchors := {"3,3": {"area": 0, "shape": ShikakuLogic.SHAPE_ABSENT}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors})
	assert_false(adapter.can_resume(), "Anchor with no clue component must not be resumable")


func test_shikaku_adapter_can_resume_true_for_shape_only_anchor() -> void:
	var adapter := ShikakuSaveAdapter.new()
	# Shape-only anchor (area=0, shape=SQUARE) is valid.
	var anchors := {"2,2": {"area": 0, "shape": ShikakuLogic.SHAPE_SQUARE}}
	adapter.save({"width": 5, "height": 5, "is_completed": false, "anchors": anchors})
	assert_true(adapter.can_resume(), "Shape-only anchor must be resumable")


func test_shikaku_adapter_get_grid_width() -> void:
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 12, "height": 12})
	assert_eq(adapter.get_grid_width(), 12)


func test_shikaku_adapter_get_grid_width_default_when_no_save() -> void:
	var adapter := ShikakuSaveAdapter.new()
	assert_eq(adapter.get_grid_width(), 10)


# Fix 3 — extended save-adapter validation

func test_shikaku_adapter_can_resume_false_for_invalid_mode() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors, "mode": 99})
	assert_false(adapter.can_resume(), "Unknown mode must not be resumable")


func test_shikaku_adapter_can_resume_true_for_shapes_mode() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 0, "shape": ShikakuLogic.SHAPE_SQUARE}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors, "mode": ShikakuLogic.RULE_SET_SHAPES})
	assert_true(adapter.can_resume(), "Shapes mode with valid anchor must be resumable")


func test_shikaku_adapter_can_resume_false_for_invalid_solution_rect_out_of_bounds() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	var bad_solution := [{"x": 8, "y": 8, "w": 5, "h": 5}]  # far outside 10×10
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors, "solution": bad_solution})
	assert_false(adapter.can_resume(), "Solution rect outside grid must not be resumable")


func test_shikaku_adapter_can_resume_false_for_invalid_solution_rect_zero_size() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	var bad_solution := [{"x": 0, "y": 0, "w": 0, "h": 3}]  # zero width
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors, "solution": bad_solution})
	assert_false(adapter.can_resume(), "Solution rect with zero dimension must not be resumable")


func test_shikaku_adapter_can_resume_false_for_invalid_placed_rect() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	var bad_placed := [{"x": -1, "y": 0, "w": 2, "h": 2}]  # negative x
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors, "placed_rects": bad_placed})
	assert_false(adapter.can_resume(), "Placed rect with negative x must not be resumable")


func test_shikaku_adapter_can_resume_false_for_invalid_undo_stack_action() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	var bad_undo := [{"action": "bogus", "rect": {"x": 0, "y": 0, "w": 2, "h": 2}}]
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors, "undo_stack": bad_undo})
	assert_false(adapter.can_resume(), "Unknown action in undo_stack must not be resumable")


func test_shikaku_adapter_can_resume_false_for_undo_stack_rect_out_of_bounds() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	var bad_undo := [{"action": "place", "rect": {"x": 9, "y": 9, "w": 5, "h": 5}}]
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors, "undo_stack": bad_undo})
	assert_false(adapter.can_resume(), "undo_stack rect outside grid must not be resumable")


func test_shikaku_adapter_can_resume_false_for_non_integer_anchor_key() -> void:
	# Coercive-parsing fix: "abc,def" must NOT silently parse to (0,0).
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"abc,def": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors})
	assert_false(adapter.can_resume(), "Non-integer anchor key must not be resumable")


# Fix 2 (extended) — non-array fields and coercive rect parsing

func test_shikaku_adapter_can_resume_false_for_solution_as_non_array() -> void:
	# Fixing the bypass: a non-Array solution value must be rejected outright
	# rather than silently skipped (the old code only ran validation if is Array).
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors,
		"solution": "not_an_array"})
	assert_false(adapter.can_resume(), "Non-Array solution value must not be resumable")


func test_shikaku_adapter_can_resume_false_for_undo_stack_as_non_array() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors,
		"undo_stack": 42})
	assert_false(adapter.can_resume(), "Non-Array undo_stack value must not be resumable")


func test_shikaku_adapter_can_resume_false_for_legacy_numbers_malformed_key() -> void:
	# Key without comma triggers legacy validation path (no valid anchor added by _migrate).
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 10, "height": 10, "is_completed": false,
		"numbers": {"garbage": 4}})
	assert_false(adapter.can_resume(), "Legacy numbers with malformed key must not be resumable")


func test_shikaku_adapter_can_resume_false_for_rect_with_string_coordinate() -> void:
	# Coercive-parsing fix: int("garbage") == 0 in GDScript, so "garbage" x-coordinate
	# must be rejected via the type check rather than silently parsed as x=0.
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	var bad_solution := [{"x": "garbage", "y": 0, "w": 2, "h": 2}]
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors,
		"solution": bad_solution})
	assert_false(adapter.can_resume(), "Rect with string coordinate must not be resumable")


# ---------------------------------------------------------------------------
# Fix 2 (current batch) — strict integer enforcement for anchors and rects
# ---------------------------------------------------------------------------

func test_shikaku_adapter_can_resume_false_for_float_anchor_area() -> void:
	# Coercive-parsing fix: int(4.5) == 4 silently truncates; float must be rejected.
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4.5, "shape": ShikakuLogic.SHAPE_ABSENT}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors})
	assert_false(adapter.can_resume(), "Float anchor area must not be resumable")


func test_shikaku_adapter_can_resume_false_for_string_anchor_area() -> void:
	# int("bad") == 0 would silently produce area=0 → invalid clue component.
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": "bad", "shape": ShikakuLogic.SHAPE_ABSENT}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors})
	assert_false(adapter.can_resume(), "String anchor area must not be resumable")


func test_shikaku_adapter_can_resume_false_for_float_anchor_shape() -> void:
	# int(2.5) == 2 would silently truncate a float shape enum.
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": 2.5}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors})
	assert_false(adapter.can_resume(), "Float anchor shape must not be resumable")


func test_shikaku_adapter_can_resume_false_for_float_rect_coordinate() -> void:
	# int(0.5) == 0 would silently truncate a float coordinate.
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"3,3": {"area": 4, "shape": ShikakuLogic.SHAPE_ABSENT}}
	var bad_solution := [{"x": 0.5, "y": 0, "w": 2, "h": 2}]
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors,
		"solution": bad_solution})
	assert_false(adapter.can_resume(), "Float rectangle coordinate must not be resumable")


func test_shikaku_adapter_can_resume_false_for_legacy_float_value() -> void:
	# Legacy numbers: float values (e.g. 4.5) must be rejected (area must be int).
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 10, "height": 10, "is_completed": false,
		"numbers": {"2,2": 4.5}})
	assert_false(adapter.can_resume(), "Legacy number with float value must not be resumable")


func test_shikaku_adapter_can_resume_false_for_legacy_noninteger_key_after_migrate() -> void:
	# _migrate must skip non-integer-key legacy entries so they don't silently
	# become valid anchors (e.g. "abc,def" → int("abc") == 0 → pos (0,0)).
	var adapter := ShikakuSaveAdapter.new()
	# A legacy save with ONLY a non-integer key produces no valid anchors after
	# migration, so _can_resume_from must return false.
	adapter.save({"width": 10, "height": 10, "is_completed": false,
		"numbers": {"abc,def": 4}})
	assert_false(adapter.can_resume(),
		"Legacy save with only non-integer key must not be resumable after migration")


# ---------------------------------------------------------------------------
# Fix — migration rejects whole save on any invalid entry (Issue 1)
# ---------------------------------------------------------------------------

func test_shikaku_adapter_migration_rejects_whole_save_on_partial_corruption() -> void:
	# _migrate must not silently drop the invalid entry and accept the valid one.
	# A mixed legacy save (one valid + one malformed key) must not be resumable.
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 10, "height": 10, "is_completed": false,
		"numbers": {"0,0": 4, "abc,def": 6}})
	assert_false(adapter.can_resume(),
		"Partial corruption in legacy numbers must cause the whole save to be rejected")


func test_shikaku_adapter_migration_rejects_whole_save_on_float_value() -> void:
	# _migrate must not silently drop the float entry and keep the valid int entry.
	# If any value is non-int the migration must abort (return data unchanged).
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 10, "height": 10, "is_completed": false,
		"numbers": {"0,0": 4, "2,2": 6.5}})
	assert_false(adapter.can_resume(),
		"Float value in legacy numbers must cause the whole save to be rejected")


# ---------------------------------------------------------------------------
# Fix 2 (current batch) — non-Dictionary 'numbers' rejected before typed assignment
# ---------------------------------------------------------------------------

func test_shikaku_adapter_migration_rejects_non_dict_numbers_integer() -> void:
	# 'numbers' as an integer must be rejected before any typed Dictionary
	# assignment, not after — the runtime type-check guard must fire first.
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 10, "height": 10, "is_completed": false, "numbers": 42})
	assert_false(adapter.can_resume(),
		"Non-Dictionary 'numbers' (integer) must cause migration to be rejected")


func test_shikaku_adapter_migration_rejects_non_dict_numbers_string() -> void:
	# 'numbers' as a string (e.g. "not_a_dict") must be rejected with a warning
	# rather than a runtime error from the typed assignment.
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 10, "height": 10, "is_completed": false, "numbers": "not_a_dict"})
	assert_false(adapter.can_resume(),
		"Non-Dictionary 'numbers' (string) must cause migration to be rejected")


func test_shikaku_adapter_migration_rejects_non_dict_numbers_array() -> void:
	# An Array value for 'numbers' must be rejected cleanly before the typed
	# Dictionary assignment, since Array is not a Dictionary subtype.
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 10, "height": 10, "is_completed": false, "numbers": [1, 2, 3]})
	assert_false(adapter.can_resume(),
		"Non-Dictionary 'numbers' (Array) must cause migration to be rejected")


# ---------------------------------------------------------------------------
# GameSaveAdapter — restore_if_resumable (avoids double load)
# ---------------------------------------------------------------------------

func test_restore_if_resumable_returns_data_when_valid() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var anchors := {"5,5": {"area": 10, "shape": 0}}
	adapter.save({"width": 10, "height": 10, "is_completed": false, "anchors": anchors})
	var data: Dictionary = adapter.restore_if_resumable()
	assert_false(data.is_empty(), "restore_if_resumable must return data for a valid save")
	assert_eq(data["width"], 10)


func test_restore_if_resumable_returns_empty_when_no_save() -> void:
	var adapter := ShikakuSaveAdapter.new()
	var data: Dictionary = adapter.restore_if_resumable()
	assert_eq(data, {}, "restore_if_resumable must return {} when there is no save")


func test_restore_if_resumable_returns_empty_when_not_resumable() -> void:
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 10, "height": 10, "is_completed": true})
	var data: Dictionary = adapter.restore_if_resumable()
	assert_eq(data, {}, "restore_if_resumable must return {} when can_resume() is false")


# ---------------------------------------------------------------------------
# BlockudokuSaveAdapter — round-trip
# ---------------------------------------------------------------------------

func test_blockudoku_adapter_save_and_restore() -> void:
	var adapter := BlockudokuSaveAdapter.new()
	var state: Dictionary = {
		"score": 1500,
		"turns": 42,
		"combo_count": 3,
		"elapsed_time": 120.0,
		"board_state": {"grid": [], "colors": []},
		"available_blocks": [[{"x": 0, "y": 0}]],
		"blocks_placed_this_set": 1,
		"random_seed": 99999,
		"rng_state": 12345,
	}
	adapter.save(state)
	assert_true(adapter.has_save())
	var restored: Dictionary = adapter.restore()
	assert_eq(restored["score"], 1500)
	assert_eq(restored["turns"], 42)
	assert_eq(restored["elapsed_time"], 120.0)
	assert_eq(restored["random_seed"], 99999)


func test_blockudoku_adapter_clear() -> void:
	var adapter := BlockudokuSaveAdapter.new()
	adapter.save({"board_state": {}, "available_blocks": []})
	assert_true(adapter.has_save())
	adapter.clear()
	assert_false(adapter.has_save())


func test_blockudoku_adapter_can_resume_with_valid_save() -> void:
	var adapter := BlockudokuSaveAdapter.new()
	adapter.save({"board_state": {"grid": []}, "available_blocks": []})
	assert_true(adapter.can_resume())


func test_blockudoku_adapter_can_resume_false_when_no_save() -> void:
	var adapter := BlockudokuSaveAdapter.new()
	assert_false(adapter.can_resume())


func test_blockudoku_adapter_can_resume_false_missing_board_state() -> void:
	var adapter := BlockudokuSaveAdapter.new()
	adapter.save({"score": 100, "available_blocks": []})
	assert_false(adapter.can_resume(), "Save without board_state must not be resumable")


func test_blockudoku_adapter_can_resume_false_missing_available_blocks() -> void:
	var adapter := BlockudokuSaveAdapter.new()
	adapter.save({"score": 100, "board_state": {"grid": []}})
	assert_false(adapter.can_resume(), "Save without available_blocks must not be resumable")


func test_blockudoku_adapter_get_score() -> void:
	var adapter := BlockudokuSaveAdapter.new()
	adapter.save({"board_state": {}, "available_blocks": [], "score": 2500})
	assert_eq(adapter.get_score(), 2500)


func test_blockudoku_adapter_get_score_default_zero_when_no_save() -> void:
	var adapter := BlockudokuSaveAdapter.new()
	assert_eq(adapter.get_score(), 0)


# ---------------------------------------------------------------------------
# GameSaveAdapter — adapter-level version stamping and migration
# ---------------------------------------------------------------------------

func test_adapter_save_stamps_version_key() -> void:
	var adapter := SudokuSaveAdapter.new()
	adapter.save({"puzzle": _make_array(81, 1), "solution": _make_array(81, 5), "current_grid": _make_array(81, 0)})
	# The version key must not be visible to callers
	var restored: Dictionary = adapter.restore()
	assert_false(restored.has(GameSaveAdapter.VERSION_KEY), "VERSION_KEY must be stripped from restored data")


func test_adapter_migration_applied_for_v0_save() -> void:
	# Write a v0 save (no VERSION_KEY) directly into the adapter's file
	_write_v0_save_to_adapter_path("sudoku", {"puzzle": _make_array(81, 0), "solution": _make_array(81, 5), "current_grid": _make_array(81, 0)})
	var adapter := SudokuSaveAdapter.new()
	# restore() must succeed (migration is a no-op for v1, but the call path runs)
	var data: Dictionary = adapter.restore()
	assert_false(data.is_empty(), "restore() must succeed for a v0 save")
	assert_true(data.has("puzzle"), "puzzle key must survive migration")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a simple Array of n elements all set to value.
func _make_array(n: int, value: int) -> Array:
	var arr: Array = []
	arr.resize(n)
	arr.fill(value)
	return arr


## Write a save directly without a version stamp (simulates a legacy v0 save).
func _write_v0_save(game_id: String, data: Dictionary) -> void:
	var config := ConfigFile.new()
	config.load(save_mgr.save_path)
	if config.has_section(game_id):
		config.erase_section(game_id)
	for key in data.keys():
		config.set_value(game_id, str(key), data[key])
	# Deliberately do NOT write VERSION_KEY — this simulates a legacy save
	config.save(save_mgr.save_path)


## Write a v0 save to the adapter's save path (GameSaveManager.save_path is
## redirected to _TEST_ADAPTER_PATH during tests by before_each(), so this
## writes to the isolated test file rather than the real user save).
func _write_v0_save_to_adapter_path(game_id: String, data: Dictionary) -> void:
	var config := ConfigFile.new()
	config.load(GameSaveManager.save_path)
	if config.has_section(game_id):
		config.erase_section(game_id)
	for key in data.keys():
		config.set_value(game_id, str(key), data[key])
	# Deliberately do NOT write VERSION_KEY — this simulates a legacy save
	config.save(GameSaveManager.save_path)
