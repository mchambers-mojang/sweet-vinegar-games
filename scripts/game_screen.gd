extends Control

## Base class for puzzle game screens.
##
## Provides the session-start ceremony (crash reporting, stats, replay, achievements,
## analytics, and auto-save) via the begin_session() template method, and owns the
## elapsed-time counter and timer-label update loop.
##
## Subclasses must implement:
##   _get_game_id() -> String
##   _get_initial_state() -> Dictionary
##   _get_settings_snapshot() -> Dictionary
##   _setup_game(saved_data: Dictionary) -> void
##   _increment_stats() -> void
##   _get_analytics_params() -> Dictionary
##   _should_tick_timer() -> bool
##   _save_current_state() -> void
##
## Optional overrides:
##   _get_start_crash_params() -> Dictionary
##   _get_resume_crash_params(saved_data: Dictionary) -> Dictionary

var elapsed_time: float = 0.0
var random_seed: int = 0
var replay_id: String = ""

@onready var timer_label: Label = %TimerLabel


# ---------------------------------------------------------------------------
# Session ceremony
# ---------------------------------------------------------------------------

## Orchestrates the session-start ceremony. Subclasses call this at the end of
## start_new_game() and resume_game() after setting their game-specific variables.
## Pass an empty dictionary (the default) for a new game, or the full save
## dictionary for a resume.
func begin_session(saved_data: Dictionary = {}) -> void:
	var is_resuming := not saved_data.is_empty()
	var game_id := _get_game_id()

	if is_resuming:
		random_seed = int(saved_data.get("random_seed", 0))
		elapsed_time = saved_data.get("elapsed_time", 0.0)
		replay_id = str(saved_data.get("replay_id", ""))
		CrashReporter.register_user_action(
				game_id + "_resume_game",
				_get_resume_crash_params(saved_data))
	else:
		random_seed = _create_session_seed()
		elapsed_time = 0.0
		replay_id = ""
		CrashReporter.register_user_action(
				game_id + "_start_new_game",
				_get_start_crash_params())

	_setup_game(saved_data)

	if not is_resuming or not ReplayManager.has_active_session():
		replay_id = ReplayManager.start_session(
				game_id, random_seed, _get_initial_state(), _get_settings_snapshot())

	if not is_resuming:
		_increment_stats()
		AnalyticsManager.log_event("game_started", _get_analytics_params())

	AchievementManager.track_game_started(game_id)
	_save_current_state()


# ---------------------------------------------------------------------------
# Timer
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _should_tick_timer():
		elapsed_time += delta
		if SettingsManager.show_timer:
			timer_label.text = _format_time(elapsed_time)
			timer_label.visible = true
		else:
			timer_label.visible = false


func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%d:%02d" % [mins, secs]


func _create_session_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(Time.get_ticks_usec() ^ rng.randi())


# ---------------------------------------------------------------------------
# Virtual hooks — implement in subclass
# ---------------------------------------------------------------------------

## Return the game identifier string used in analytics, replay, and crash reports.
func _get_game_id() -> String:
	return ""


## Return the board / puzzle state dict for the replay session header.
## Called after _setup_game(), so game state is fully initialised.
func _get_initial_state() -> Dictionary:
	return {}


## Return a snapshot of relevant settings for the replay session header.
## Called after _setup_game(), so game state is fully initialised.
func _get_settings_snapshot() -> Dictionary:
	return {}


## Perform the game-specific board initialisation for a new or resumed session.
## Called by begin_session() after elapsed_time, random_seed, and replay_id are set.
## saved_data is empty for a new game, or the full save dict for a resume.
func _setup_game(_saved_data: Dictionary) -> void:
	pass


## Increment game-specific play-count statistics. Called only for new games.
func _increment_stats() -> void:
	pass


## Return event parameters for the "game_started" analytics event. Called only for
## new games.
func _get_analytics_params() -> Dictionary:
	return {}


## Return extra metadata for the crash action registered on start_new_game.
func _get_start_crash_params() -> Dictionary:
	return {}


## Return extra metadata for the crash action registered on resume_game.
func _get_resume_crash_params(_saved_data: Dictionary) -> Dictionary:
	return {}


## Return true while the timer should advance and the timer label should update.
## Override to add pause / game-over guards (e.g. return not is_completed and not is_paused).
func _should_tick_timer() -> bool:
	return true


## Persist the current game state to disk. Called by begin_session() after all
## ceremony is complete.
func _save_current_state() -> void:
	pass
