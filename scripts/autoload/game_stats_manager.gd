extends Node

## Unified stats manager for all Games in the Collection.
## Stores historical entries as Arrays of Dictionaries keyed by game_id.
## Each Game records opaque stat entries; computation (averages, bests) is
## the Game's responsibility.

const SAVE_PATH := "user://game_stats.cfg"
const HISTORY_LIMIT := 30

signal stats_recorded(game_id: String)
signal stats_cleared(game_id: String)

# In-memory cache: game_id -> Array[Dictionary]
var _history_cache: Dictionary = {}
# Aggregate counters: game_id -> Dictionary of counters
var _counters_cache: Dictionary = {}


func _ready() -> void:
	_load_all()


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
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


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
	config.save(SAVE_PATH)


func _load_all() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
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
