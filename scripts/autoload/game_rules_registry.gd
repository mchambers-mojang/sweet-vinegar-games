extends Node

## Per-game rule registry — games register their own keys with defaults on load

signal rule_changed(game_id: String, key: String)

const SAVE_PATH := "user://settings.cfg"

# _rules[game_id][key] = value
var _rules: Dictionary = {}
# _registered[game_id] = true once register_rules has been called
var _registered: Dictionary = {}


## Register rules for a game. Persisted values take precedence over defaults.
## Safe to call multiple times — subsequent calls are no-ops.
func register_rules(game_id: String, defaults: Dictionary) -> void:
	if _registered.get(game_id, false):
		return
	_registered[game_id] = true
	var stored: Dictionary = {}
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		for key in defaults.keys():
			stored[key] = config.get_value(game_id, key, defaults[key])
	else:
		stored = defaults.duplicate()
	_rules[game_id] = stored


func get_rule(game_id: String, key: String) -> Variant:
	if not _rules.has(game_id):
		push_warning("GameRulesRegistry: game_id '%s' not registered" % game_id)
		return null
	return _rules[game_id].get(key)


func set_rule(game_id: String, key: String, value: Variant) -> void:
	if not _rules.has(game_id):
		push_warning("GameRulesRegistry: game_id '%s' not registered" % game_id)
		return
	_rules[game_id][key] = value
	rule_changed.emit(game_id, key)


func save() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	for game_id in _rules.keys():
		var game_rules: Dictionary = _rules[game_id]
		for key in game_rules.keys():
			config.set_value(game_id, key, game_rules[key])
	config.save(SAVE_PATH)
