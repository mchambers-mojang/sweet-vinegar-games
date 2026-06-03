extends Node

## Stats tracking for Shikaku — per grid size

const SAVE_PATH := "user://shikaku_stats.cfg"
const SIZES := [5, 7, 8, 10, 12, 15]

var best_times: Dictionary = {}       # size -> float
var total_times: Dictionary = {}      # size -> float
var games_started: Dictionary = {}    # size -> int
var games_completed: Dictionary = {}  # size -> int
var games_abandoned: Dictionary = {}  # size -> int
var total_games_played: int = 0
var current_streak: int = 0
var best_streak: int = 0


func _ready() -> void:
	_init_defaults()
	load_stats()


func _init_defaults() -> void:
	for s in SIZES:
		if not best_times.has(s):
			best_times[s] = -1.0
		if not total_times.has(s):
			total_times[s] = 0.0
		if not games_started.has(s):
			games_started[s] = 0
		if not games_completed.has(s):
			games_completed[s] = 0
		if not games_abandoned.has(s):
			games_abandoned[s] = 0


func record_game_started(grid_size: int) -> void:
	games_started[grid_size] = games_started.get(grid_size, 0) + 1
	total_games_played += 1
	save_stats()


func record_game_completed(grid_size: int, time: float) -> void:
	games_completed[grid_size] = games_completed.get(grid_size, 0) + 1
	total_times[grid_size] = total_times.get(grid_size, 0.0) + time

	var best: float = best_times.get(grid_size, -1.0)
	if best < 0 or time < best:
		best_times[grid_size] = time

	current_streak += 1
	if current_streak > best_streak:
		best_streak = current_streak
	save_stats()


func record_game_abandoned(grid_size: int) -> void:
	games_abandoned[grid_size] = games_abandoned.get(grid_size, 0) + 1
	current_streak = 0
	save_stats()


func get_average_time(grid_size: int) -> float:
	var completed: int = games_completed.get(grid_size, 0)
	if completed == 0:
		return -1.0
	return total_times.get(grid_size, 0.0) / completed


func get_completion_rate(grid_size: int) -> float:
	var started: int = games_started.get(grid_size, 0)
	if started == 0:
		return 0.0
	return float(games_completed.get(grid_size, 0)) / started * 100.0


func reset_all() -> void:
	for s in SIZES:
		best_times[s] = -1.0
		total_times[s] = 0.0
		games_started[s] = 0
		games_completed[s] = 0
		games_abandoned[s] = 0
	total_games_played = 0
	current_streak = 0
	best_streak = 0
	save_stats()


func save_stats() -> void:
	var config := ConfigFile.new()
	for s in SIZES:
		config.set_value("times", "best_%d" % s, best_times.get(s, -1.0))
		config.set_value("times", "total_%d" % s, total_times.get(s, 0.0))
		config.set_value("games", "started_%d" % s, games_started.get(s, 0))
		config.set_value("games", "completed_%d" % s, games_completed.get(s, 0))
		config.set_value("games", "abandoned_%d" % s, games_abandoned.get(s, 0))
	config.set_value("global", "total_games_played", total_games_played)
	config.set_value("global", "current_streak", current_streak)
	config.set_value("global", "best_streak", best_streak)
	config.save(SAVE_PATH)


func load_stats() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for s in SIZES:
		best_times[s] = config.get_value("times", "best_%d" % s, -1.0)
		total_times[s] = config.get_value("times", "total_%d" % s, 0.0)
		games_started[s] = config.get_value("games", "started_%d" % s, 0)
		games_completed[s] = config.get_value("games", "completed_%d" % s, 0)
		games_abandoned[s] = config.get_value("games", "abandoned_%d" % s, 0)
	total_games_played = config.get_value("global", "total_games_played", 0)
	current_streak = config.get_value("global", "current_streak", 0)
	best_streak = config.get_value("global", "best_streak", 0)
