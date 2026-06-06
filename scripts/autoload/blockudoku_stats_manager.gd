extends Node

## Stats tracking for Blockudoku

const SAVE_PATH := "user://blockudoku_stats.cfg"
const DEFAULT_MODE := "classic"
const SCORE_HISTORY_LIMIT := 30

var games_played: int = 0
var high_score: int = 0
var best_turns: int = 0
var total_score: int = 0
var total_turns: int = 0
var total_clears: int = 0
var score_history_by_mode: Dictionary = {}


func _ready() -> void:
	load_stats()


func record_game_started() -> void:
	games_played += 1
	save_stats()


func record_game_over(final_score: int, final_turns: int, mode: String = DEFAULT_MODE) -> void:
	total_score += final_score
	total_turns += final_turns
	if final_score > high_score:
		high_score = final_score
	if final_turns > best_turns:
		best_turns = final_turns
	_append_score_history(mode, final_score)
	save_stats()


func record_clears(count: int) -> void:
	total_clears += count
	save_stats()


func get_average_turns() -> float:
	if games_played == 0:
		return 0.0
	return float(total_turns) / float(games_played)


func get_score_history(mode: String = DEFAULT_MODE) -> Array:
	_ensure_mode_history(mode)
	return (score_history_by_mode[mode] as Array).duplicate()


func get_average_score(mode: String = DEFAULT_MODE) -> float:
	var history: Array = get_score_history(mode)
	if history.is_empty():
		return 0.0
	var total := 0
	for score in history:
		total += int(score)
	return float(total) / float(history.size())


func get_best_score(mode: String = DEFAULT_MODE) -> int:
	var history: Array = get_score_history(mode)
	if history.is_empty():
		return 0
	var best := int(history[0])
	for score in history:
		best = maxi(best, int(score))
	return best


func reset_all() -> void:
	games_played = 0
	high_score = 0
	best_turns = 0
	total_score = 0
	total_turns = 0
	total_clears = 0
	score_history_by_mode.clear()
	_ensure_mode_history(DEFAULT_MODE)
	save_stats()


func save_stats() -> void:
	var config := ConfigFile.new()
	config.set_value("stats", "games_played", games_played)
	config.set_value("stats", "high_score", high_score)
	config.set_value("stats", "best_turns", best_turns)
	config.set_value("stats", "total_score", total_score)
	config.set_value("stats", "total_turns", total_turns)
	config.set_value("stats", "total_clears", total_clears)
	for mode in score_history_by_mode.keys():
		config.set_value("score_history", str(mode), score_history_by_mode[mode])
	config.save(SAVE_PATH)


func load_stats() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	games_played = config.get_value("stats", "games_played", 0)
	high_score = config.get_value("stats", "high_score", 0)
	best_turns = config.get_value("stats", "best_turns", 0)
	total_score = config.get_value("stats", "total_score", 0)
	total_turns = config.get_value("stats", "total_turns", 0)
	total_clears = config.get_value("stats", "total_clears", 0)
	score_history_by_mode.clear()
	if config.has_section("score_history"):
		for mode in config.get_section_keys("score_history"):
			var raw_scores = config.get_value("score_history", mode, [])
			if raw_scores is Array:
				var normalized_scores: Array = []
				for score in raw_scores:
					normalized_scores.append(int(score))
				if normalized_scores.size() > SCORE_HISTORY_LIMIT:
					normalized_scores = normalized_scores.slice(normalized_scores.size() - SCORE_HISTORY_LIMIT)
				score_history_by_mode[mode] = normalized_scores
	_ensure_mode_history(DEFAULT_MODE)


func _ensure_mode_history(mode: String) -> void:
	if not score_history_by_mode.has(mode):
		score_history_by_mode[mode] = []
		return
	if not (score_history_by_mode[mode] is Array):
		score_history_by_mode[mode] = []


func _append_score_history(mode: String, score: int) -> void:
	_ensure_mode_history(mode)
	var history := score_history_by_mode[mode] as Array
	history.append(score)
	if history.size() > SCORE_HISTORY_LIMIT:
		history = history.slice(history.size() - SCORE_HISTORY_LIMIT)
	score_history_by_mode[mode] = history
