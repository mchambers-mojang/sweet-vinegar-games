extends GutTest

## Unit tests for BlockudokuStatsManager — scoring, averages, history limits.

const StatsScript := preload("res://scripts/autoload/blockudoku_stats_manager.gd")

var stats: Node


func before_each() -> void:
	stats = Node.new()
	stats.set_script(StatsScript)
	add_child_autofree(stats)
	stats.reset_all()


# --- Recording ---

func test_record_game_started() -> void:
	stats.record_game_started()
	assert_eq(stats.games_played, 1)


func test_record_game_over_updates_high_score() -> void:
	stats.record_game_over(500, 10)
	assert_eq(stats.high_score, 500)
	assert_eq(stats.total_score, 500)
	assert_eq(stats.total_turns, 10)


func test_record_game_over_only_updates_if_higher() -> void:
	stats.record_game_over(500, 10)
	stats.record_game_over(300, 8)
	assert_eq(stats.high_score, 500)


func test_record_game_over_updates_best_turns() -> void:
	stats.record_game_over(100, 20)
	stats.record_game_over(200, 30)
	assert_eq(stats.best_turns, 30)


func test_record_clears() -> void:
	stats.record_clears(3)
	stats.record_clears(2)
	assert_eq(stats.total_clears, 5)


func test_record_high_score_candidate_true_if_new() -> void:
	stats.record_game_over(100, 5)
	assert_true(stats.record_high_score_candidate(200))
	assert_eq(stats.high_score, 200)


func test_record_high_score_candidate_false_if_not() -> void:
	stats.record_game_over(100, 5)
	assert_false(stats.record_high_score_candidate(50))
	assert_eq(stats.high_score, 100)


# --- Averages ---

func test_average_turns_no_games() -> void:
	assert_eq(stats.get_average_turns(), 0.0)


func test_average_turns() -> void:
	stats.record_game_started()
	stats.record_game_started()
	stats.record_game_over(100, 20)
	stats.record_game_over(200, 30)
	assert_eq(stats.get_average_turns(), 25.0)


func test_average_score_no_history() -> void:
	assert_eq(stats.get_average_score(), 0.0)


func test_average_score_calculated() -> void:
	stats.record_game_over(100, 5)
	stats.record_game_over(200, 5)
	stats.record_game_over(300, 5)
	assert_eq(stats.get_average_score(), 200.0)


func test_get_best_score() -> void:
	stats.record_game_over(100, 5)
	stats.record_game_over(500, 5)
	stats.record_game_over(200, 5)
	assert_eq(stats.get_best_score(), 500)


# --- Score history ---

func test_score_history_records_games() -> void:
	stats.record_game_over(100, 5)
	stats.record_game_over(200, 5)
	var history: Array = stats.get_score_history()
	assert_eq(history.size(), 2)
	assert_eq(history[0], 100)
	assert_eq(history[1], 200)


func test_score_history_limited_to_30() -> void:
	for i in 35:
		stats.record_game_over(i * 10, 5)
	var history: Array = stats.get_score_history()
	assert_eq(history.size(), 30)


func test_score_history_per_mode() -> void:
	stats.record_game_over(100, 5, "classic")
	stats.record_game_over(200, 5, "zen")
	assert_eq(stats.get_score_history("classic").size(), 1)
	assert_eq(stats.get_score_history("zen").size(), 1)


# --- Reset ---

func test_reset_all() -> void:
	stats.record_game_started()
	stats.record_game_over(500, 20)
	stats.record_clears(5)
	stats.reset_all()
	assert_eq(stats.games_played, 0)
	assert_eq(stats.high_score, 0)
	assert_eq(stats.total_score, 0)
	assert_eq(stats.total_clears, 0)
	assert_eq(stats.get_score_history().size(), 0)
