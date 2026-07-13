extends GutTest

## Unit tests for GameScreen DI constructor and session ceremony.
##
## All tests use lightweight inner-class mocks; no scene tree or autoloads needed.
## GameScreen._init() accepts 9 optional dependency objects, so tests simply
## pass mock instances and call begin_session() / save_progress() / clear_save()
## directly on the node — _ready() is never required.


# ---------------------------------------------------------------------------
# Mock helpers (identical to the ones that previously lived in
# test_session_controller.gd, moved here now that the DI lives in GameScreen)
# ---------------------------------------------------------------------------

class MockRecorder:
	var started := false
	var last_game_mode := ""
	var last_seed := 0
	var inputs: Array = []
	var finished := false
	var flushed := false

	func start_session(game_mode: String, seed: int, _initial: Dictionary, _settings: Dictionary = {}) -> String:
		started = true
		last_game_mode = game_mode
		last_seed = seed
		return "mock-replay-id"

	func has_active_session() -> bool:
		return started and not finished

	func record_input(timestamp: float, event_type: String, payload: Dictionary = {}) -> void:
		inputs.append({"t": timestamp, "type": event_type, "payload": payload})

	func finish_session(outcome: String, _count: int, _elapsed: float, _extra: Dictionary = {}) -> Dictionary:
		finished = true
		return {"outcome": outcome, "mock": true}

	func flush_active_replay() -> void:
		flushed = true


class MockStorage:
	var saved: Array = []
	var bookmarked := false

	func save_replay(completed: Dictionary) -> void:
		saved.append(completed)

	func bookmark_latest_replay() -> bool:
		bookmarked = true
		return true


class MockCrash:
	var providers: Array = []
	var user_actions: Array = []

	func register_state_provider(provider: Callable) -> void:
		providers.append(provider)

	func unregister_state_provider(provider: Callable) -> void:
		providers.erase(provider)

	func register_user_action(action: String, metadata: Dictionary = {}) -> void:
		user_actions.append({"action": action, "meta": metadata})


class MockAnalytics:
	var events: Array = []

	func log_event(name: String, params: Dictionary = {}) -> void:
		events.append({"name": name, "params": params})


class MockAchievements:
	var calls: Array = []

	func track(event_key: String, value: int = 1) -> void:
		calls.append(["track", event_key, value])

	func check_stats() -> void:
		calls.append(["check_stats"])


class MockSaves:
	var data: Dictionary = {}

	func save_game(game_id: String, state: Dictionary) -> void:
		data[game_id] = state

	func clear_save(game_id: String) -> void:
		data.erase(game_id)

	func has_saved_game(game_id: String) -> bool:
		return data.has(game_id)

	func load_game(game_id: String) -> Dictionary:
		return data.get(game_id, {})


class MockStats:
	var counters: Dictionary = {}
	var records: Array = []

	func record(game_id: String, entry: Dictionary) -> void:
		records.append({"game": game_id, "entry": entry})

	func increment_counter(game_id: String, key: String, amount: int = 1) -> void:
		var full_key := game_id + "." + key
		counters[full_key] = counters.get(full_key, 0) + amount

	func set_counter(game_id: String, key: String, value: int) -> void:
		counters[game_id + "." + key] = value

	func get_counter(game_id: String, key: String) -> int:
		return counters.get(game_id + "." + key, 0)


class MockSound:
	var calls: Array = []

	func play_place() -> void:
		calls.append("play_place")

	func play_win() -> void:
		calls.append("play_win")

	func play_pencil() -> void:
		calls.append("play_pencil")

	func play_erase() -> void:
		calls.append("play_erase")

	func play_error() -> void:
		calls.append("play_error")

	func play_select() -> void:
		calls.append("play_select")

	func play_unit_complete() -> void:
		calls.append("play_unit_complete")


class MockHaptic:
	var calls: Array = []

	func vibrate_light() -> void:
		calls.append("vibrate_light")

	func vibrate_medium() -> void:
		calls.append("vibrate_medium")

	func vibrate_heavy() -> void:
		calls.append("vibrate_heavy")

	func vibrate_error() -> void:
		calls.append("vibrate_error")

	func vibrate_success() -> void:
		calls.append("vibrate_success")

	func stop() -> void:
		calls.append("stop")


# ---------------------------------------------------------------------------
# Minimal concrete GameScreen subclass for testing
# ---------------------------------------------------------------------------

class TestScreen extends "res://scripts/game_screen.gd":
	var game_id := "test_game"
	var initialized := true

	func _get_game_id() -> String:
		return game_id

	func _serialize_state() -> Dictionary:
		return {"dummy": true}

	func _is_initialized() -> bool:
		return initialized


# ---------------------------------------------------------------------------
# Test fixtures
# ---------------------------------------------------------------------------

var recorder: MockRecorder
var storage: MockStorage
var crash: MockCrash
var analytics: MockAnalytics
var achievements: MockAchievements
var saves: MockSaves
var stats: MockStats
var sound: MockSound
var haptic: MockHaptic
var screen: TestScreen


func before_each() -> void:
	recorder = MockRecorder.new()
	storage = MockStorage.new()
	crash = MockCrash.new()
	analytics = MockAnalytics.new()
	achievements = MockAchievements.new()
	saves = MockSaves.new()
	stats = MockStats.new()
	sound = MockSound.new()
	haptic = MockHaptic.new()
	screen = TestScreen.new(
		recorder, storage, crash, analytics, achievements, saves, stats, sound, haptic
	)


func after_each() -> void:
	screen.free()


# ---------------------------------------------------------------------------
# DI wiring — verify _init() stores the injected mocks
# ---------------------------------------------------------------------------

func test_init_stores_recorder() -> void:
	assert_eq(screen._recorder, recorder)


func test_init_stores_storage() -> void:
	assert_eq(screen._storage, storage)


func test_init_stores_crash() -> void:
	assert_eq(screen._crash, crash)


func test_init_stores_analytics() -> void:
	assert_eq(screen._analytics, analytics)


func test_init_stores_achievements() -> void:
	assert_eq(screen._achievements, achievements)


func test_init_stores_saves() -> void:
	assert_eq(screen._saves, saves)


func test_init_stores_stats() -> void:
	assert_eq(screen._stats, stats)


func test_init_stores_sound() -> void:
	assert_eq(screen._sound, sound)


func test_init_stores_haptic() -> void:
	assert_eq(screen._haptic, haptic)


# ---------------------------------------------------------------------------
# begin_session() — new game
# ---------------------------------------------------------------------------

func test_begin_session_new_starts_replay() -> void:
	screen.begin_session()
	assert_true(recorder.started)
	assert_eq(recorder.last_game_mode, "test_game")


func test_begin_session_new_sets_replay_id() -> void:
	screen.begin_session()
	assert_eq(screen.replay_id, "mock-replay-id")


func test_begin_session_new_registers_crash_action() -> void:
	screen.begin_session()
	var actions: Array = crash.user_actions.map(func(e: Dictionary) -> String: return e["action"])
	assert_true(actions.has("test_game_start_new_game"))


func test_begin_session_new_increments_general_games_played() -> void:
	screen.begin_session()
	assert_eq(stats.counters.get("general.games_played", 0), 1)


func test_begin_session_new_tracks_achievement() -> void:
	screen.begin_session()
	var tracked: Array = achievements.calls.filter(
		func(c: Array) -> bool: return c[0] == "track"
	)
	assert_eq(tracked.size(), 1)
	assert_eq(tracked[0][1], "general.game_started.test_game")


func test_begin_session_new_checks_achievements() -> void:
	screen.begin_session()
	var checked: Array = achievements.calls.filter(
		func(c: Array) -> bool: return c[0] == "check_stats"
	)
	assert_eq(checked.size(), 1)


func test_begin_session_new_flushes_replay() -> void:
	screen.begin_session()
	assert_true(recorder.flushed)


func test_begin_session_new_saves_progress() -> void:
	screen.begin_session()
	assert_true(saves.data.has("test_game"))


func test_begin_session_stops_when_setup_does_not_initialize() -> void:
	screen.initialized = false

	screen.begin_session()

	assert_push_error("setup failed to initialize game state")
	assert_false(recorder.started)
	assert_false(saves.data.has("test_game"))
	assert_eq(stats.counters.get("general.games_played", 0), 0)


# ---------------------------------------------------------------------------
# begin_session() — resume
# ---------------------------------------------------------------------------

func test_begin_session_resume_restores_seed() -> void:
	var saved_data := {"random_seed": 12345, "elapsed_time": 30.0, "replay_id": "old-id"}
	screen.begin_session(saved_data)
	assert_eq(screen.random_seed, 12345)


func test_begin_session_resume_restores_elapsed_time() -> void:
	var saved_data := {"random_seed": 1, "elapsed_time": 99.5, "replay_id": ""}
	screen.begin_session(saved_data)
	assert_eq(screen.elapsed_time, 99.5)


func test_begin_session_resume_registers_resume_crash_action() -> void:
	var saved_data := {"random_seed": 1, "elapsed_time": 0.0, "replay_id": ""}
	screen.begin_session(saved_data)
	var actions: Array = crash.user_actions.map(func(e: Dictionary) -> String: return e["action"])
	assert_true(actions.has("test_game_resume_game"))


func test_begin_session_resume_does_not_increment_games_played() -> void:
	var saved_data := {"random_seed": 1, "elapsed_time": 0.0, "replay_id": ""}
	screen.begin_session(saved_data)
	assert_eq(stats.counters.get("general.games_played", 0), 0)


func test_begin_session_resume_starts_new_replay_when_none_active() -> void:
	var saved_data := {"random_seed": 1, "elapsed_time": 0.0, "replay_id": "old"}
	screen.begin_session(saved_data)
	assert_true(recorder.started)


func test_begin_session_resume_skips_replay_when_already_active() -> void:
	# Pre-start a replay so has_active_session() returns true
	recorder.started = true
	var saved_data := {"random_seed": 1, "elapsed_time": 5.0, "replay_id": "existing"}
	screen.begin_session(saved_data)
	# replay_id should be kept from saved_data, not replaced
	assert_eq(screen.replay_id, "existing")


# ---------------------------------------------------------------------------
# save_progress()
# ---------------------------------------------------------------------------

func test_save_progress_delegates_to_saves() -> void:
	screen.save_progress()
	assert_true(saves.data.has("test_game"))


func test_save_progress_uses_serialized_state() -> void:
	screen.save_progress()
	assert_eq(saves.data["test_game"], {"dummy": true})


# ---------------------------------------------------------------------------
# clear_save()
# ---------------------------------------------------------------------------

func test_clear_save_delegates_to_saves() -> void:
	saves.data["test_game"] = {"dummy": true}
	screen.clear_save()
	assert_false(saves.data.has("test_game"))


func test_all_game_screen_scripts_compile() -> void:
	var paths := [
		"res://scripts/blockudoku/blockudoku_game_screen.gd",
		"res://scripts/shikaku/shikaku_game_screen.gd",
		"res://scripts/sudoku/sudoku_game_screen.gd",
		"res://carom/scripts/carom_arena.gd",
	]
	for path in paths:
		var script := load(path) as GDScript
		assert_not_null(script, "%s should load" % path)
		assert_true(script.can_instantiate(), "%s should compile" % path)


# ---------------------------------------------------------------------------
# Generation-failure redirect: suppress auto-resume and ceremony
# ---------------------------------------------------------------------------

## Unsatisfiable constraint — every value at index 0 is illegal, so no
## valid 9x9 grid can be produced.  Used to force init_new_game() failure.
class BlockAllAtIndexConstraint extends SudokuConstraint:
	func is_valid(grid: Array[int], index: int, value: int) -> bool:
		return index != 0

	func get_id() -> String:
		return "block_all_0"


## SudokuGameScreen subclass that captures the abort-navigation call
## without touching SceneTransition / scene tree.
class TestSudokuFailScreen extends "res://scripts/sudoku/sudoku_game_screen.gd":
	var abort_called := false

	func _abort_generation_failure() -> void:
		abort_called = true


func test_suppress_auto_resume_flag_prevents_try_auto_resume() -> void:
	# Base-class guarantee: _suppress_auto_resume blocks _try_auto_resume.
	saves.data["test_game"] = {"dummy": true}
	screen._suppress_auto_resume = true
	screen.initialized = false

	screen._try_auto_resume()

	assert_false(screen._is_initialized(),
			"_try_auto_resume must not initialize the screen when _suppress_auto_resume is true")
	assert_false(saves.data.has("test_game") and saves.data["test_game"] == {},
			"_try_auto_resume must not clear saved data")


func test_failed_generation_suppresses_auto_resume_and_no_ceremony() -> void:
	# Integration regression: launching through the real SudokuGameScreen /
	# SudokuLogic setup path with an unsatisfiable constraint must:
	#   • set _suppress_auto_resume so saved data cannot be auto-resumed, and
	#   • NOT run any session ceremony (no replay, stats, or save writes).
	# Saved game data is planted to prove _try_auto_resume won't pick it up.

	var mock_recorder := MockRecorder.new()
	var mock_saves := MockSaves.new()
	var mock_stats := MockStats.new()
	# Plant a saved game; _try_auto_resume would normally resume this.
	mock_saves.data["sudoku"] = {
		"difficulty": 0, "random_seed": 1, "elapsed_time": 5.0, "replay_id": "old"
	}

	var s := TestSudokuFailScreen.new(
		mock_recorder, MockStorage.new(), MockCrash.new(), MockAnalytics.new(),
		MockAchievements.new(), mock_saves, mock_stats, MockSound.new(), MockHaptic.new()
	)
	s.constraints = [BlockAllAtIndexConstraint.new()]

	# Trigger the real new-game path: begin_session → _setup_game → init_new_game fails.
	s.start_new_game(0)

	# begin_session() emits a push_error when _is_initialized() is false.
	assert_push_error("setup failed to initialize game state")

	# No ceremony must have run.
	assert_false(mock_recorder.started,
			"replay must not be started after failed generation")
	assert_eq(mock_stats.counters.get("sudoku.games_started", 0), 0,
			"games_started stat must not be incremented after failed generation")
	assert_eq(mock_stats.counters.get("general.games_played", 0), 0,
			"general games_played stat must not be incremented after failed generation")

	# abort handler must have been triggered (menu redirect requested).
	assert_true(s.abort_called,
			"_abort_generation_failure must be called when generation fails")

	# auto-resume must be suppressed.
	assert_true(s._suppress_auto_resume,
			"_suppress_auto_resume must be true after a failed generation")

	# _try_auto_resume must not resume the planted save.
	s._try_auto_resume()
	assert_false(s._is_initialized(),
			"_try_auto_resume must not resume the game when suppressed after failed launch")

	s.free()
