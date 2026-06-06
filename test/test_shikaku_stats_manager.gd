extends GutTest

## Unit tests for ShikakuStatsManager — per grid size stats, streaks.

const StatsScript := preload("res://scripts/autoload/shikaku_stats_manager.gd")

var stats: Node


func before_each() -> void:
	stats = Node.new()
	stats.set_script(StatsScript)
	add_child_autofree(stats)
	stats.reset_all()


# --- Recording ---

func test_record_game_started() -> void:
	stats.record_game_started(5)
	assert_eq(stats.games_started[5], 1)
	assert_eq(stats.total_games_played, 1)


func test_record_game_completed() -> void:
	stats.record_game_completed(5, 45.0)
	assert_eq(stats.games_completed[5], 1)
	assert_eq(stats.best_times[5], 45.0)
	assert_eq(stats.total_times[5], 45.0)


func test_record_game_completed_updates_best() -> void:
	stats.record_game_completed(7, 100.0)
	stats.record_game_completed(7, 50.0)
	assert_eq(stats.best_times[7], 50.0)


func test_record_game_completed_keeps_best() -> void:
	stats.record_game_completed(7, 50.0)
	stats.record_game_completed(7, 100.0)
	assert_eq(stats.best_times[7], 50.0)


func test_record_game_abandoned() -> void:
	stats.record_game_abandoned(10)
	assert_eq(stats.games_abandoned[10], 1)


# --- Streaks ---

func test_streak_increments_on_completion() -> void:
	stats.record_game_completed(5, 30.0)
	stats.record_game_completed(7, 60.0)
	assert_eq(stats.current_streak, 2)
	assert_eq(stats.best_streak, 2)


func test_streak_resets_on_abandon() -> void:
	stats.record_game_completed(5, 30.0)
	stats.record_game_abandoned(5)
	assert_eq(stats.current_streak, 0)
	assert_eq(stats.best_streak, 1)


# --- Averages ---

func test_average_time_no_games() -> void:
	assert_eq(stats.get_average_time(5), -1.0)


func test_average_time_calculated() -> void:
	stats.record_game_completed(5, 40.0)
	stats.record_game_completed(5, 60.0)
	assert_eq(stats.get_average_time(5), 50.0)


func test_completion_rate() -> void:
	stats.record_game_started(5)
	stats.record_game_started(5)
	stats.record_game_completed(5, 30.0)
	assert_eq(stats.get_completion_rate(5), 50.0)


# --- Time history ---

func test_time_history_records() -> void:
	stats.record_game_completed(5, 30.0)
	stats.record_game_completed(5, 45.0)
	var history: Array = stats.get_time_history(5)
	assert_eq(history.size(), 2)


func test_time_history_limited() -> void:
	for i in 35:
		stats.record_game_completed(5, float(i))
	var history: Array = stats.get_time_history(5)
	assert_eq(history.size(), 30)


func test_time_history_per_size() -> void:
	stats.record_game_completed(5, 30.0)
	stats.record_game_completed(10, 60.0)
	assert_eq(stats.get_time_history(5).size(), 1)
	assert_eq(stats.get_time_history(10).size(), 1)


# --- Reset ---

func test_reset_all() -> void:
	stats.record_game_started(5)
	stats.record_game_completed(5, 30.0)
	stats.reset_all()
	assert_eq(stats.games_started[5], 0)
	assert_eq(stats.games_completed[5], 0)
	assert_eq(stats.total_games_played, 0)
	assert_eq(stats.current_streak, 0)
	assert_eq(stats.best_times[5], -1.0)
