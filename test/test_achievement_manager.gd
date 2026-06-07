extends GutTest

const AchievementScript := preload("res://scripts/autoload/achievement_manager.gd")

var achievements: Node


func before_each() -> void:
	StatsManager.reset_all()
	BlockudokuStatsManager.reset_all()
	ShikakuStatsManager.reset_all()
	achievements = Node.new()
	achievements.set_script(AchievementScript)
	add_child_autofree(achievements)
	achievements.reset_all_progress()


func after_each() -> void:
	if is_instance_valid(achievements):
		achievements.reset_all_progress()
	StatsManager.reset_all()
	BlockudokuStatsManager.reset_all()
	ShikakuStatsManager.reset_all()
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
	StatsManager.record_game_started(4)
	achievements.track_game_started("sudoku")
	achievements.track_game_won("sudoku", {
		"difficulty": 4,
		"elapsed_time": 170.0,
		"strikes": 0,
	})

	assert_true(bool(_get_achievement("first_game").get("unlocked", false)))
	assert_true(bool(_get_achievement("sudoku_no_errors").get("unlocked", false)))
	assert_true(bool(_get_achievement("sudoku_evil_win").get("unlocked", false)))
	assert_true(bool(_get_achievement("sudoku_under_5").get("unlocked", false)))
	assert_true(bool(_get_achievement("sudoku_under_3").get("unlocked", false)))
	assert_eq(int(_get_achievement("sudoku_10_wins").get("current_value", 0)), 1)


func test_blockudoku_tracking_unlocks_score_and_clear_achievements() -> void:
	BlockudokuStatsManager.record_game_started()
	achievements.track_game_started("blockudoku")
	BlockudokuStatsManager.record_game_over(1200, 42)
	achievements.track_blockudoku_game_played(1200)

	BlockudokuStatsManager.record_clears(4)
	achievements.track_blockudoku_clear(4)
	BlockudokuStatsManager.record_clears(196)
	achievements.track_blockudoku_clear(1)

	assert_true(bool(_get_achievement("blockudoku_first_game").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_score_100").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_score_500").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_score_1000").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_clear_three").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_clear_four").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_50_clears").get("unlocked", false)))
	assert_true(bool(_get_achievement("blockudoku_200_clears").get("unlocked", false)))


func test_shikaku_and_general_streaks_unlock_and_reset() -> void:
	for i in 5:
		ShikakuStatsManager.record_game_completed(5, 45.0)
		achievements.track_game_won("shikaku")
		achievements.track_shikaku_won(5, 45.0)

	assert_true(bool(_get_achievement("streak_5").get("unlocked", false)))
	assert_true(bool(_get_achievement("shikaku_first_win").get("unlocked", false)))
	assert_true(bool(_get_achievement("shikaku_5x5_win").get("unlocked", false)))
	assert_true(bool(_get_achievement("shikaku_under_60").get("unlocked", false)))
	assert_true(bool(_get_achievement("shikaku_streak_5").get("unlocked", false)))

	achievements.track_streak_broken()
	assert_eq(int(_get_achievement("streak_15").get("current_value", 0)), 0)


func _get_achievement(achievement_id: String) -> Dictionary:
	var snapshot: Array[Dictionary] = achievements.get_achievement_snapshot()
	for achievement in snapshot:
		if str(achievement.get("id", "")) == achievement_id:
			return achievement
	return {}
