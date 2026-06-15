extends Node

signal achievement_unlocked(achievement_id: String, definition: Dictionary)
signal platform_unlock_requested(payload: Dictionary)

const AchievementCatalogScript := preload("res://scripts/achievements/achievement_catalog.gd")
const AchievementStoreScript := preload("res://scripts/achievements/achievement_store.gd")
const UnlockPresenterScript := preload("res://scripts/achievements/unlock_presenter.gd")

const DEFAULT_SAVE_PATH := "user://achievements.cfg"
const CATEGORY_ORDER = AchievementCatalog.CATEGORY_ORDER
const TIER_ORDER = AchievementCatalog.TIER_ORDER
const ACHIEVEMENT_DEFINITIONS = AchievementCatalog.DEFINITIONS

var save_path := DEFAULT_SAVE_PATH

var _progress: Dictionary = {}
var _session_modes: Dictionary = {}
var _store: AchievementStore
var _presenter: UnlockPresenter


func _ready() -> void:
	_store = AchievementStoreScript.new(save_path)
	_init_progress_defaults()
	_load_progress()
	_ensure_presenter()


func track(event_key: String, value: int = 1) -> void:
	var did_change := false
	if event_key.begins_with("general.game_started."):
		var mode: String = event_key.trim_prefix("general.game_started.")
		if mode != "" and not _session_modes.has(mode):
			_session_modes[mode] = true
			did_change = _evaluate_event_triggers("general.session_modes", _session_modes.size()) or did_change
	did_change = _evaluate_event_triggers(event_key, value) or did_change
	if did_change:
		_save_progress()


func check_stats() -> void:
	var did_change := false
	var keep_checking := true
	while keep_checking:
		keep_checking = false
		for id in ACHIEVEMENT_DEFINITIONS.keys():
			var definition: Dictionary = ACHIEVEMENT_DEFINITIONS[id]
			var trigger: Dictionary = definition.get("trigger", {})
			if str(trigger.get("type", "")) != "stat":
				continue
			if not _can_evaluate(id, definition):
				continue
			if _apply_stat_progress(id, definition):
				did_change = true
				keep_checking = true
	if did_change:
		_save_progress()


func reset_all_progress() -> void:
	if _store == null:
		_store = AchievementStoreScript.new(save_path)
	_store.clear()
	_progress.clear()
	_session_modes.clear()
	_init_progress_defaults()


func get_achievement_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in ACHIEVEMENT_DEFINITIONS.keys():
		var definition: Dictionary = ACHIEVEMENT_DEFINITIONS[id]
		var progress_entry: Dictionary = _progress.get(id, {})
		result.append({
			"id": id,
			"category": definition.get("category", "General"),
			"title": definition.get("title", ""),
			"description": definition.get("description", ""),
			"tier": definition.get("tier", "Bronze"),
			"hidden": definition.get("hidden", false),
			"is_visible": _is_visible(id),
			"prerequisite_id": definition.get("prerequisite_id", ""),
			"reward_type": definition.get("reward_type", ""),
			"reward_id": definition.get("reward_id", ""),
			"current_value": int(progress_entry.get("current_value", 0)),
			"target_value": int(progress_entry.get("target_value", int(definition.get("target_value", 1)))),
			"unlocked": bool(progress_entry.get("unlocked", false)),
			"unlocked_at": int(progress_entry.get("unlocked_at", 0)),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var category_a: int = int(CATEGORY_ORDER.get(str(a.get("category", "General")), CATEGORY_ORDER.size()))
		var category_b: int = int(CATEGORY_ORDER.get(str(b.get("category", "General")), CATEGORY_ORDER.size()))
		if category_a != category_b:
			return category_a < category_b
		var tier_a: int = int(TIER_ORDER.get(str(a.get("tier", "Bronze")), 0))
		var tier_b: int = int(TIER_ORDER.get(str(b.get("tier", "Bronze")), 0))
		if tier_a != tier_b:
			return tier_a < tier_b
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return result


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


func _load_progress() -> void:
	var loaded: Dictionary = _store.load_progress()
	for id in loaded.keys():
		if not _progress.has(id):
			continue
		var definition: Dictionary = ACHIEVEMENT_DEFINITIONS.get(id, {})
		var target: int = int(definition.get("target_value", 1))
		var entry: Dictionary = loaded[id]
		_progress[id] = {
			"achievement_id": id,
			"current_value": clampi(int(entry.get("current_value", 0)), 0, target),
			"target_value": target,
			"unlocked": bool(entry.get("unlocked", false)),
			"unlocked_at": int(entry.get("unlocked_at", 0)),
		}


func _save_progress() -> void:
	if _store == null or _store.save_path != save_path:
		_store = AchievementStoreScript.new(save_path)
	_store.save_progress(_progress)


func _ensure_presenter() -> void:
	_presenter = get_node_or_null("UnlockPresenter") as UnlockPresenter
	if _presenter == null:
		_presenter = UnlockPresenterScript.new()
		_presenter.name = "UnlockPresenter"
		add_child(_presenter)
	if not _presenter.platform_unlock_requested.is_connected(_on_presenter_platform_unlock_requested):
		_presenter.platform_unlock_requested.connect(_on_presenter_platform_unlock_requested)


func _on_presenter_platform_unlock_requested(payload: Dictionary) -> void:
	platform_unlock_requested.emit(payload)


func _evaluate_event_triggers(event_key: String, value: int) -> bool:
	var matches: Array[Dictionary] = []
	for id in ACHIEVEMENT_DEFINITIONS.keys():
		var definition: Dictionary = ACHIEVEMENT_DEFINITIONS[id]
		var trigger: Dictionary = definition.get("trigger", {})
		if str(trigger.get("type", "")) != "event":
			continue
		if str(trigger.get("key", "")) != event_key:
			continue
		matches.append({
			"id": id,
			"definition": definition,
			"threshold": int(trigger.get("threshold", 1)),
		})
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("threshold", 0)) < int(b.get("threshold", 0))
	)
	var changed := false
	for match in matches:
		var id: String = str(match.get("id", ""))
		var definition: Dictionary = match.get("definition", {})
		if not _can_evaluate(id, definition):
			continue
		var threshold: int = int(match.get("threshold", 1))
		if value < threshold:
			continue
		changed = _set_progress_max(id, 1) or changed
	return changed


func _apply_stat_progress(achievement_id: String, definition: Dictionary) -> bool:
	var trigger: Dictionary = definition.get("trigger", {})
	var stat_value: int = _get_stat_value(str(trigger.get("key", "")))
	var target: int = int(definition.get("target_value", 1))
	var progress_mode: String = str(definition.get("progress_mode", "max"))
	if progress_mode == "exact":
		return _set_progress_exact(achievement_id, clampi(stat_value, 0, target))
	return _set_progress_max(achievement_id, clampi(stat_value, 0, target))


func _get_stat_value(stat_key: String) -> int:
	var key_parts: PackedStringArray = stat_key.split(".", false, 1)
	if key_parts.size() != 2:
		return 0
	return GameStatsManager.get_counter(key_parts[0], key_parts[1])


func _can_evaluate(achievement_id: String, definition: Dictionary) -> bool:
	if not _progress.has(achievement_id):
		return false
	if bool(_progress[achievement_id].get("unlocked", false)):
		return false
	var prereq: String = str(definition.get("prerequisite_id", ""))
	if prereq == "":
		return true
	return bool(_progress.get(prereq, {}).get("unlocked", false))


func _set_progress_max(achievement_id: String, value: int) -> bool:
	if not _progress.has(achievement_id):
		return false
	var entry: Dictionary = _progress[achievement_id]
	if bool(entry.get("unlocked", false)):
		return false
	var target: int = int(entry.get("target_value", 1))
	var current_value: int = int(entry.get("current_value", 0))
	var next_value: int = clampi(maxi(current_value, value), 0, target)
	if next_value == current_value:
		return false
	entry["current_value"] = next_value
	if next_value >= target:
		_unlock_achievement(achievement_id, entry)
		return true
	_progress[achievement_id] = entry
	return true


func _set_progress_exact(achievement_id: String, value: int) -> bool:
	if not _progress.has(achievement_id):
		return false
	var entry: Dictionary = _progress[achievement_id]
	if bool(entry.get("unlocked", false)):
		return false
	var target: int = int(entry.get("target_value", 1))
	var next_value: int = clampi(value, 0, target)
	if next_value == int(entry.get("current_value", 0)):
		return false
	entry["current_value"] = next_value
	if next_value >= target:
		_unlock_achievement(achievement_id, entry)
		return true
	_progress[achievement_id] = entry
	return true


func _unlock_achievement(achievement_id: String, entry: Dictionary) -> void:
	entry["unlocked"] = true
	entry["unlocked_at"] = Time.get_unix_time_from_system()
	_progress[achievement_id] = entry
	var definition: Dictionary = ACHIEVEMENT_DEFINITIONS.get(achievement_id, {}).duplicate(true)
	achievement_unlocked.emit(achievement_id, definition)
	definition["platform_payload"] = {
		"id": achievement_id,
		"title": definition.get("title", ""),
		"tier": definition.get("tier", "Bronze"),
		"reward_type": definition.get("reward_type", ""),
		"reward_id": definition.get("reward_id", ""),
		"target_value": int(definition.get("target_value", 1)),
		"unlocked_at": int(entry.get("unlocked_at", 0)),
	}
	_ensure_presenter()
	_presenter.present_unlock(definition)


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
