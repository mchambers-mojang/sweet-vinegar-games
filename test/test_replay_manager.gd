extends GutTest

## Unit tests for ReplayManager — session lifecycle, frame recording, serialization.

const ReplayScript := preload("res://scripts/autoload/replay_manager.gd")

var replay_mgr: Node


func before_each() -> void:
	replay_mgr = Node.new()
	replay_mgr.set_script(ReplayScript)
	add_child_autofree(replay_mgr)
	# Override internal state after _ready (avoids filesystem side-effects)
	replay_mgr._replay_index = [] as Array[Dictionary]
	replay_mgr._active_replay = {}
	replay_mgr._id_rng = RandomNumberGenerator.new()
	replay_mgr._active_sequence = 0
	replay_mgr._save_timer = 0.0
	replay_mgr._dirty = false
	replay_mgr._pending_playback = {}


# --- Session lifecycle ---

func test_start_session_creates_active_replay() -> void:
	replay_mgr.start_session("blockudoku", 12345, {"board": "empty"}, {"timer": true})
	assert_true(replay_mgr.has_active_session())
	assert_eq(replay_mgr._active_replay["header"]["game_mode"], "blockudoku")
	assert_eq(replay_mgr._active_replay["header"]["seed"], 12345)


func test_start_session_returns_nonempty_id() -> void:
	var id: String = replay_mgr.start_session("sudoku", 99, {})
	assert_true(id.length() > 0)


func test_record_input_appends_frames() -> void:
	replay_mgr.start_session("shikaku", 1, {})
	replay_mgr.record_input(1.5, "rectangle_placed", {"x": 0, "y": 0, "w": 3, "h": 2})
	replay_mgr.record_input(3.0, "rectangle_placed", {"x": 3, "y": 0, "w": 2, "h": 3})
	var frames: Array = replay_mgr._active_replay["frames"]
	assert_eq(frames.size(), 2)


func test_record_input_increments_sequence() -> void:
	replay_mgr.start_session("blockudoku", 1, {})
	replay_mgr.record_input(0.5, "piece_placed", {"grid_x": 3})
	replay_mgr.record_input(1.0, "piece_placed", {"grid_x": 5})
	var frames: Array = replay_mgr._active_replay["frames"]
	assert_eq(frames[0]["seq"], 0)
	assert_eq(frames[1]["seq"], 1)


func test_record_input_converts_time_to_ms() -> void:
	replay_mgr.start_session("sudoku", 1, {})
	replay_mgr.record_input(2.5, "number_input", {"index": 10})
	var frames: Array = replay_mgr._active_replay["frames"]
	assert_eq(frames[0]["tick"], 2500)


func test_record_input_noop_without_session() -> void:
	replay_mgr.record_input(1.0, "test", {"foo": "bar"})
	assert_true(replay_mgr._active_replay.is_empty())


# --- Pending playback ---

func test_set_get_pending_playback() -> void:
	var replay := {"id": "test123", "frames": []}
	replay_mgr.set_pending_playback(replay)
	var retrieved: Dictionary = replay_mgr.get_pending_playback()
	assert_eq(retrieved["id"], "test123")


func test_get_pending_clears_after_read() -> void:
	replay_mgr.set_pending_playback({"id": "x"})
	replay_mgr.get_pending_playback()
	var second: Dictionary = replay_mgr.get_pending_playback()
	assert_true(second.is_empty())


# --- Frame ordering ---

func test_frames_maintain_order() -> void:
	replay_mgr.start_session("shikaku", 1, {})
	for i in 10:
		replay_mgr.record_input(float(i), "rect_placed", {"step": i})
	var frames: Array = replay_mgr._active_replay["frames"]
	for i in 10:
		assert_eq(frames[i]["seq"], i)
		assert_eq(frames[i]["input_event"]["payload"]["step"], i)


# --- Dirty flag ---

func test_record_sets_dirty_flag() -> void:
	replay_mgr.start_session("blockudoku", 1, {})
	assert_false(replay_mgr._dirty)
	replay_mgr.record_input(0.1, "piece_placed", {})
	assert_true(replay_mgr._dirty)


# --- Undo/redo recording produces correct replay stream ---

func test_shikaku_undo_redo_replay_stream() -> void:
	# Simulates: place A, place B, undo (removes B), redo (re-adds B)
	# Expected replay frames: placed A, placed B, removed index 1, placed B
	replay_mgr.start_session("shikaku", 1, {})
	replay_mgr.record_input(1.0, "rectangle_placed", {"x": 0, "y": 0, "w": 2, "h": 2})
	replay_mgr.record_input(2.0, "rectangle_placed", {"x": 2, "y": 0, "w": 2, "h": 2})
	# Undo removes B (index 1)
	replay_mgr.record_input(3.0, "rectangle_removed", {"index": 1})
	# Redo re-adds B
	replay_mgr.record_input(4.0, "rectangle_placed", {"x": 2, "y": 0, "w": 2, "h": 2})

	var frames: Array = replay_mgr._active_replay["frames"]
	assert_eq(frames.size(), 4)
	assert_eq(frames[0]["input_event"]["type"], "rectangle_placed")
	assert_eq(frames[1]["input_event"]["type"], "rectangle_placed")
	assert_eq(frames[2]["input_event"]["type"], "rectangle_removed")
	assert_eq(frames[2]["input_event"]["payload"]["index"], 1)
	assert_eq(frames[3]["input_event"]["type"], "rectangle_placed")
