extends Node

## Persistent statistics tracking

const SAVE_PATH := "user://stats.cfg"

## Per-difficulty stats stored as dictionaries keyed by difficulty int
var best_times: Dictionary = {}      # difficulty -> float (seconds)
var total_times: Dictionary = {}     # difficulty -> float (total seconds for averaging)
var games_started: Dictionary = {}   # difficulty -> int
var games_completed: Dictionary = {} # difficulty -> int
var games_abandoned: Dictionary = {} # difficulty -> int
var games_won: Dictionary = {}       # difficulty -> int (strict mode wins)
var games_lost: Dictionary = {}      # difficulty -> int (strict mode losses)

## Global stats
var total_games_played: int = 0
var current_streak: int = 0
var best_streak: int = 0


func _ready() -> void:
	_init_difficulty_dicts()
	load_stats()


func _init_difficulty_dicts() -> void:
	for d in range(5):  # 5 difficulty levels
		if not best_times.has(d):
			best_times[d] = -1.0
		if not total_times.has(d):
			total_times[d] = 0.0
		if not games_started.has(d):
			games_started[d] = 0
		if not games_completed.has(d):
			games_completed[d] = 0
		if not games_abandoned.has(d):
			games_abandoned[d] = 0
		if not games_won.has(d):
			games_won[d] = 0
		if not games_lost.has(d):
			games_lost[d] = 0


func record_game_started(difficulty: int) -> void:
	games_started[difficulty] = games_started.get(difficulty, 0) + 1
	total_games_played += 1
	save_stats()


func record_game_completed(difficulty: int, time: float, was_strict: bool, won: bool) -> void:
	games_completed[difficulty] = games_completed.get(difficulty, 0) + 1
	total_times[difficulty] = total_times.get(difficulty, 0.0) + time

	if best_times[difficulty] < 0 or time < best_times[difficulty]:
		best_times[difficulty] = time

	if was_strict:
		if won:
			games_won[difficulty] = games_won.get(difficulty, 0) + 1
			current_streak += 1
			if current_streak > best_streak:
				best_streak = current_streak
		else:
			games_lost[difficulty] = games_lost.get(difficulty, 0) + 1
			current_streak = 0

	save_stats()


func record_game_abandoned(difficulty: int) -> void:
	games_abandoned[difficulty] = games_abandoned.get(difficulty, 0) + 1
	current_streak = 0
	save_stats()


func get_average_time(difficulty: int) -> float:
	var completed: int = games_completed.get(difficulty, 0)
	if completed == 0:
		return -1.0
	return total_times.get(difficulty, 0.0) / completed


func get_completion_rate(difficulty: int) -> float:
	var started: int = games_started.get(difficulty, 0)
	if started == 0:
		return 0.0
	return float(games_completed.get(difficulty, 0)) / float(started) * 100.0


func reset_all() -> void:
	for d in range(5):
		best_times[d] = -1.0
		total_times[d] = 0.0
		games_started[d] = 0
		games_completed[d] = 0
		games_abandoned[d] = 0
		games_won[d] = 0
		games_lost[d] = 0
	total_games_played = 0
	current_streak = 0
	best_streak = 0
	save_stats()


func save_stats() -> void:
	var config := ConfigFile.new()
	for d in range(5):
		config.set_value("times", "best_%d" % d, best_times.get(d, -1.0))
		config.set_value("times", "total_%d" % d, total_times.get(d, 0.0))
		config.set_value("games", "started_%d" % d, games_started.get(d, 0))
		config.set_value("games", "completed_%d" % d, games_completed.get(d, 0))
		config.set_value("games", "abandoned_%d" % d, games_abandoned.get(d, 0))
		config.set_value("games", "won_%d" % d, games_won.get(d, 0))
		config.set_value("games", "lost_%d" % d, games_lost.get(d, 0))
	config.set_value("global", "total_played", total_games_played)
	config.set_value("global", "current_streak", current_streak)
	config.set_value("global", "best_streak", best_streak)
	config.save(SAVE_PATH)


func load_stats() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for d in range(5):
		best_times[d] = config.get_value("times", "best_%d" % d, -1.0)
		total_times[d] = config.get_value("times", "total_%d" % d, 0.0)
		games_started[d] = config.get_value("games", "started_%d" % d, 0)
		games_completed[d] = config.get_value("games", "completed_%d" % d, 0)
		games_abandoned[d] = config.get_value("games", "abandoned_%d" % d, 0)
		games_won[d] = config.get_value("games", "won_%d" % d, 0)
		games_lost[d] = config.get_value("games", "lost_%d" % d, 0)
	total_games_played = config.get_value("global", "total_played", 0)
	current_streak = config.get_value("global", "current_streak", 0)
	best_streak = config.get_value("global", "best_streak", 0)
