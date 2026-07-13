extends GutTest

## Unit tests for ReplayRecorder — session lifecycle, frame recording, serialization.
## Updated to use ReplayRecorder directly after the ReplayManager → ReplayRecorder + ReplayStorage split.

const RecorderScript := preload("res://scripts/replays/replay_recorder.gd")
const TEST_ACTIVE_REPLAY_PATH := "user://test_replay_manager_active.json"

var recorder: Node


func before_each() -> void:
	recorder = Node.new()
	recorder.set_script(RecorderScript)
	recorder.active_replay_path = TEST_ACTIVE_REPLAY_PATH
	add_child_autofree(recorder)
	# Override internal state after _ready (avoids filesystem side-effects)
	recorder._active_replay = {}
	recorder._id_rng = RandomNumberGenerator.new()
	recorder._active_sequence = 0
	recorder._save_timer = 0.0
	recorder._dirty = false


func after_each() -> void:
	if FileAccess.file_exists(TEST_ACTIVE_REPLAY_PATH):
		DirAccess.remove_absolute(TEST_ACTIVE_REPLAY_PATH)


# --- Session lifecycle ---

func test_start_session_creates_active_replay() -> void:
	recorder.start_session("blockudoku", 12345, {"board": "empty"}, {"timer": true})
	assert_true(recorder.has_active_session())
	assert_eq(recorder._active_replay["header"]["game_mode"], "blockudoku")
	assert_eq(recorder._active_replay["header"]["seed"], 12345)


func test_start_session_returns_nonempty_id() -> void:
	var id: String = recorder.start_session("sudoku", 99, {})
	assert_true(id.length() > 0)


func test_record_input_appends_frames() -> void:
	recorder.start_session("shikaku", 1, {})
	recorder.record_input(1.5, "rectangle_placed", {"x": 0, "y": 0, "w": 3, "h": 2})
	recorder.record_input(3.0, "rectangle_placed", {"x": 3, "y": 0, "w": 2, "h": 3})
	var frames: Array = recorder._active_replay["frames"]
	assert_eq(frames.size(), 2)


func test_record_input_increments_sequence() -> void:
	recorder.start_session("blockudoku", 1, {})
	recorder.record_input(0.5, "piece_placed", {"grid_x": 3})
	recorder.record_input(1.0, "piece_placed", {"grid_x": 5})
	var frames: Array = recorder._active_replay["frames"]
	assert_eq(frames[0]["seq"], 0)
	assert_eq(frames[1]["seq"], 1)


func test_record_input_converts_time_to_ms() -> void:
	recorder.start_session("sudoku", 1, {})
	recorder.record_input(2.5, "number_input", {"index": 10})
	var frames: Array = recorder._active_replay["frames"]
	assert_eq(frames[0]["tick"], 2500)


func test_record_input_noop_without_session() -> void:
	recorder.record_input(1.0, "test", {"foo": "bar"})
	assert_true(recorder._active_replay.is_empty())


# --- Frame ordering ---

func test_frames_maintain_order() -> void:
	recorder.start_session("shikaku", 1, {})
	for i in 10:
		recorder.record_input(float(i), "rect_placed", {"step": i})
	var frames: Array = recorder._active_replay["frames"]
	for i in 10:
		assert_eq(frames[i]["seq"], i)
		assert_eq(frames[i]["input_event"]["payload"]["step"], i)


# --- Dirty flag ---

func test_record_sets_dirty_flag() -> void:
	recorder.start_session("blockudoku", 1, {})
	assert_false(recorder._dirty)
	recorder.record_input(0.1, "piece_placed", {})
	assert_true(recorder._dirty)


# --- Undo/redo recording produces correct replay stream ---

func test_shikaku_undo_redo_replay_stream() -> void:
	# Simulates: place A, place B, undo (removes B), redo (re-adds B)
	# Expected replay frames: placed A, placed B, removed index 1, placed B
	recorder.start_session("shikaku", 1, {})
	recorder.record_input(1.0, "rectangle_placed", {"x": 0, "y": 0, "w": 2, "h": 2})
	recorder.record_input(2.0, "rectangle_placed", {"x": 2, "y": 0, "w": 2, "h": 2})
	# Undo removes B (index 1)
	recorder.record_input(3.0, "rectangle_removed", {"index": 1})
	# Redo re-adds B
	recorder.record_input(4.0, "rectangle_placed", {"x": 2, "y": 0, "w": 2, "h": 2})

	var frames: Array = recorder._active_replay["frames"]
	assert_eq(frames.size(), 4)
	assert_eq(frames[0]["input_event"]["type"], "rectangle_placed")
	assert_eq(frames[1]["input_event"]["type"], "rectangle_placed")
	assert_eq(frames[2]["input_event"]["type"], "rectangle_removed")
	assert_eq(frames[2]["input_event"]["payload"]["index"], 1)
	assert_eq(frames[3]["input_event"]["type"], "rectangle_placed")
