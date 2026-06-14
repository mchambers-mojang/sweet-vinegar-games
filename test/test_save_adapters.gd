extends GutTest

## Tests for the GameSaveAdapter contract, per-game adapters, and the deepened
## GameSaveManager (version tracking, migration, corruption recovery).

var save_mgr: Node


func before_each() -> void:
	save_mgr = load("res://scripts/autoload/game_save_manager.gd").new()
	add_child_autofree(save_mgr)
	save_mgr.clear_all()


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
	var f := FileAccess.open(GameSaveManager.SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string("THIS IS NOT A VALID CONFIG FILE !!!")
		f.close()
	var result: Dictionary = save_mgr.load_game("any_game")
	assert_eq(result, {}, "Corrupted file must return empty dict")


func test_has_saved_game_false_for_corrupted_file() -> void:
	var f := FileAccess.open(GameSaveManager.SAVE_PATH, FileAccess.WRITE)
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
	adapter.save({"width": 10, "height": 10, "is_completed": false})
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


func test_shikaku_adapter_get_grid_width() -> void:
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 12, "height": 12})
	assert_eq(adapter.get_grid_width(), 12)


func test_shikaku_adapter_get_grid_width_default_when_no_save() -> void:
	var adapter := ShikakuSaveAdapter.new()
	assert_eq(adapter.get_grid_width(), 10)


# ---------------------------------------------------------------------------
# GameSaveAdapter — restore_if_resumable (avoids double load)
# ---------------------------------------------------------------------------

func test_restore_if_resumable_returns_data_when_valid() -> void:
	var adapter := ShikakuSaveAdapter.new()
	adapter.save({"width": 10, "height": 10, "is_completed": false})
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
	config.load(GameSaveManager.SAVE_PATH)
	if config.has_section(game_id):
		config.erase_section(game_id)
	for key in data.keys():
		config.set_value(game_id, str(key), data[key])
	# Deliberately do NOT write VERSION_KEY — this simulates a legacy save
	config.save(GameSaveManager.SAVE_PATH)
