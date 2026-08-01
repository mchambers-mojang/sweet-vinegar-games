extends GutTest

## Focused regressions for CrownGridGameScreen session-ceremony and
## Crown-hint replay recording.
##
## Uses lightweight mock dependencies (no scene tree required).
## All @onready-dependent methods are overridden in TestCrownGridScreen so
## the screen can be instantiated via .new() without a live scene.

# ---------------------------------------------------------------------------
# Mock helpers (mirrors test_game_screen.gd)
# ---------------------------------------------------------------------------

class MockRecorder:
	var started := false
	var last_game_mode := ""
	var last_seed := 0
	var inputs: Array = []
	var finished := false

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
		pass


class MockStorage:
	func save_replay(_completed: Dictionary) -> void:
		pass

	func bookmark_latest_replay() -> bool:
		return true


class MockCrash:
	func register_state_provider(_provider: Callable) -> void:
		pass

	func unregister_state_provider(_provider: Callable) -> void:
		pass

	func register_user_action(_action: String, _metadata: Dictionary = {}) -> void:
		pass


class MockAnalytics:
	func log_event(_name: String, _params: Dictionary = {}) -> void:
		pass


class MockAchievements:
	func track(_event_key: String, _value: int = 1) -> void:
		pass

	func check_stats() -> void:
		pass


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
	func play_place() -> void: pass
	func play_win() -> void: pass
	func play_pencil() -> void: pass
	func play_erase() -> void: pass
	func play_error() -> void: pass
	func play_select() -> void: pass
	func play_unit_complete() -> void: pass


class MockHaptic:
	func vibrate_light() -> void: pass
	func vibrate_medium() -> void: pass
	func vibrate_heavy() -> void: pass
	func vibrate_error() -> void: pass
	func vibrate_success() -> void: pass
	func stop() -> void: pass


# ---------------------------------------------------------------------------
# Minimal CrownGridGameScreen subclass for testing
# All methods that access @onready board/button/spinner nodes are overridden.
# ---------------------------------------------------------------------------

class TestCrownGridScreen extends CrownGridGameScreen:
	## Override to skip @onready-dependent signal connections.
	func _on_game_screen_ready() -> void:
		pass

	## Override to skip board setup and button state updates.
	func _apply_board_from_logic() -> void:
		pass

	func _update_button_states() -> void:
		pass

	func _apply_game_theme() -> void:
		pass

	func _apply_panel_theme() -> void:
		pass


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a minimal valid 6x6 generation result without running the generator.
## Uses column regions (region i = column i) and a zigzag solution that is
## non-diagonally-adjacent: [0, 2, 4, 1, 3, 5].
func _minimal_gen_result() -> Dictionary:
	var sz := 6
	var regions := PackedInt32Array()
	regions.resize(sz * sz)
	for r in range(sz):
		for c in range(sz):
			regions[r * sz + c] = c
	var solution: Array[int] = [0, 2, 4, 1, 3, 5]
	return {"size": sz, "regions": regions, "solution": solution}


func _make_screen(rec: MockRecorder, sta: MockStats) -> TestCrownGridScreen:
	return TestCrownGridScreen.new(
		rec, MockStorage.new(), MockCrash.new(),
		MockAnalytics.new(), MockAchievements.new(),
		MockSaves.new(), sta, MockSound.new(), MockHaptic.new()
	)


# ---------------------------------------------------------------------------
# Session-ceremony regression
# ---------------------------------------------------------------------------

## After _on_generation_done() completes with a valid result, begin_session()
## must have been called (new-game path, not resume).  The recorder must be
## started, random_seed must match the generation seed, and Crown Grid stats
## must reflect a new game.
func test_generation_done_starts_session_ceremony() -> void:
	var recorder := MockRecorder.new()
	var stats := MockStats.new()
	var screen := _make_screen(recorder, stats)

	screen._tier = CrownGridGenerator.TIER_EASY
	screen._tier_size = 6
	screen._pending_gen_seed = 12345
	screen._gen_pending_result = _minimal_gen_result()
	screen._gen_thread = null  # no background thread to join

	screen._on_generation_done()

	assert_true(recorder.started,
			"begin_session() must be called after generation — recorder must be started")
	assert_eq(recorder.last_game_mode, "crown_grid",
			"Replay must be started with game_mode 'crown_grid'")
	assert_eq(screen.random_seed, 12345,
			"random_seed must match the generation seed")
	assert_eq(stats.counters.get("crown_grid.games_started", 0), 1,
			"_increment_stats() must increment crown_grid.games_started for a new game")
	assert_eq(stats.counters.get("general.games_played", 0), 1,
			"begin_session() must increment general.games_played")


## A cancelled generation must NOT start a session ceremony.
func test_generation_done_cancelled_skips_ceremony() -> void:
	var recorder := MockRecorder.new()
	var stats := MockStats.new()
	var screen := _make_screen(recorder, stats)

	screen._set_gen_cancelled(true)
	screen._gen_pending_result = _minimal_gen_result()
	screen._gen_thread = null

	screen._on_generation_done()

	assert_false(recorder.started,
			"A cancelled generation must not start a session ceremony")


## resume_game() must call begin_session(saved_data), starting the recorder.
func test_resume_game_starts_session_from_save() -> void:
	var recorder := MockRecorder.new()
	var stats := MockStats.new()
	var screen := _make_screen(recorder, stats)

	var gen := _minimal_gen_result()
	var sz: int = gen["size"]
	var cells: Array = []
	for _i in range(sz * sz):
		cells.append(0)
	var saved: Dictionary = {
		"size": sz,
		"tier": CrownGridGenerator.TIER_EASY,
		"regions": gen["regions"],
		"solution": gen["solution"],
		"cells": cells,
		"is_completed": false,
		"assistance_mode": 0,
		"elapsed_time": 30.0,
		"random_seed": 99,
		"replay_id": "old-id",
	}

	screen.resume_game(saved)

	assert_true(recorder.started,
			"resume_game() must call begin_session() to start the recorder")
	assert_eq(screen.elapsed_time, 30.0,
			"elapsed_time must be restored from save")


# ---------------------------------------------------------------------------
# Crown-hint replay regression
# ---------------------------------------------------------------------------

## When a Crown hint fires with auto_mark=true, the HintResult must carry the
## auto-marked cells so the game screen can record the "exclusions_painted"
## replay event.  This test confirms the logic contract that the recording
## logic in _on_hint() depends on.
func test_hint_crown_result_carries_auto_marked_cells() -> void:
	var logic := CrownGridLogic.new()
	# Build a 4x4 board with column regions and a known solution [1,0,3,2].
	var sz := 4
	var regions := PackedInt32Array()
	regions.resize(sz * sz)
	for r in range(sz):
		for c in range(sz):
			regions[r * sz + c] = c
	var solution: Array[int] = [1, 0, 3, 2]
	logic.init_new_game(sz, regions, solution, true)  # auto_mark=true

	# Force a crown hint on row 0 by excluding all candidates except (1,0).
	var to_exclude: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(3, 0)]
	logic.paint_excluded(to_exclude)

	var hint := logic.use_hint()
	assert_true(hint.applied, "Hint must be applied")
	assert_eq(hint.new_state, CrownGridLogic.CELL_CROWN,
			"Hint must place a Crown")
	assert_false(hint.auto_marked.is_empty(),
			"Crown hint with auto_mark=true must populate auto_marked — "
			+ "this is the data the game screen uses to record exclusions_painted")


## _on_hint() must record a hint_applied event followed by an exclusions_painted
## event when auto_mark fires; replaying those frames against a CrownGridBoard
## must produce the same cell state that the logic has.
func test_on_hint_records_and_replays_correctly() -> void:
	var recorder := MockRecorder.new()
	var stats := MockStats.new()
	var screen := _make_screen(recorder, stats)

	# Start session via _on_generation_done() with the 6x6 minimal result.
	var gen := _minimal_gen_result()
	screen._tier = CrownGridGenerator.TIER_EASY
	screen._tier_size = 6
	screen._pending_gen_seed = 42
	screen._gen_pending_result = gen
	screen._gen_thread = null
	screen._on_generation_done()

	# Re-init logic with auto_mark=true so Crown hints auto-mark the column.
	var sz: int = gen["size"]
	var regions: PackedInt32Array = gen["regions"]
	var solution: Array[int] = gen["solution"]  # [0, 2, 4, 1, 3, 5]
	screen.logic.init_new_game(sz, regions, solution, true)

	# Force a naked-single Crown hint in row 0: exclude all cols except 0.
	var to_exclude: Array[Vector2i] = []
	for c in range(1, sz):
		to_exclude.append(Vector2i(c, 0))
	screen.logic.paint_excluded(to_exclude)

	# Snapshot recorder state before the hint so we can find the new events.
	var inputs_before := recorder.inputs.size()

	screen._on_hint()

	# --- Verify recorded events ---
	var new_inputs: Array = recorder.inputs.slice(inputs_before)
	var hint_events: Array = new_inputs.filter(func(e): return e["type"] == "hint_applied")
	var excl_events: Array = new_inputs.filter(func(e): return e["type"] == "exclusions_painted")

	assert_false(hint_events.is_empty(),
			"_on_hint() must record a hint_applied event")
	var hint_payload: Dictionary = hint_events[0]["payload"]
	assert_eq(hint_payload.get("col", -1), 0,
			"hint_applied col must be 0 (crown position in row 0)")
	assert_eq(hint_payload.get("row", -1), 0,
			"hint_applied row must be 0")
	assert_eq(hint_payload.get("new_state", -1), CrownGridLogic.CELL_CROWN,
			"hint_applied new_state must be CELL_CROWN")

	assert_false(excl_events.is_empty(),
			"Crown hint with auto_mark=true must also record an exclusions_painted event")

	# --- Verify replay faithfully reproduces the hint ---
	var board := CrownGridBoard.new()
	board.setup(sz, regions)

	var adapter := CrownGridReplayAdapter.new()
	for evt in new_inputs:
		var frame := {"input_event": {"type": evt["type"], "payload": evt["payload"]}}
		adapter.apply_frame(frame, board)

	# The crown at (col=0, row=0) must be reflected in board.cell_states.
	assert_eq(int(board.cell_states[0 * sz + 0]), CrownGridLogic.CELL_CROWN,
			"Replayed board must show CELL_CROWN at (0,0) after hint_applied frame")

	# All cells in col 0 except row 0 must be CELL_EXCLUDED after exclusions_painted.
	for r in range(1, sz):
		assert_eq(int(board.cell_states[r * sz + 0]), CrownGridLogic.CELL_EXCLUDED,
				"Column-0 cell in row %d must be CELL_EXCLUDED after auto-mark replay" % r)

	board.free()
	screen.free()
