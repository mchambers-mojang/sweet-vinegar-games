extends GutTest

## Tests for the unified GameSaveManager and GameStatsManager

const _SAVES_PATH := "user://game_saves.cfg"
const _STATS_PATH := "user://game_stats.cfg"
const _SAVES_BACKUP := "user://game_saves.cfg.bak"
const _STATS_BACKUP := "user://game_stats.cfg.bak"

var save_mgr: Node
var stats_mgr: Node


func before_all() -> void:
	_backup_file(_SAVES_PATH, _SAVES_BACKUP)
	_backup_file(_STATS_PATH, _STATS_BACKUP)


func after_all() -> void:
	_restore_file(_SAVES_PATH, _SAVES_BACKUP)
	_restore_file(_STATS_PATH, _STATS_BACKUP)
	GameStatsManager._load_all()


func before_each() -> void:
	save_mgr = load("res://scripts/autoload/game_save_manager.gd").new()
	stats_mgr = load("res://scripts/autoload/game_stats_manager.gd").new()
	add_child_autofree(save_mgr)
	add_child_autofree(stats_mgr)
	# Clean slate for each test
	save_mgr.clear_all()
	stats_mgr.clear_all()


func _backup_file(path: String, backup_path: String) -> void:
	if FileAccess.file_exists(path):
		var content := FileAccess.get_file_as_bytes(path)
		var f := FileAccess.open(backup_path, FileAccess.WRITE)
		if f:
			f.store_buffer(content)
			f.close()


func _restore_file(path: String, backup_path: String) -> void:
	if FileAccess.file_exists(backup_path):
		var content := FileAccess.get_file_as_bytes(backup_path)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_buffer(content)
			f.close()
		DirAccess.remove_absolute(backup_path)
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# --- GameSaveManager Tests ---

func test_has_saved_game_returns_false_when_empty() -> void:
	assert_false(save_mgr.has_saved_game("test_game"))


func test_save_and_load_round_trip() -> void:
	var data := {"score": 42, "name": "test", "nested": {"key": "value"}}
	save_mgr.save_game("test_game", data)
	assert_true(save_mgr.has_saved_game("test_game"))
	var loaded: Dictionary = save_mgr.load_game("test_game")
	assert_eq(loaded["score"], 42)
	assert_eq(loaded["name"], "test")
	assert_eq(loaded["nested"], {"key": "value"})


func test_save_multiple_games_independently() -> void:
	save_mgr.save_game("game_a", {"val": 1})
	save_mgr.save_game("game_b", {"val": 2})
	assert_eq(save_mgr.load_game("game_a")["val"], 1)
	assert_eq(save_mgr.load_game("game_b")["val"], 2)


func test_clear_save_removes_only_target() -> void:
	save_mgr.save_game("game_a", {"val": 1})
	save_mgr.save_game("game_b", {"val": 2})
	save_mgr.clear_save("game_a")
	assert_false(save_mgr.has_saved_game("game_a"))
	assert_true(save_mgr.has_saved_game("game_b"))


func test_load_nonexistent_returns_empty() -> void:
	var loaded: Dictionary = save_mgr.load_game("nonexistent")
	assert_eq(loaded, {})


func test_save_overwrites_previous() -> void:
	save_mgr.save_game("game_a", {"old_key": "old_val"})
	save_mgr.save_game("game_a", {"new_key": "new_val"})
	var loaded: Dictionary = save_mgr.load_game("game_a")
	assert_false(loaded.has("old_key"))
	assert_eq(loaded["new_key"], "new_val")


# --- GameStatsManager Tests ---

func test_record_and_get_history() -> void:
	stats_mgr.record("sudoku", {"time": 120.5, "difficulty": 2})
	stats_mgr.record("sudoku", {"time": 95.0, "difficulty": 2})
	var history: Array = stats_mgr.get_history("sudoku")
	assert_eq(history.size(), 2)
	assert_eq(history[0]["time"], 120.5)
	assert_eq(history[1]["time"], 95.0)


func test_history_capped_at_limit() -> void:
	for i in range(35):
		stats_mgr.record("test_game", {"index": i})
	var history: Array = stats_mgr.get_history("test_game")
	assert_eq(history.size(), 30)
	# Should have last 30 entries (indices 5-34)
	assert_eq(history[0]["index"], 5)
	assert_eq(history[29]["index"], 34)


func test_increment_counter() -> void:
	stats_mgr.increment_counter("game_a", "plays")
	stats_mgr.increment_counter("game_a", "plays")
	stats_mgr.increment_counter("game_a", "plays", 3)
	assert_eq(stats_mgr.get_counter("game_a", "plays"), 5)


func test_set_counter() -> void:
	stats_mgr.set_counter("game_a", "best_streak", 7)
	assert_eq(stats_mgr.get_counter("game_a", "best_streak"), 7)
	stats_mgr.set_counter("game_a", "best_streak", 12)
	assert_eq(stats_mgr.get_counter("game_a", "best_streak"), 12)


func test_get_counter_default_zero() -> void:
	assert_eq(stats_mgr.get_counter("nonexistent", "something"), 0)


func test_get_counters_returns_all() -> void:
	stats_mgr.increment_counter("game_a", "wins", 3)
	stats_mgr.increment_counter("game_a", "losses", 1)
	var counters: Dictionary = stats_mgr.get_counters("game_a")
	assert_eq(counters["wins"], 3)
	assert_eq(counters["losses"], 1)


func test_clear_removes_game_data() -> void:
	stats_mgr.record("game_a", {"score": 100})
	stats_mgr.increment_counter("game_a", "plays")
	stats_mgr.clear("game_a")
	assert_eq(stats_mgr.get_history("game_a"), [])
	assert_eq(stats_mgr.get_counter("game_a", "plays"), 0)


func test_games_are_independent() -> void:
	stats_mgr.record("game_a", {"val": 1})
	stats_mgr.record("game_b", {"val": 2})
	stats_mgr.increment_counter("game_a", "x", 5)
	assert_eq(stats_mgr.get_history("game_a").size(), 1)
	assert_eq(stats_mgr.get_history("game_b").size(), 1)
	assert_eq(stats_mgr.get_counter("game_b", "x"), 0)


func test_clear_all_removes_everything() -> void:
	stats_mgr.record("game_a", {"val": 1})
	stats_mgr.record("game_b", {"val": 2})
	stats_mgr.clear_all()
	assert_eq(stats_mgr.get_history("game_a"), [])
	assert_eq(stats_mgr.get_history("game_b"), [])
