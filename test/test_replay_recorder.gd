extends GutTest

## Unit tests for ReplayRecorder — in-memory session lifecycle and crash recovery.

const RecorderScript := preload("res://scripts/replays/replay_recorder.gd")

var recorder: Node


func before_each() -> void:
	recorder = Node.new()
	recorder.set_script(RecorderScript)
	add_child_autofree(recorder)
	# Override internal state after _ready (avoids filesystem side-effects)
	recorder._active_replay = {}
	recorder._id_rng = RandomNumberGenerator.new()
	recorder._active_sequence = 0
	recorder._save_timer = 0.0
	recorder._dirty = false


func test_start_session_creates_active() -> void:
	recorder.start_session("blockudoku", 42, {"board": "empty"}, {"timer": false})
	assert_true(recorder.has_active_session())
	assert_eq(recorder._active_replay["header"]["game_mode"], "blockudoku")
	assert_eq(recorder._active_replay["header"]["seed"], 42)


func test_record_input_appends_frame() -> void:
	recorder.start_session("shikaku", 1, {})
	recorder.record_input(1.0, "rectangle_placed", {"x": 0, "y": 0, "w": 2, "h": 2})
	recorder.record_input(2.0, "rectangle_placed", {"x": 2, "y": 0, "w": 2, "h": 2})
	var frames: Array = recorder._active_replay["frames"]
	assert_eq(frames.size(), 2)
	assert_eq(frames[0]["input_event"]["type"], "rectangle_placed")


func test_finish_session_returns_replay() -> void:
	recorder.start_session("sudoku", 99, {"puzzle": "hard"})
	recorder.record_input(5.0, "number_input", {"index": 3, "value": 7})
	var replay: Dictionary = recorder.finish_session("win", 100, 5.0, {"filled": 81})
	assert_false(replay.is_empty())
	assert_eq(replay["header"]["game_mode"], "sudoku")
	assert_eq(replay["footer"]["outcome"], "win")
	assert_eq(replay["footer"]["final_score"], 100)
	var frames: Array = replay["frames"]
	assert_eq(frames.size(), 1)


func test_finish_clears_active_session() -> void:
	recorder.start_session("blockudoku", 1, {})
	assert_true(recorder.has_active_session())
	recorder.finish_session("game_over", 0, 10.0)
	assert_false(recorder.has_active_session())


func test_crash_payload_includes_active_frames() -> void:
	recorder.start_session("shikaku", 7, {})
	recorder.record_input(1.0, "rectangle_placed", {"x": 0, "y": 0, "w": 1, "h": 1})
	recorder.record_input(2.0, "rectangle_placed", {"x": 1, "y": 0, "w": 1, "h": 1})
	var payload: Dictionary = recorder.get_crash_recovery_payload()
	assert_false(payload.is_empty())
	var active: Dictionary = payload["active_replay"]
	assert_false(active.is_empty())
	var frames: Array = active["frames"]
	assert_eq(frames.size(), 2)
