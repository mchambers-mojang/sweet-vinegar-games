extends Node

## Stats tracking for Blockudoku

const SAVE_PATH := "user://blockudoku_stats.cfg"

var games_played: int = 0
var high_score: int = 0
var best_turns: int = 0
var total_score: int = 0
var total_turns: int = 0
var total_clears: int = 0


func _ready() -> void:
	load_stats()


func record_game_started() -> void:
	games_played += 1
	save_stats()


func record_game_over(final_score: int, final_turns: int) -> void:
	total_score += final_score
	total_turns += final_turns
	if final_score > high_score:
		high_score = final_score
	if final_turns > best_turns:
		best_turns = final_turns
	save_stats()


func record_clears(count: int) -> void:
	total_clears += count
	save_stats()


func get_average_turns() -> float:
	if games_played == 0:
		return 0.0
	return float(total_turns) / float(games_played)


func reset_all() -> void:
	games_played = 0
	high_score = 0
	best_turns = 0
	total_score = 0
	total_turns = 0
	total_clears = 0
	save_stats()


func save_stats() -> void:
	var config := ConfigFile.new()
	config.set_value("stats", "games_played", games_played)
	config.set_value("stats", "high_score", high_score)
	config.set_value("stats", "best_turns", best_turns)
	config.set_value("stats", "total_score", total_score)
	config.set_value("stats", "total_turns", total_turns)
	config.set_value("stats", "total_clears", total_clears)
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
