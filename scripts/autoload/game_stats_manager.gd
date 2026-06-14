extends Node

## Unified stats manager for all Games in the Collection.
## Stores historical entries as Arrays of Dictionaries keyed by game_id.
## Each Game records opaque stat entries; computation (averages, bests) is
## the Game's responsibility.

const DEFAULT_SAVE_PATH := "user://game_stats.cfg"
var save_path := DEFAULT_SAVE_PATH
const HISTORY_LIMIT := 30

signal stats_recorded(game_id: String)
signal stats_cleared(game_id: String)

# In-memory cache: game_id -> Array[Dictionary]
var _history_cache: Dictionary = {}
# Aggregate counters: game_id -> Dictionary of counters
var _counters_cache: Dictionary = {}


func _ready() -> void:
	_load_all()
	_migrate_legacy_stats()


## Record a stat entry for a game. The entry is an opaque Dictionary.
## Entries are appended to a capped history (last HISTORY_LIMIT entries).
func record(game_id: String, entry: Dictionary) -> void:
	_ensure_game(game_id)
	var history: Array = _history_cache[game_id]
	history.append(entry)
	if history.size() > HISTORY_LIMIT:
		_history_cache[game_id] = history.slice(history.size() - HISTORY_LIMIT)
	_save_all()
	stats_recorded.emit(game_id)


## Get the full history for a game (up to HISTORY_LIMIT entries).
func get_history(game_id: String) -> Array:
	_ensure_game(game_id)
	return (_history_cache[game_id] as Array).duplicate()


## Increment a named counter for a game.
func increment_counter(game_id: String, counter_name: String, amount: int = 1) -> void:
	_ensure_game(game_id)
	var counters: Dictionary = _counters_cache[game_id]
	counters[counter_name] = counters.get(counter_name, 0) + amount
	_save_all()


## Get a counter value.
func get_counter(game_id: String, counter_name: String) -> int:
	_ensure_game(game_id)
	return _counters_cache[game_id].get(counter_name, 0)


## Get all counters for a game.
func get_counters(game_id: String) -> Dictionary:
	_ensure_game(game_id)
	return (_counters_cache[game_id] as Dictionary).duplicate()


## Set a counter to a specific value (useful for streaks, bests).
func set_counter(game_id: String, counter_name: String, value: int) -> void:
	_ensure_game(game_id)
	_counters_cache[game_id][counter_name] = value
	_save_all()


## Clear all stats for a specific game.
func clear(game_id: String) -> void:
	_history_cache[game_id] = []
	_counters_cache[game_id] = {}
	_save_all()
	stats_cleared.emit(game_id)


## Clear all stats for all games.
func clear_all() -> void:
	_history_cache.clear()
	_counters_cache.clear()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)


func _ensure_game(game_id: String) -> void:
	if not _history_cache.has(game_id):
		_history_cache[game_id] = []
	if not _counters_cache.has(game_id):
		_counters_cache[game_id] = {}


func _save_all() -> void:
	var config := ConfigFile.new()
	for game_id in _history_cache.keys():
		config.set_value(game_id, "history", _history_cache[game_id])
	for game_id in _counters_cache.keys():
		config.set_value(game_id, "counters", _counters_cache[game_id])
	config.save(save_path)


func _load_all() -> void:
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	for game_id in config.get_sections():
		var raw_history = config.get_value(game_id, "history", [])
		if raw_history is Array:
			_history_cache[game_id] = raw_history
		else:
			_history_cache[game_id] = []
		var raw_counters = config.get_value(game_id, "counters", {})
		if raw_counters is Dictionary:
			_counters_cache[game_id] = raw_counters
		else:
			_counters_cache[game_id] = {}


# --- Legacy data migration ---

const _LEGACY_STATS_PATH_SUDOKU := "user://stats.cfg"
const _LEGACY_STATS_PATH_BLOCKUDOKU := "user://blockudoku_stats.cfg"
const _LEGACY_STATS_PATH_SHIKAKU := "user://shikaku_stats.cfg"


func _migrate_legacy_stats() -> void:
	_migrate_sudoku_stats()
	_migrate_blockudoku_stats()
	_migrate_shikaku_stats()


func _migrate_sudoku_stats() -> void:
	if not FileAccess.file_exists(_LEGACY_STATS_PATH_SUDOKU):
		return
	# Skip if we already have data
	if not get_history("sudoku").is_empty() or not get_counters("sudoku").is_empty():
		DirAccess.remove_absolute(_LEGACY_STATS_PATH_SUDOKU)
		return
	var config := ConfigFile.new()
	if config.load(_LEGACY_STATS_PATH_SUDOKU) != OK:
		return

	# Migrate counters
	var total_played: int = config.get_value("global", "total_played", 0)
	if total_played > 0:
		set_counter("sudoku", "games_started", total_played)
	set_counter("sudoku", "current_streak", config.get_value("global", "current_streak", 0))
	set_counter("sudoku", "best_streak", config.get_value("global", "best_streak", 0))

	for d in range(5):
		var started: int = config.get_value("games", "started_%d" % d, 0)
		if started > 0:
			set_counter("sudoku", "started_d%d" % d, started)
		var completed: int = config.get_value("games", "completed_%d" % d, 0)
		if completed > 0:
			set_counter("sudoku", "completed_d%d" % d, completed)
		var abandoned: int = config.get_value("games", "abandoned_%d" % d, 0)
		if abandoned > 0:
			set_counter("sudoku", "abandoned_d%d" % d, abandoned)
		var won: int = config.get_value("games", "won_%d" % d, 0)
		if won > 0:
			set_counter("sudoku", "won_d%d" % d, won)
		var lost: int = config.get_value("games", "lost_%d" % d, 0)
		if lost > 0:
			set_counter("sudoku", "lost_d%d" % d, lost)
		var best_time: float = config.get_value("times", "best_%d" % d, -1.0)
		if best_time > 0:
			set_counter("sudoku", "best_d%d" % d, int(best_time * 1000.0))

	# Migrate time history into record entries
	for d in range(5):
		var raw_history = config.get_value("time_history", str(d), [])
		if raw_history is Array:
			for time_val in raw_history:
				record("sudoku", {"difficulty": d, "time": float(time_val), "completed": true})

	DirAccess.remove_absolute(_LEGACY_STATS_PATH_SUDOKU)


func _migrate_blockudoku_stats() -> void:
	if not FileAccess.file_exists(_LEGACY_STATS_PATH_BLOCKUDOKU):
		return
	if not get_history("blockudoku").is_empty() or not get_counters("blockudoku").is_empty():
		DirAccess.remove_absolute(_LEGACY_STATS_PATH_BLOCKUDOKU)
		return
	var config := ConfigFile.new()
	if config.load(_LEGACY_STATS_PATH_BLOCKUDOKU) != OK:
		return

	# Migrate counters
	var games_played: int = config.get_value("stats", "games_played", 0)
	if games_played > 0:
		set_counter("blockudoku", "games_played", games_played)
	var high_score: int = config.get_value("stats", "high_score", 0)
	if high_score > 0:
		set_counter("blockudoku", "high_score", high_score)
	var best_turns: int = config.get_value("stats", "best_turns", 0)
	if best_turns > 0:
		set_counter("blockudoku", "best_turns", best_turns)
	var total_score: int = config.get_value("stats", "total_score", 0)
	if total_score > 0:
		set_counter("blockudoku", "total_score", total_score)
	var total_turns: int = config.get_value("stats", "total_turns", 0)
	if total_turns > 0:
		set_counter("blockudoku", "total_turns", total_turns)
	var total_clears: int = config.get_value("stats", "total_clears", 0)
	if total_clears > 0:
		set_counter("blockudoku", "total_clears", total_clears)

	# Migrate score history
	if config.has_section("score_history"):
		for mode in config.get_section_keys("score_history"):
			var raw_scores = config.get_value("score_history", mode, [])
			if raw_scores is Array:
				for score_val in raw_scores:
					record("blockudoku", {"mode": mode, "score": int(score_val)})

	DirAccess.remove_absolute(_LEGACY_STATS_PATH_BLOCKUDOKU)


func _migrate_shikaku_stats() -> void:
	if not FileAccess.file_exists(_LEGACY_STATS_PATH_SHIKAKU):
		return
	if not get_history("shikaku").is_empty() or not get_counters("shikaku").is_empty():
		DirAccess.remove_absolute(_LEGACY_STATS_PATH_SHIKAKU)
		return
	var config := ConfigFile.new()
	if config.load(_LEGACY_STATS_PATH_SHIKAKU) != OK:
		return

	# Migrate counters
	var total_played: int = config.get_value("global", "total_games_played", 0)
	if total_played > 0:
		set_counter("shikaku", "games_started", total_played)
	set_counter("shikaku", "current_streak", config.get_value("global", "current_streak", 0))
	set_counter("shikaku", "best_streak", config.get_value("global", "best_streak", 0))

	var sizes := [5, 7, 8, 10, 12, 15]
	for s in sizes:
		var started: int = config.get_value("games", "started_%d" % s, 0)
		if started > 0:
			set_counter("shikaku", "started_s%d" % s, started)
		var completed: int = config.get_value("games", "completed_%d" % s, 0)
		if completed > 0:
			set_counter("shikaku", "completed_s%d" % s, completed)
		var abandoned: int = config.get_value("games", "abandoned_%d" % s, 0)
		if abandoned > 0:
			set_counter("shikaku", "abandoned_s%d" % s, abandoned)
		var best_time: float = config.get_value("times", "best_%d" % s, -1.0)
		if best_time > 0:
			set_counter("shikaku", "best_s%d" % s, int(best_time * 1000.0))

	# Migrate time history into record entries
	for s in sizes:
		var raw_history = config.get_value("time_history", str(s), [])
		if raw_history is Array:
			for time_val in raw_history:
				record("shikaku", {"size": s, "time": float(time_val), "completed": true})

	DirAccess.remove_absolute(_LEGACY_STATS_PATH_SHIKAKU)
