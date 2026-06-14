extends Control
class_name GameScreen

## Base class for all Game Screens in the Collection.
## Handles the shared lifecycle ceremony: crash reporting, settings navigation,
## theme, safe area, help button, session persistence, replay, and analytics.
## Subclasses override virtual methods to provide game-specific behavior.
##
## Session ceremony is centralised in begin_session(). Subclasses call
## begin_session() (new game) or begin_session(saved_data) (resume) and
## implement the hooks below.


# --- Session state (owned by base) ---

var elapsed_time: float = 0.0
var random_seed: int = 0
var replay_id: String = ""

@onready var timer_label: Label = %TimerLabel


# --- Virtual methods (lifecycle / serialisation) ---

## Return the game_id used for saves, stats, analytics, replay.
func _get_game_id() -> String:
	return ""


## Return the scene path for this game screen (used for settings return).
func _get_scene_path() -> String:
	return ""


## Serialize the current game state for saving.
func _serialize_state() -> Dictionary:
	return {}


## Restore game state from a saved Dictionary.
func _deserialize_state(_data: Dictionary) -> void:
	pass


## Return true if the game has been explicitly initialized (from menu).
## Used to decide whether auto-resume should fire.
func _is_initialized() -> bool:
	return false


## Return true if the game is completed (don't save completed games).
func _is_completed() -> bool:
	return false


## Return crash state dictionary for CrashReporter.
func _get_crash_state() -> Dictionary:
	return {"game": _get_game_id()}


## Return the help topic string for HowToPlay.
func _get_help_topic() -> String:
	return _get_game_id()


## Called after the base lifecycle setup is complete.
## Subclass should wire its own buttons and signals here.
func _on_game_screen_ready() -> void:
	pass


## Apply visual theme. Called on ready and on theme changes.
func _apply_game_theme() -> void:
	pass


# --- Virtual methods (session ceremony hooks) ---

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


## Return event parameters for the "game_started" analytics event.
## Called only for new games.
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


# --- Lifecycle ---

func _ready() -> void:
	# Crash reporting
	CrashReporter.register_state_provider(_get_crash_state)
	CrashReporter.register_user_action("%s_screen_opened" % _get_game_id())

	# Settings button
	var settings_btn := _find_settings_button()
	if settings_btn:
		settings_btn.pressed.connect(_on_settings_pressed)

	# Help button
	_setup_help_button()

	# Theme
	_apply_game_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_game_theme())

	# Safe area
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)

	# Let subclass do its own setup
	_on_game_screen_ready()

	# Auto-resume (deferred so subclass _ready and explicit init can happen first)
	_try_auto_resume.call_deferred()


func _exit_tree() -> void:
	CrashReporter.unregister_state_provider(_get_crash_state)


func _process(delta: float) -> void:
	if _should_tick_timer():
		elapsed_time += delta
		if timer_label:
			if PlatformSettings.show_timer:
				timer_label.text = _format_time(elapsed_time)
				timer_label.visible = true
			else:
				timer_label.visible = false


# --- Session ceremony ---

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

	# _setup_game() runs here so game state (board, seed derivation for legacy
	# saves) is fully initialised before ReplayRecorder.start_session() below.
	_setup_game(saved_data)

	if not is_resuming or not ReplayRecorder.has_active_session():
		replay_id = ReplayRecorder.start_session(
				game_id, random_seed, _get_initial_state(), _get_settings_snapshot())

	if not is_resuming:
		_increment_stats()
		AnalyticsManager.log_event("game_started", _get_analytics_params())

	AchievementManager.track_game_started(game_id)
	_save_current_state()


# --- Save / Resume ---

func save_progress() -> void:
	if _is_completed():
		return
	GameSaveManager.save_game(_get_game_id(), _serialize_state())


func clear_save() -> void:
	GameSaveManager.clear_save(_get_game_id())


func _try_auto_resume() -> void:
	if _is_initialized():
		return
	if GameSaveManager.has_saved_game(_get_game_id()):
		var data := GameSaveManager.load_game(_get_game_id())
		if not data.is_empty():
			_deserialize_state(data)


## Save current game state to disk and flush the active replay.
## Defined here so subclasses do not need to repeat the two-line body.
func _save_current_state() -> void:
	save_progress()
	ReplayRecorder.flush_active_replay()


# --- Navigation ---

func _on_settings_pressed() -> void:
	var SettingsScreen := load("res://scripts/settings_screen.gd")
	SettingsScreen.return_scene = _get_scene_path()
	SceneTransition.transition_to(Scenes.SETTINGS)


func navigate_to_menu(menu_scene: String) -> void:
	SceneTransition.transition_to(menu_scene)


# --- Help Button ---

func _setup_help_button() -> void:
	var settings_btn := _find_settings_button()
	if not settings_btn:
		return
	var topic := _get_help_topic()
	if topic.is_empty():
		return
	var btn := Button.new()
	btn.text = "?"
	btn.custom_minimum_size = Vector2(36, 0)
	btn.pressed.connect(func() -> void: HowToPlay.show_for(self, topic))
	var parent := settings_btn.get_parent()
	if parent:
		parent.add_child(btn)
		parent.move_child(btn, settings_btn.get_index())


# --- Internals ---

func _find_settings_button() -> Button:
	return get_node_or_null("%SettingsButton") as Button


# --- Utilities ---

func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%d:%02d" % [mins, secs]


func _create_session_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(Time.get_ticks_usec() ^ rng.randi())
