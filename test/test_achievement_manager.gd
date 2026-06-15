extends GutTest

const AchievementScript := preload("res://scripts/autoload/achievement_engine.gd")
const _TEST_ACHIEVEMENTS_PATH := "user://test_achievements.cfg"
const _TEST_GAME_STATS_PATH := "user://test_game_stats.cfg"

var achievements: Node
var _original_stats_path: String


func before_all() -> void:
	_original_stats_path = GameStatsManager.save_path
	GameStatsManager.save_path = _TEST_GAME_STATS_PATH


func after_all() -> void:
	GameStatsManager.save_path = _original_stats_path
	GameStatsManager._load_all()
	if FileAccess.file_exists(_TEST_ACHIEVEMENTS_PATH):
		DirAccess.remove_absolute(_TEST_ACHIEVEMENTS_PATH)
	if FileAccess.file_exists(_TEST_GAME_STATS_PATH):
		DirAccess.remove_absolute(_TEST_GAME_STATS_PATH)


func before_each() -> void:
	GameStatsManager.clear_all()
	achievements = Node.new()
	achievements.set_script(AchievementScript)
	achievements.save_path = _TEST_ACHIEVEMENTS_PATH
	add_child_autofree(achievements)
	achievements.reset_all_progress()


func after_each() -> void:
	if is_instance_valid(achievements):
		achievements.reset_all_progress()
	GameStatsManager.clear_all()
	var toast_layer: Node = get_tree().root.get_node_or_null("AchievementToastLayer")
	if toast_layer:
		toast_layer.queue_free()


func test_snapshot_includes_categories_with_general_first() -> void:
	var snapshot: Array[Dictionary] = achievements.get_achievement_snapshot()
	assert_eq(snapshot.size(), AchievementScript.ACHIEVEMENT_DEFINITIONS.size())

	var categories: Array[String] = []
	for achievement in snapshot:
		var category: String = str(achievement.get("category", ""))
		if not categories.has(category):
			categories.append(category)
	assert_eq(categories, ["General", "Sudoku", "Blockudoku", "Shikaku"])


func test_sudoku_win_tracking_unlocks_difficulty_and_time_achievements() -> void:
	GameStatsManager.increment_counter("general", "games_played")
	GameStatsManager.increment_counter("general", "games_won")
	GameStatsManager.increment_counter("general", "current_win_streak")
	GameStatsManager.increment_counter("sudoku", "games_won")
	GameStatsManager.increment_counter("sudoku", "perfect_wins")
	GameStatsManager.increment_counter("sudoku", "wins_under_300s")
	GameStatsManager.increment_counter("sudoku", "wins_under_180s")
	GameStatsManager.increment_counter("sudoku", "won_d3")
	GameStatsManager.increment_counter("sudoku", "won_d4")
	achievements.track("general.game_started.sudoku")
	achievements.check_stats()

	assert_true(bool(_get_achievement("first_game").get("unlocked", false)))
	assert_true(bool(_get_achievement("sudoku_no_errors").get("unlocked", false)))
	assert_true(bool(_get_achievement("sudoku_evil_win").get("unlocked", false)))
	assert_true(bool(_get_achievement("sudoku_under_5").get("unlocked", false)))
	assert_true(bool(_get_achievement("sudoku_under_3").get("unlocked", false)))
	assert_eq(int(_get_achievement("sudoku_10_wins").get("current_value", 0)), 1)


func test_blockudoku_tracking_unlocks_score_and_clear_achievements() -> void:
	GameStatsManager.increment_counter("blockudoku", "games_completed")
	GameStatsManager.set_counter("blockudoku", "high_score", 1200)
	achievements.check_stats()

	GameStatsManager.increment_counter("blockudoku", "total_clears", 4)
	achievements.track("blockudoku.clear_count", 4)
	achievements.check_stats()
	GameStatsManager.increment_counter("blockudoku", "total_clears", 196)
	achievements.check_stats()

	assert_true(bool(_get_achievement("blockudoku_first_game").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_score_100").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_score_500").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_score_1000").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_clear_three").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_clear_four").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_50_clears").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_200_clears").get("unlocked", false)))


func test_shikaku_and_general_streaks_unlock_and_reset() -> void:
	for i in 10:
		GameStatsManager.increment_counter("general", "games_won")
		GameStatsManager.set_counter("general", "current_win_streak", i + 1)
		GameStatsManager.increment_counter("shikaku", "games_won")
		GameStatsManager.increment_counter("shikaku", "completed_s5")
		GameStatsManager.increment_counter("shikaku", "wins_under_60s")
		GameStatsManager.set_counter("shikaku", "current_streak", i + 1)
		achievements.check_stats()

	assert_true(bool(_get_achievement("streak_5").get("unlocked", false)))
	assert_true(bool(_get_achievement("shikaku_first_win").get("unlocked", false)))
	assert_true(bool(_get_achievement("shikaku_5x5_win").get("unlocked", false)))
	assert_true(bool(_get_achievement("shikaku_under_60").get("unlocked", false)))
	assert_true(bool(_get_achievement("shikaku_streak_5").get("unlocked", false)))

	GameStatsManager.set_counter("general", "current_win_streak", 0)
	achievements.check_stats()
	assert_eq(int(_get_achievement("streak_15").get("current_value", 0)), 0)


func _get_achievement(achievement_id: String) -> Dictionary:
	var snapshot: Array[Dictionary] = achievements.get_achievement_snapshot()
	for achievement in snapshot:
		if str(achievement.get("id", "")) == achievement_id:
			return achievement
	return {}
