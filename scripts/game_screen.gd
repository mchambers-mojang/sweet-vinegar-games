extends Control
class_name GameScreen

const TimeFormat := preload("res://scripts/utils/time_format.gd")

## Base class for all Game Screens in the Collection.
## Handles the shared lifecycle ceremony: crash reporting, settings navigation,
## theme, safe area, help button, session persistence, replay, and analytics.
## Subclasses override virtual methods to provide game-specific behavior.
##
## Session ceremony is centralised in begin_session(). Subclasses call
## begin_session() (new game) or begin_session(saved_data) (resume) and
## implement the hooks below.
##
## All platform-service autoload calls (replay, crash, analytics, stats, save,
## sound, haptics) go through protected dependency variables rather than
## directly to the autoloads. Pass mock objects to _init() for unit testing —
## no scene tree needed.


# --- Injected dependencies (default to global autoloads) ---
# _recorder and _storage both default to ReplaySystem (merged autoload).
# _sound and _haptic both default to FeedbackManager (merged autoload).
# They remain separate parameters so unit tests can inject fine-grained mocks
# for recording behaviour vs. persistence, and sound vs. haptic, independently.

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
	_recorder = p_recorder if p_recorder != null else ReplaySystem
	_storage = p_storage if p_storage != null else ReplaySystem
	_crash = p_crash if p_crash != null else CrashCollector
	_analytics = p_analytics if p_analytics != null else AnalyticsManager
	_achievements = p_achievements if p_achievements != null else AchievementEngine
	_saves = p_saves if p_saves != null else GameSaveManager
	_stats = p_stats if p_stats != null else GameStatsManager
	_sound = p_sound if p_sound != null else FeedbackManager
	_haptic = p_haptic if p_haptic != null else FeedbackManager


# --- Session state (owned by base) ---

var elapsed_time: float = 0.0
var random_seed: int = 0
var replay_id: String = ""

# Cached save adapter — set in _ready() via _get_save_adapter().
# null for games that have not yet migrated to the adapter contract.
var _save_adapter: GameSaveAdapter = null

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


## Start a new game with the provided launch parameters.
## Called by GameMenu after the scene is added to the tree.
## Subclasses implement this to extract the relevant fields from params
## (e.g. params.option_value for difficulty or grid size) and call begin_session().
func launch(_params: LaunchParams) -> void:
	pass


## Return true if the game has been explicitly initialized (from menu).
## Used to decide whether auto-resume should fire.
func _is_initialized() -> bool:
	return false


## Return true if the game is completed (don't save completed games).
func _is_completed() -> bool:
	return false


## Return crash state dictionary for CrashCollector.
func _get_crash_state() -> Dictionary:
	return {"game": _get_game_id()}


## Return the help topic string for HowToPlay.
func _get_help_topic() -> String:
	return _get_game_id()


## Return a GameSaveAdapter for this game, or null to fall back to direct
## GameSaveManager calls.  Override in concrete game screens.
func _get_save_adapter() -> GameSaveAdapter:
	return null


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


## Return the difficulty level for the game_started domain event.
## Override in game screens with explicit difficulty (e.g. Sudoku).
## Returns -1 for games without an explicit difficulty level.
func _get_difficulty() -> int:
	return -1


# --- Lifecycle ---

func _ready() -> void:
	# Cache the save adapter (null for games not yet using the adapter contract)
	_save_adapter = _get_save_adapter()

	# Crash reporting
	_crash.register_state_provider(_get_crash_state)
	_crash.register_user_action("%s_screen_opened" % _get_game_id())

	# Settings button
	var settings_btn := _find_settings_button()
	if settings_btn:
		settings_btn.pressed.connect(_on_settings_pressed)

	# Help button
	_setup_help_button()

	# Theme
	_apply_game_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_game_theme())

	# Let subclass do its own setup
	_on_game_screen_ready()

	# Auto-resume (deferred so subclass _ready and explicit init can happen first)
	_try_auto_resume.call_deferred()


func _exit_tree() -> void:
	_crash.unregister_state_provider(_get_crash_state)


func _process(delta: float) -> void:
	if _should_tick_timer():
		elapsed_time += delta
		if timer_label:
			if PlatformSettings.show_timer:
				timer_label.text = TimeFormat.format_time(elapsed_time)
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
		_crash.register_user_action(
				game_id + "_resume_game",
				_get_resume_crash_params(saved_data))
	else:
		random_seed = _create_session_seed()
		elapsed_time = 0.0
		replay_id = ""
		_crash.register_user_action(
				game_id + "_start_new_game",
				_get_start_crash_params())

	# _setup_game() runs here so game state (board, seed derivation for legacy
	# saves) is fully initialised before _recorder.start_session() below.
	_setup_game(saved_data)
	if not _is_initialized():
		push_error("GameScreen: %s setup failed to initialize game state" % game_id)
		return

	if not is_resuming or not _recorder.has_active_session():
		replay_id = _recorder.start_session(
				game_id, random_seed, _get_initial_state(), _get_settings_snapshot())

	if not is_resuming:
		_increment_stats()
		_stats.increment_counter("general", "games_played")
		GameEvents.game_started.emit(game_id, _get_difficulty(), _get_analytics_params())

	_achievements.track("general.game_started.%s" % game_id)
	_achievements.check_stats()
	_save_current_state()


# --- Save / Resume ---

func save_progress() -> void:
	if _is_completed():
		return
	if _save_adapter:
		_save_adapter.save(_serialize_state())
	else:
		_saves.save_game(_get_game_id(), _serialize_state())


func clear_save() -> void:
	if _save_adapter:
		_save_adapter.clear()
	else:
		_saves.clear_save(_get_game_id())


func _try_auto_resume() -> void:
	if _is_initialized():
		return
	if _save_adapter:
		var data := _save_adapter.restore_if_resumable()
		if not data.is_empty():
			_deserialize_state(data)
	elif _saves.has_saved_game(_get_game_id()):
		var data: Dictionary = _saves.load_game(_get_game_id())
		if not data.is_empty():
			_deserialize_state(data)


## Save current game state to disk and flush the active replay.
## Defined here so subclasses do not need to repeat the two-line body.
func _save_current_state() -> void:
	save_progress()
	_recorder.flush_active_replay()


# --- Navigation ---

func _on_settings_pressed() -> void:
	var SettingsScreen := load("res://scripts/settings_screen.gd")
	SettingsScreen.return_scene = _get_scene_path()
	SceneTransition.push(Scenes.SETTINGS)


func navigate_to_menu(menu_scene: String) -> void:
	SceneTransition.navigate(menu_scene)


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


func _create_session_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(Time.get_ticks_usec() ^ rng.randi())
