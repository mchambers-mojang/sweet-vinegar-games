extends GutTest

## Unit tests for SessionController — lifecycle delegation and dependency injection.
##
## All tests use lightweight inner-class mocks; no scene tree or autoloads needed.

const SessionControllerScript := preload("res://scripts/session/session_controller.gd")


# ---------------------------------------------------------------------------
# Mock helpers
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

	func track_game_started(game_id: String) -> void:
		calls.append(["track_game_started", game_id])

	func track_game_won(game_id: String, metadata: Dictionary = {}) -> void:
		calls.append(["track_game_won", game_id, metadata])

	func track_streak_broken() -> void:
		calls.append(["track_streak_broken"])

	func track_blockudoku_clear(n: int) -> void:
		calls.append(["track_blockudoku_clear", n])

	func track_blockudoku_combo(n: int) -> void:
		calls.append(["track_blockudoku_combo", n])

	func track_blockudoku_game_played(score: int) -> void:
		calls.append(["track_blockudoku_game_played", score])

	func track_shikaku_won(size: int, time: float) -> void:
		calls.append(["track_shikaku_won", size, time])


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
var session: SessionControllerScript


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
	session = SessionControllerScript.new(
		recorder, storage, crash, analytics, achievements, saves, stats, sound, haptic
	)


# ---------------------------------------------------------------------------
# Replay
# ---------------------------------------------------------------------------

func test_start_replay_delegates_to_recorder() -> void:
	var id: String = session.start_replay("sudoku", 42, {"board": []})
	assert_true(recorder.started)
	assert_eq(recorder.last_game_mode, "sudoku")
	assert_eq(recorder.last_seed, 42)
	assert_eq(id, "mock-replay-id")


func test_has_active_replay_true_after_start() -> void:
	session.start_replay("blockudoku", 1, {})
	assert_true(session.has_active_replay())


func test_has_active_replay_false_before_start() -> void:
	assert_false(session.has_active_replay())


func test_record_input_appends_to_recorder() -> void:
	session.start_replay("shikaku", 7, {})
	session.record_input(1.0, "rectangle_placed", {"x": 0, "y": 0})
	session.record_input(2.5, "rectangle_placed", {"x": 3, "y": 0})
	assert_eq(recorder.inputs.size(), 2)
	assert_eq(recorder.inputs[0]["type"], "rectangle_placed")
	assert_eq(recorder.inputs[1]["t"], 2.5)


func test_finish_replay_returns_completed_dict() -> void:
	session.start_replay("sudoku", 1, {})
	var completed: Dictionary = session.finish_replay("win", 81, 120.0)
	assert_eq(completed["outcome"], "win")
	assert_true(recorder.finished)


func test_save_completed_replay_delegates_to_storage() -> void:
	var data: Dictionary = {"outcome": "win", "id": "abc"}
	session.save_completed_replay(data)
	assert_eq(storage.saved.size(), 1)
	assert_eq(storage.saved[0]["id"], "abc")


func test_bookmark_replay_returns_true() -> void:
	assert_true(session.bookmark_replay())
	assert_true(storage.bookmarked)


func test_bookmark_latest_replay_alias() -> void:
	assert_true(session.bookmark_latest_replay())


func test_flush_replay_delegates() -> void:
	session.flush_replay()
	assert_true(recorder.flushed)


# ---------------------------------------------------------------------------
# Crash state
# ---------------------------------------------------------------------------

func test_register_crash_state_delegates() -> void:
	var provider := func() -> Dictionary: return {}
	session.register_crash_state(provider)
	assert_eq(crash.providers.size(), 1)


func test_unregister_crash_state_delegates() -> void:
	var provider := func() -> Dictionary: return {}
	session.register_crash_state(provider)
	session.unregister_crash_state(provider)
	assert_eq(crash.providers.size(), 0)


func test_user_action_delegates_to_crash() -> void:
	session.user_action("test_event", {"key": "val"})
	assert_eq(crash.user_actions.size(), 1)
	assert_eq(crash.user_actions[0]["action"], "test_event")
	assert_eq(crash.user_actions[0]["meta"]["key"], "val")


func test_register_user_action_alias() -> void:
	session.register_user_action("another_event")
	assert_eq(crash.user_actions.size(), 1)
	assert_eq(crash.user_actions[0]["action"], "another_event")


# ---------------------------------------------------------------------------
# Analytics
# ---------------------------------------------------------------------------

func test_log_event_delegates_to_analytics() -> void:
	session.log_event("game_started", {"game": "sudoku"})
	assert_eq(analytics.events.size(), 1)
	assert_eq(analytics.events[0]["name"], "game_started")
	assert_eq(analytics.events[0]["params"]["game"], "sudoku")


# ---------------------------------------------------------------------------
# Achievements
# ---------------------------------------------------------------------------

func test_track_game_started_delegates() -> void:
	session.track_game_started("sudoku")
	assert_eq(achievements.calls.size(), 1)
	assert_eq(achievements.calls[0][0], "track_game_started")
	assert_eq(achievements.calls[0][1], "sudoku")


func test_track_game_won_delegates() -> void:
	session.track_game_won("shikaku", {"difficulty": 2})
	assert_eq(achievements.calls[0][0], "track_game_won")
	assert_eq(achievements.calls[0][1], "shikaku")


func test_track_streak_broken_delegates() -> void:
	session.track_streak_broken()
	assert_eq(achievements.calls[0][0], "track_streak_broken")


func test_track_blockudoku_clear_delegates() -> void:
	session.track_blockudoku_clear(3)
	assert_eq(achievements.calls[0][0], "track_blockudoku_clear")
	assert_eq(achievements.calls[0][1], 3)


func test_track_blockudoku_combo_delegates() -> void:
	session.track_blockudoku_combo(2)
	assert_eq(achievements.calls[0][0], "track_blockudoku_combo")


func test_track_blockudoku_game_played_delegates() -> void:
	session.track_blockudoku_game_played(500)
	assert_eq(achievements.calls[0][0], "track_blockudoku_game_played")
	assert_eq(achievements.calls[0][1], 500)


func test_track_shikaku_won_delegates() -> void:
	session.track_shikaku_won(6, 45.0)
	assert_eq(achievements.calls[0][0], "track_shikaku_won")
	assert_eq(achievements.calls[0][1], 6)


# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------

func test_increment_stats_counter_delegates() -> void:
	session.increment_stats_counter("sudoku", "games_played")
	assert_eq(stats.counters["sudoku.games_played"], 1)


func test_increment_stats_counter_with_amount() -> void:
	session.increment_stats_counter("blockudoku", "total_clears", 5)
	assert_eq(stats.counters["blockudoku.total_clears"], 5)


func test_set_stats_counter_delegates() -> void:
	session.set_stats_counter("sudoku", "best_d1", 12500)
	assert_eq(stats.counters["sudoku.best_d1"], 12500)


func test_get_stats_counter_returns_zero_when_absent() -> void:
	var val: int = session.get_stats_counter("sudoku", "nonexistent")
	assert_eq(val, 0)


func test_get_stats_counter_returns_stored_value() -> void:
	session.set_stats_counter("shikaku", "current_streak", 7)
	assert_eq(session.get_stats_counter("shikaku", "current_streak"), 7)


func test_record_stats_delegates() -> void:
	session.record_stats("sudoku", {"type": "completion", "difficulty": 2})
	assert_eq(stats.records.size(), 1)
	assert_eq(stats.records[0]["game"], "sudoku")


# ---------------------------------------------------------------------------
# Saves
# ---------------------------------------------------------------------------

func test_save_progress_delegates() -> void:
	session.save_progress("sudoku", {"grid": []})
	assert_true(saves.data.has("sudoku"))


func test_clear_save_delegates() -> void:
	session.save_progress("sudoku", {"grid": []})
	session.clear_save("sudoku")
	assert_false(saves.data.has("sudoku"))


func test_has_saved_game_returns_false_when_absent() -> void:
	assert_false(session.has_saved_game("sudoku"))


func test_has_saved_game_returns_true_after_save() -> void:
	session.save_progress("sudoku", {"x": 1})
	assert_true(session.has_saved_game("sudoku"))


func test_load_game_returns_saved_data() -> void:
	session.save_progress("blockudoku", {"score": 42})
	var loaded: Dictionary = session.load_game("blockudoku")
	assert_eq(loaded["score"], 42)


# ---------------------------------------------------------------------------
# Sound
# ---------------------------------------------------------------------------

func test_play_sound_place_delegates() -> void:
	session.play_sound_place()
	assert_true(sound.calls.has("play_place"))


func test_play_sound_win_delegates() -> void:
	session.play_sound_win()
	assert_true(sound.calls.has("play_win"))


func test_play_sound_pencil_delegates() -> void:
	session.play_sound_pencil()
	assert_true(sound.calls.has("play_pencil"))


func test_play_sound_erase_delegates() -> void:
	session.play_sound_erase()
	assert_true(sound.calls.has("play_erase"))


func test_play_sound_error_delegates() -> void:
	session.play_sound_error()
	assert_true(sound.calls.has("play_error"))


func test_play_sound_unit_complete_delegates() -> void:
	session.play_sound_unit_complete()
	assert_true(sound.calls.has("play_unit_complete"))


# ---------------------------------------------------------------------------
# Haptics
# ---------------------------------------------------------------------------

func test_vibrate_light_delegates() -> void:
	session.vibrate_light()
	assert_true(haptic.calls.has("vibrate_light"))


func test_vibrate_medium_delegates() -> void:
	session.vibrate_medium()
	assert_true(haptic.calls.has("vibrate_medium"))


func test_vibrate_heavy_delegates() -> void:
	session.vibrate_heavy()
	assert_true(haptic.calls.has("vibrate_heavy"))


func test_vibrate_error_delegates() -> void:
	session.vibrate_error()
	assert_true(haptic.calls.has("vibrate_error"))


func test_vibrate_success_delegates() -> void:
	session.vibrate_success()
	assert_true(haptic.calls.has("vibrate_success"))
