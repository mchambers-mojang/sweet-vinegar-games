class_name SessionController
extends RefCounted

## Orchestrates all platform services for a single game session.
##
## GameScreen instantiates one SessionController in _ready() and stores it as
## `session`. All autoload calls that were previously scattered across game
## screens go through this interface instead, so each screen only imports one
## symbol instead of ten.
##
## Pass mock objects to the constructor for unit testing — no scene tree needed.


# --- Injected dependencies (default to global autoloads) ---

var _recorder: Object
var _storage: Object
var _crash: Object
var _analytics: Object
var _achievements: Object
var _saves: Object
var _stats: Object
var _sound: Object
var _haptic: Object


func _init(
	p_recorder: Object = null,
	p_storage: Object = null,
	p_crash: Object = null,
	p_analytics: Object = null,
	p_achievements: Object = null,
	p_saves: Object = null,
	p_stats: Object = null,
	p_sound: Object = null,
	p_haptic: Object = null
) -> void:
	_recorder = p_recorder if p_recorder != null else ReplayRecorder
	_storage = p_storage if p_storage != null else ReplayStorage
	_crash = p_crash if p_crash != null else CrashCollector
	_analytics = p_analytics if p_analytics != null else AnalyticsManager
	_achievements = p_achievements if p_achievements != null else AchievementEngine
	_saves = p_saves if p_saves != null else GameSaveManager
	_stats = p_stats if p_stats != null else GameStatsManager
	_sound = p_sound if p_sound != null else SoundManager
	_haptic = p_haptic if p_haptic != null else HapticManager


# === Crash / State ===

func register_crash_state(provider: Callable) -> void:
	_crash.register_state_provider(provider)


func unregister_crash_state(provider: Callable) -> void:
	_crash.unregister_state_provider(provider)


func register_user_action(action: String, metadata: Dictionary = {}) -> void:
	_crash.register_user_action(action, metadata)


## Alias for register_user_action — shorter form used by some game screens.
func user_action(action: String, metadata: Dictionary = {}) -> void:
	_crash.register_user_action(action, metadata)


# === Replay ===

func start_replay(game_mode: String, seed: int, initial_state: Dictionary, settings_snapshot: Dictionary = {}) -> String:
	return _recorder.start_session(game_mode, seed, initial_state, settings_snapshot)


func has_active_replay() -> bool:
	return _recorder.has_active_session()


func record_input(timestamp: float, event_type: String, payload: Dictionary = {}) -> void:
	_recorder.record_input(timestamp, event_type, payload)


func finish_replay(outcome: String, action_count: int, elapsed_time: float, extra: Dictionary = {}) -> Dictionary:
	return _recorder.finish_session(outcome, action_count, elapsed_time, extra)


func save_completed_replay(completed: Dictionary) -> void:
	_storage.save_replay(completed)


func bookmark_latest_replay() -> bool:
	return _storage.bookmark_latest_replay()


## Alias for bookmark_latest_replay — shorter form used by some game screens.
func bookmark_replay() -> bool:
	return _storage.bookmark_latest_replay()


func flush_replay() -> void:
	_recorder.flush_active_replay()


# === Analytics ===

func log_event(event_name: String, params: Dictionary = {}) -> void:
	_analytics.log_event(event_name, params)


# === Achievements ===

func track_achievement(event_key: String, value: int = 1) -> void:
	_achievements.track(event_key, value)


func check_achievements() -> void:
	_achievements.check_stats()


# === Stats ===

func record_stats(game_id: String, data: Dictionary) -> void:
	_stats.record(game_id, data)


func increment_stats_counter(game_id: String, key: String, amount: int = 1) -> void:
	_stats.increment_counter(game_id, key, amount)


func set_stats_counter(game_id: String, key: String, value: int) -> void:
	_stats.set_counter(game_id, key, value)


func get_stats_counter(game_id: String, key: String) -> int:
	return _stats.get_counter(game_id, key)


# === Saves ===

func save_progress(game_id: String, data: Dictionary) -> void:
	_saves.save_game(game_id, data)


func clear_save(game_id: String) -> void:
	_saves.clear_save(game_id)


func has_saved_game(game_id: String) -> bool:
	return _saves.has_saved_game(game_id)


func load_game(game_id: String) -> Dictionary:
	return _saves.load_game(game_id)


# === Sound ===

func play_sound_place() -> void:
	_sound.play_place()


func play_sound_win() -> void:
	_sound.play_win()


func play_sound_pencil() -> void:
	_sound.play_pencil()


func play_sound_erase() -> void:
	_sound.play_erase()


func play_sound_error() -> void:
	_sound.play_error()


func play_sound_select() -> void:
	_sound.play_select()


func play_sound_unit_complete() -> void:
	_sound.play_unit_complete()


# === Haptics ===

func vibrate_light() -> void:
	_haptic.vibrate_light()


func vibrate_medium() -> void:
	_haptic.vibrate_medium()


func vibrate_heavy() -> void:
	_haptic.vibrate_heavy()


func vibrate_error() -> void:
	_haptic.vibrate_error()


func vibrate_success() -> void:
	_haptic.vibrate_success()
