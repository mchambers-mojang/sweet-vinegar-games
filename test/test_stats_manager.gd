extends GutTest

## Unit tests for StatsManager (Sudoku) — recording, averages, streaks, serialization.

const StatsScript := preload("res://scripts/autoload/stats_manager.gd")

var stats: Node


func before_each() -> void:
	stats = Node.new()
	stats.set_script(StatsScript)
	add_child_autofree(stats)
	# Override after _ready to avoid loading real save data
	stats.reset_all()


# --- Recording ---

func test_record_game_started() -> void:
	stats.record_game_started(0)
	assert_eq(stats.games_started[0], 1)
	assert_eq(stats.total_games_played, 1)


func test_record_multiple_starts() -> void:
	stats.record_game_started(0)
	stats.record_game_started(0)
	stats.record_game_started(1)
	assert_eq(stats.games_started[0], 2)
	assert_eq(stats.games_started[1], 1)
	assert_eq(stats.total_games_played, 3)


func test_record_game_completed_tracks_time() -> void:
	stats.record_game_completed(0, 120.0, false, true)
	assert_eq(stats.games_completed[0], 1)
	assert_eq(stats.total_times[0], 120.0)
	assert_eq(stats.best_times[0], 120.0)


func test_record_game_completed_updates_best_time() -> void:
	stats.record_game_completed(0, 200.0, false, true)
	stats.record_game_completed(0, 100.0, false, true)
	assert_eq(stats.best_times[0], 100.0)


func test_record_game_completed_keeps_best_time() -> void:
	stats.record_game_completed(0, 100.0, false, true)
	stats.record_game_completed(0, 200.0, false, true)
	assert_eq(stats.best_times[0], 100.0)


func test_record_abandoned_increments() -> void:
	stats.record_game_abandoned(2)
	assert_eq(stats.games_abandoned[2], 1)


# --- Streaks ---

func test_streak_increments_on_strict_win() -> void:
	stats.record_game_completed(0, 60.0, true, true)
	assert_eq(stats.current_streak, 1)
	stats.record_game_completed(0, 70.0, true, true)
	assert_eq(stats.current_streak, 2)
	assert_eq(stats.best_streak, 2)


func test_streak_resets_on_strict_loss() -> void:
	stats.record_game_completed(0, 60.0, true, true)
	stats.record_game_completed(0, 60.0, true, true)
	stats.record_game_completed(0, 60.0, true, false)
	assert_eq(stats.current_streak, 0)
	assert_eq(stats.best_streak, 2)


func test_streak_resets_on_abandon() -> void:
	stats.record_game_completed(0, 60.0, true, true)
	stats.record_game_abandoned(0)
	assert_eq(stats.current_streak, 0)


func test_non_strict_doesnt_affect_streak() -> void:
	stats.record_game_completed(0, 60.0, false, true)
	assert_eq(stats.current_streak, 0)


# --- Averages and rates ---

func test_average_time_no_games() -> void:
	assert_eq(stats.get_average_time(0), -1.0)


func test_average_time_calculated() -> void:
	stats.record_game_completed(0, 100.0, false, true)
	stats.record_game_completed(0, 200.0, false, true)
	assert_eq(stats.get_average_time(0), 150.0)


func test_completion_rate_no_starts() -> void:
	assert_eq(stats.get_completion_rate(0), 0.0)


func test_completion_rate_calculated() -> void:
	stats.record_game_started(0)
	stats.record_game_started(0)
	stats.record_game_started(0)
	stats.record_game_started(0)
	stats.record_game_completed(0, 60.0, false, true)
	stats.record_game_completed(0, 60.0, false, true)
	# 2 completed out of 4 started = 50%
	assert_eq(stats.get_completion_rate(0), 50.0)


# --- Time history ---

func test_time_history_records() -> void:
	stats.record_game_completed(0, 100.0, false, true)
	stats.record_game_completed(0, 200.0, false, true)
	var history: Array = stats.get_time_history(0)
	assert_eq(history.size(), 2)
	assert_eq(history[0], 100.0)
	assert_eq(history[1], 200.0)


func test_time_history_limited_to_30() -> void:
	for i in 35:
		stats.record_game_completed(0, float(i), false, true)
	var history: Array = stats.get_time_history(0)
	assert_eq(history.size(), 30)
	# Should keep last 30
	assert_eq(history[0], 5.0)


func test_time_history_returns_copy() -> void:
	stats.record_game_completed(0, 100.0, false, true)
	var h1: Array = stats.get_time_history(0)
	h1.append(999.0)
	var h2: Array = stats.get_time_history(0)
	assert_eq(h2.size(), 1)


# --- Reset ---

func test_reset_all_clears_everything() -> void:
	stats.record_game_started(0)
	stats.record_game_completed(0, 60.0, true, true)
	stats.reset_all()
	assert_eq(stats.games_started[0], 0)
	assert_eq(stats.games_completed[0], 0)
	assert_eq(stats.total_games_played, 0)
	assert_eq(stats.current_streak, 0)
	assert_eq(stats.best_streak, 0)
	assert_eq(stats.best_times[0], -1.0)
