extends Node

## Global achievement tracking with local persistence and event-driven updates.

signal achievement_unlocked(achievement_id: String, definition: Dictionary)
signal platform_unlock_requested(payload: Dictionary)

const SAVE_PATH := "user://achievements.cfg"
const CATEGORY_ORDER := {"General": 0, "Sudoku": 1, "Blockudoku": 2, "Shikaku": 3}
const TIER_ORDER := {"Bronze": 0, "Silver": 1, "Gold": 2}

const ACHIEVEMENT_DEFINITIONS := {
	"first_game": {
		"id": "first_game",
		"category": "General",
		"title": "Getting Started",
		"description": "Play your first game.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"play_25": {
		"id": "play_25",
		"category": "General",
		"title": "Dedicated Player",
		"description": "Play 25 games total.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 25,
	},
	"play_100": {
		"id": "play_100",
		"category": "General",
		"title": "Centurion",
		"description": "Play 100 games total.",
		"tier": "Silver",
		"hidden": true,
		"prerequisite_id": "play_25",
		"reward_type": "",
		"reward_id": "",
		"target_value": 100,
	},
	"win_10": {
		"id": "win_10",
		"category": "General",
		"title": "Puzzle Winner",
		"description": "Win 10 games.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 10,
	},
	"win_50": {
		"id": "win_50",
		"category": "General",
		"title": "Puzzle Veteran",
		"description": "Win 50 games.",
		"tier": "Silver",
		"hidden": true,
		"prerequisite_id": "win_10",
		"reward_type": "",
		"reward_id": "",
		"target_value": 50,
	},
	"win_100": {
		"id": "win_100",
		"category": "General",
		"title": "Puzzle Legend",
		"description": "Win 100 games.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "win_50",
		"reward_type": "",
		"reward_id": "",
		"target_value": 100,
	},
	"all_modes_session": {
		"id": "all_modes_session",
		"category": "General",
		"title": "Sampler Session",
		"description": "Use all 3 game modes in one session.",
		"tier": "Bronze",
		"hidden": true,
		"prerequisite_id": "",
		"reward_type": "shape",
		"reward_id": "",
		"target_value": 1,
	},
	"streak_5": {
		"id": "streak_5",
		"category": "General",
		"title": "On a Roll",
		"description": "Win 5 games in a row.",
		"tier": "Silver",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 5,
	},
	"streak_15": {
		"id": "streak_15",
		"category": "General",
		"title": "Unstoppable",
		"description": "Win 15 games in a row.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "streak_5",
		"reward_type": "",
		"reward_id": "",
		"target_value": 15,
	},
	"sudoku_easy_win": {
		"id": "sudoku_easy_win",
		"category": "Sudoku",
		"title": "Easy Street",
		"description": "Complete an Easy Sudoku puzzle.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"sudoku_no_errors": {
		"id": "sudoku_no_errors",
		"category": "Sudoku",
		"title": "Clean Finish",
		"description": "Complete a Sudoku with no errors.",
		"tier": "Silver",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "theme",
		"reward_id": "",
		"target_value": 1,
	},
	"sudoku_under_5": {
		"id": "sudoku_under_5",
		"category": "Sudoku",
		"title": "Speed Demon",
		"description": "Complete any Sudoku in under 5 minutes.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"sudoku_under_3": {
		"id": "sudoku_under_3",
		"category": "Sudoku",
		"title": "Lightning Fast",
		"description": "Complete any Sudoku in under 3 minutes.",
		"tier": "Silver",
		"hidden": true,
		"prerequisite_id": "sudoku_under_5",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"sudoku_expert_win": {
		"id": "sudoku_expert_win",
		"category": "Sudoku",
		"title": "Expert Solver",
		"description": "Complete an Expert Sudoku puzzle.",
		"tier": "Silver",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"sudoku_evil_win": {
		"id": "sudoku_evil_win",
		"category": "Sudoku",
		"title": "Pure Evil",
		"description": "Complete an Evil Sudoku puzzle.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "sudoku_expert_win",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"sudoku_10_wins": {
		"id": "sudoku_10_wins",
		"category": "Sudoku",
		"title": "Sudoku Regular",
		"description": "Win 10 Sudoku games.",
		"tier": "Silver",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 10,
	},
	"sudoku_50_wins": {
		"id": "sudoku_50_wins",
		"category": "Sudoku",
		"title": "Sudoku Master",
		"description": "Win 50 Sudoku games.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "sudoku_10_wins",
		"reward_type": "",
		"reward_id": "",
		"target_value": 50,
	},
	"blockudoku_first_game": {
		"id": "blockudoku_first_game",
		"category": "Blockudoku",
		"title": "Block Party",
		"description": "Play your first Blockudoku game.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_clear_three": {
		"id": "blockudoku_clear_three",
		"category": "Blockudoku",
		"title": "Triple Threat",
		"description": "Clear 3 lines or boxes at once in Blockudoku.",
		"tier": "Bronze",
		"hidden": true,
		"prerequisite_id": "",
		"reward_type": "effect",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_score_100": {
		"id": "blockudoku_score_100",
		"category": "Blockudoku",
		"title": "Century",
		"description": "Score 100 or more in one Blockudoku game.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_10_games": {
		"id": "blockudoku_10_games",
		"category": "Blockudoku",
		"title": "Block Builder",
		"description": "Play 10 Blockudoku games.",
		"tier": "Silver",
		"hidden": false,
		"prerequisite_id": "blockudoku_first_game",
		"reward_type": "",
		"reward_id": "",
		"target_value": 10,
	},
	"blockudoku_score_500": {
		"id": "blockudoku_score_500",
		"category": "Blockudoku",
		"title": "High Roller",
		"description": "Score 500 or more in one Blockudoku game.",
		"tier": "Silver",
		"hidden": true,
		"prerequisite_id": "blockudoku_score_100",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_50_clears": {
		"id": "blockudoku_50_clears",
		"category": "Blockudoku",
		"title": "Line Eraser",
		"description": "Clear 50 total lines or boxes in Blockudoku.",
		"tier": "Silver",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 50,
	},
	"blockudoku_score_1000": {
		"id": "blockudoku_score_1000",
		"category": "Blockudoku",
		"title": "Four Digits",
		"description": "Score 1000 or more in one Blockudoku game.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "blockudoku_score_500",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_200_clears": {
		"id": "blockudoku_200_clears",
		"category": "Blockudoku",
		"title": "Clear Machine",
		"description": "Clear 200 total lines or boxes in Blockudoku.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "blockudoku_50_clears",
		"reward_type": "",
		"reward_id": "",
		"target_value": 200,
	},
	"blockudoku_clear_four": {
		"id": "blockudoku_clear_four",
		"category": "Blockudoku",
		"title": "Quad Clear",
		"description": "Clear 4 or more lines or boxes at once in Blockudoku.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "blockudoku_clear_three",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_monster_clear": {
		"id": "blockudoku_monster_clear",
		"category": "Blockudoku",
		"title": "M-M-M-Monster Clear",
		"description": "Clear 5 or more lines or boxes at once in Blockudoku.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "blockudoku_clear_four",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_combo_2": {
		"id": "blockudoku_combo_2",
		"category": "Blockudoku",
		"title": "Double Up",
		"description": "Achieve a 2x combo in Blockudoku.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_combo_3": {
		"id": "blockudoku_combo_3",
		"category": "Blockudoku",
		"title": "Hat Trick",
		"description": "Achieve a 3x combo in Blockudoku.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "blockudoku_combo_2",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_combo_4": {
		"id": "blockudoku_combo_4",
		"category": "Blockudoku",
		"title": "On Fire",
		"description": "Achieve a 4x combo in Blockudoku.",
		"tier": "Silver",
		"hidden": true,
		"prerequisite_id": "blockudoku_combo_3",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_combo_5": {
		"id": "blockudoku_combo_5",
		"category": "Blockudoku",
		"title": "Unstoppable Streak",
		"description": "Achieve a 5x combo in Blockudoku.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "blockudoku_combo_4",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_combo_6": {
		"id": "blockudoku_combo_6",
		"category": "Blockudoku",
		"title": "Combo God",
		"description": "Achieve a 6x combo in Blockudoku.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "blockudoku_combo_5",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_clear_six": {
		"id": "blockudoku_clear_six",
		"category": "Blockudoku",
		"title": "Cleartacular",
		"description": "Clear 6 or more lines or boxes at once in Blockudoku.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "blockudoku_monster_clear",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"blockudoku_clear_seven": {
		"id": "blockudoku_clear_seven",
		"category": "Blockudoku",
		"title": "Clearamanjaro",
		"description": "Clear 7 or more lines or boxes at once in Blockudoku.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "blockudoku_clear_six",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"shikaku_first_win": {
		"id": "shikaku_first_win",
		"category": "Shikaku",
		"title": "Box Maker",
		"description": "Complete your first Shikaku puzzle.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"shikaku_5x5_win": {
		"id": "shikaku_5x5_win",
		"category": "Shikaku",
		"title": "Small Boxes",
		"description": "Complete a 5×5 Shikaku puzzle.",
		"tier": "Bronze",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"shikaku_10x10_win": {
		"id": "shikaku_10x10_win",
		"category": "Shikaku",
		"title": "Big Boxes",
		"description": "Complete a 10×10 Shikaku puzzle.",
		"tier": "Silver",
		"hidden": false,
		"prerequisite_id": "",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"shikaku_10_wins": {
		"id": "shikaku_10_wins",
		"category": "Shikaku",
		"title": "Shikaku Regular",
		"description": "Complete 10 Shikaku puzzles.",
		"tier": "Silver",
		"hidden": false,
		"prerequisite_id": "shikaku_first_win",
		"reward_type": "",
		"reward_id": "",
		"target_value": 10,
	},
	"shikaku_under_60": {
		"id": "shikaku_under_60",
		"category": "Shikaku",
		"title": "Quick Rectangles",
		"description": "Complete any Shikaku puzzle in under 60 seconds.",
		"tier": "Silver",
		"hidden": true,
		"prerequisite_id": "shikaku_first_win",
		"reward_type": "",
		"reward_id": "",
		"target_value": 1,
	},
	"shikaku_streak_5": {
		"id": "shikaku_streak_5",
		"category": "Shikaku",
		"title": "Box Streak",
		"description": "Win 5 Shikaku puzzles in a row.",
		"tier": "Gold",
		"hidden": true,
		"prerequisite_id": "shikaku_10_wins",
		"reward_type": "",
		"reward_id": "",
		"target_value": 5,
	},
}

var _progress: Dictionary = {}
var _session_modes: Dictionary = {}
var _toast_layer: CanvasLayer
var _current_win_streak: int = 0
var _toast_queue: Array[Dictionary] = []
var _toast_showing: bool = false


func _ready() -> void:
	_init_progress_defaults()
	_load_progress()


func track_game_started(mode: String) -> void:
	var total_games_played: int = _get_total_games_played()
	_set_progress_max("first_game", total_games_played)
	_set_progress_max("play_25", total_games_played)
	_set_progress_max("play_100", total_games_played)
	if mode != "":
		_session_modes[mode] = true
	if _session_modes.size() >= 3:
		_set_progress_max("all_modes_session", 1)
	_save_progress()


func track_game_won(mode: String, metadata: Dictionary = {}) -> void:
	if mode == "":
		return

	_current_win_streak += 1
	_increment_progress("win_10", 1)
	_increment_progress("win_50", 1)
	_increment_progress("win_100", 1)
	_set_progress_exact("streak_5", _current_win_streak)
	_set_progress_exact("streak_15", _current_win_streak)

	if mode == "sudoku":
		var strikes: int = int(metadata.get("strikes", 0))
		var difficulty: int = int(metadata.get("difficulty", -1))
		var elapsed_time: float = float(metadata.get("elapsed_time", -1.0))
		_increment_progress("sudoku_10_wins", 1)
		_increment_progress("sudoku_50_wins", 1)
		if strikes == 0:
			_set_progress_max("sudoku_no_errors", 1)
		if difficulty == 0:
			_set_progress_max("sudoku_easy_win", 1)
		elif difficulty == 3:
			_set_progress_max("sudoku_expert_win", 1)
		elif difficulty == 4:
			_set_progress_max("sudoku_evil_win", 1)
		if elapsed_time >= 0.0 and elapsed_time < 300.0:
			_set_progress_max("sudoku_under_5", 1)
		if elapsed_time >= 0.0 and elapsed_time < 180.0:
			_set_progress_max("sudoku_under_3", 1)

	_save_progress()


func track_blockudoku_game_played(score: int) -> void:
	var games_played: int = int(BlockudokuStatsManager.games_played)
	var high_score: int = maxi(score, int(BlockudokuStatsManager.high_score))
	_set_progress_max("blockudoku_first_game", games_played)
	_set_progress_max("blockudoku_10_games", games_played)
	if high_score >= 100:
		_set_progress_max("blockudoku_score_100", 1)
	if high_score >= 500:
		_set_progress_max("blockudoku_score_500", 1)
	if high_score >= 1000:
		_set_progress_max("blockudoku_score_1000", 1)
	_save_progress()


func track_blockudoku_clear(clear_count: int) -> void:
	var total_clears: int = int(BlockudokuStatsManager.total_clears)
	if clear_count >= 3:
		_set_progress_max("blockudoku_clear_three", 1)
	if clear_count >= 4:
		_set_progress_max("blockudoku_clear_four", 1)
	if clear_count >= 5:
		_set_progress_max("blockudoku_monster_clear", 1)
	if clear_count >= 6:
		_set_progress_max("blockudoku_clear_six", 1)
	if clear_count >= 7:
		_set_progress_max("blockudoku_clear_seven", 1)
	_set_progress_max("blockudoku_50_clears", total_clears)
	_set_progress_max("blockudoku_200_clears", total_clears)
	_save_progress()


func track_blockudoku_combo(combo_count: int) -> void:
	if combo_count >= 2:
		_set_progress_max("blockudoku_combo_2", 1)
	if combo_count >= 3:
		_set_progress_max("blockudoku_combo_3", 1)
	if combo_count >= 4:
		_set_progress_max("blockudoku_combo_4", 1)
	if combo_count >= 5:
		_set_progress_max("blockudoku_combo_5", 1)
	if combo_count >= 6:
		_set_progress_max("blockudoku_combo_6", 1)
	_save_progress()


func track_shikaku_won(size: int, time: float) -> void:
	var shikaku_streak: int = int(ShikakuStatsManager.current_streak)
	_set_progress_max("shikaku_first_win", 1)
	_increment_progress("shikaku_10_wins", 1)
	_set_progress_exact("shikaku_streak_5", shikaku_streak)
	if size == 5:
		_set_progress_max("shikaku_5x5_win", 1)
	if size == 10:
		_set_progress_max("shikaku_10x10_win", 1)
	if time < 60.0:
		_set_progress_max("shikaku_under_60", 1)
	_save_progress()


func track_streak_broken() -> void:
	_current_win_streak = 0
	_set_progress_exact("streak_5", 0, false)
	_set_progress_exact("streak_15", 0, false)
	_save_progress()


func get_achievement_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in ACHIEVEMENT_DEFINITIONS.keys():
		var definition: Dictionary = ACHIEVEMENT_DEFINITIONS[id]
		var progress_entry: Dictionary = _progress.get(id, {})
		var is_visible: bool = _is_visible(id)
		result.append({
			"id": id,
			"category": definition.get("category", "General"),
			"title": definition.get("title", ""),
			"description": definition.get("description", ""),
			"tier": definition.get("tier", "Bronze"),
			"hidden": definition.get("hidden", false),
			"is_visible": is_visible,
			"prerequisite_id": definition.get("prerequisite_id", ""),
			"reward_type": definition.get("reward_type", ""),
			"reward_id": definition.get("reward_id", ""),
			"current_value": int(progress_entry.get("current_value", 0)),
			"target_value": int(progress_entry.get("target_value", int(definition.get("target_value", 1)))),
			"unlocked": bool(progress_entry.get("unlocked", false)),
			"unlocked_at": int(progress_entry.get("unlocked_at", 0)),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var category_a: int = _get_category_order(str(a.get("category", "General")))
		var category_b: int = _get_category_order(str(b.get("category", "General")))
		if category_a != category_b:
			return category_a < category_b
		var tier_a: int = int(TIER_ORDER.get(str(a.get("tier", "Bronze")), 0))
		var tier_b: int = int(TIER_ORDER.get(str(b.get("tier", "Bronze")), 0))
		if tier_a != tier_b:
			return tier_a < tier_b
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return result


func get_platform_unlock_payload(achievement_id: String) -> Dictionary:
	if not ACHIEVEMENT_DEFINITIONS.has(achievement_id):
		return {}
	var definition: Dictionary = ACHIEVEMENT_DEFINITIONS[achievement_id]
	var progress_entry: Dictionary = _progress.get(achievement_id, {})
	if not bool(progress_entry.get("unlocked", false)):
		return {}
	return {
		"id": achievement_id,
		"title": definition.get("title", ""),
		"tier": definition.get("tier", "Bronze"),
		"reward_type": definition.get("reward_type", ""),
		"reward_id": definition.get("reward_id", ""),
		"target_value": int(definition.get("target_value", 1)),
		"unlocked_at": int(progress_entry.get("unlocked_at", 0)),
	}


func _init_progress_defaults() -> void:
	for id in ACHIEVEMENT_DEFINITIONS.keys():
		var definition: Dictionary = ACHIEVEMENT_DEFINITIONS[id]
		_progress[id] = {
			"achievement_id": id,
			"current_value": 0,
			"target_value": int(definition.get("target_value", 1)),
			"unlocked": false,
			"unlocked_at": 0,
		}


func _increment_progress(achievement_id: String, amount: int) -> void:
	if not _progress.has(achievement_id) or amount <= 0:
		return
	var entry: Dictionary = _progress[achievement_id]
	if bool(entry.get("unlocked", false)):
		return
	var target: int = int(entry.get("target_value", 1))
	var current_value: int = int(entry.get("current_value", 0))
	var next_value: int = clampi(current_value + amount, 0, target)
	entry["current_value"] = next_value
	if next_value >= target:
		_unlock_achievement(achievement_id, entry)
		return
	_progress[achievement_id] = entry


func _set_progress_max(achievement_id: String, value: int, show_toast: bool = true) -> void:
	if not _progress.has(achievement_id):
		return
	var entry: Dictionary = _progress[achievement_id]
	if bool(entry.get("unlocked", false)):
		return
	var target: int = int(entry.get("target_value", 1))
	var current_value: int = int(entry.get("current_value", 0))
	var next_value: int = clampi(maxi(current_value, value), 0, target)
	if next_value == current_value:
		return
	entry["current_value"] = next_value
	if next_value >= target:
		_unlock_achievement(achievement_id, entry, show_toast)
		return
	_progress[achievement_id] = entry


func _set_progress_exact(achievement_id: String, value: int, show_toast: bool = true) -> void:
	if not _progress.has(achievement_id):
		return
	var entry: Dictionary = _progress[achievement_id]
	if bool(entry.get("unlocked", false)):
		return
	var target: int = int(entry.get("target_value", 1))
	var next_value: int = clampi(value, 0, target)
	if next_value == int(entry.get("current_value", 0)):
		return
	entry["current_value"] = next_value
	if next_value >= target:
		_unlock_achievement(achievement_id, entry, show_toast)
		return
	_progress[achievement_id] = entry


func _unlock_achievement(achievement_id: String, entry: Dictionary, show_toast: bool = true) -> void:
	entry["unlocked"] = true
	entry["unlocked_at"] = Time.get_unix_time_from_system()
	_progress[achievement_id] = entry
	var definition: Dictionary = ACHIEVEMENT_DEFINITIONS.get(achievement_id, {})
	achievement_unlocked.emit(achievement_id, definition)
	platform_unlock_requested.emit(get_platform_unlock_payload(achievement_id))
	if show_toast:
		_show_toast(definition)


func _is_visible(achievement_id: String) -> bool:
	var definition: Dictionary = ACHIEVEMENT_DEFINITIONS.get(achievement_id, {})
	if not bool(definition.get("hidden", false)):
		return true
	if bool(_progress.get(achievement_id, {}).get("unlocked", false)):
		return true
	var prereq: String = str(definition.get("prerequisite_id", ""))
	if prereq == "":
		return false
	return bool(_progress.get(prereq, {}).get("unlocked", false))


func reset_all_progress() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_progress.clear()
	_session_modes.clear()
	_current_win_streak = 0
	_init_progress_defaults()


func _save_progress() -> void:
	var config := ConfigFile.new()
	for id in _progress.keys():
		var entry: Dictionary = _progress[id]
		config.set_value(id, "current_value", int(entry.get("current_value", 0)))
		config.set_value(id, "target_value", int(entry.get("target_value", 1)))
		config.set_value(id, "unlocked", bool(entry.get("unlocked", false)))
		config.set_value(id, "unlocked_at", int(entry.get("unlocked_at", 0)))
	config.set_value("__meta", "current_win_streak", _current_win_streak)
	config.save(SAVE_PATH)


func _load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for id in ACHIEVEMENT_DEFINITIONS.keys():
		var target: int = int(ACHIEVEMENT_DEFINITIONS[id].get("target_value", 1))
		var current: int = int(config.get_value(id, "current_value", 0))
		_progress[id] = {
			"achievement_id": id,
			"current_value": clampi(current, 0, target),
			"target_value": target,
			"unlocked": bool(config.get_value(id, "unlocked", false)),
			"unlocked_at": int(config.get_value(id, "unlocked_at", 0)),
		}
	_current_win_streak = int(config.get_value("__meta", "current_win_streak", 0))


func _get_total_games_played() -> int:
	return int(StatsManager.total_games_played) + int(BlockudokuStatsManager.games_played) + int(ShikakuStatsManager.total_games_played)


func _get_category_order(category: String) -> int:
	return int(CATEGORY_ORDER.get(category, CATEGORY_ORDER.size()))


func _show_toast(definition: Dictionary) -> void:
	if definition.is_empty():
		return
	_toast_queue.append(definition)
	if not _toast_showing:
		_show_next_toast()


func _show_next_toast() -> void:
	if _toast_queue.is_empty():
		_toast_showing = false
		return
	_toast_showing = true
	var definition: Dictionary = _toast_queue.pop_front()
	var root: Window = get_tree().root
	if root == null:
		_toast_showing = false
		return
	if _toast_layer == null or not is_instance_valid(_toast_layer):
		_toast_layer = CanvasLayer.new()
		_toast_layer.layer = 120
		_toast_layer.name = "AchievementToastLayer"
		root.add_child(_toast_layer)

	var label: Label = Label.new()
	label.text = "Achievement Unlocked: %s" % str(definition.get("title", ""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var vp_size: Vector2 = root.get_visible_rect().size
	var safe_top: int = SafeAreaManager.get_insets().get("top", 0)
	var toast_width: float = minf(420.0, vp_size.x * 0.85)
	label.custom_minimum_size = Vector2(toast_width, 48)
	label.size = Vector2(toast_width, 48)
	label.position = Vector2((vp_size.x - toast_width) * 0.5, safe_top + 24)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.pivot_offset = Vector2(toast_width, 48) / 2.0
	label.scale = Vector2(1.2, 1.2)
	_toast_layer.add_child(label)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(label, "position:y", label.position.y + 12.0, 3.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(2.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(func() -> void:
		label.queue_free()
		_show_next_toast()
	)
