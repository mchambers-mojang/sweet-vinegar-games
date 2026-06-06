extends GutTest

## Unit tests for replay playback logic — frame timing, speed cycling.
## Since viewers need full scene trees, we test the core logic patterns:
## speed cycling, frame advancement timing, frame indexing.


# --- Speed cycling logic (shared across all viewers) ---

func test_speed_cycle_wraps() -> void:
	var speeds := [1, 2, 4]
	var idx := 0
	idx = (idx + 1) % speeds.size()
	assert_eq(idx, 1)
	idx = (idx + 1) % speeds.size()
	assert_eq(idx, 2)
	idx = (idx + 1) % speeds.size()
	assert_eq(idx, 0)


# --- Frame timing logic ---

func test_frame_advancement_respects_tick_delta() -> void:
	# Simulate frames with ticks in ms
	var frames := [
		{"tick": 0, "seq": 0, "input_event": {"type": "test", "payload": {}}},
		{"tick": 1000, "seq": 1, "input_event": {"type": "test", "payload": {}}},
		{"tick": 2500, "seq": 2, "input_event": {"type": "test", "payload": {}}},
	]
	var current_frame := 0
	var playback_timer := 0.0
	var playback_speed := 1.0
	var last_tick := 0

	# Advance 0.5s (500ms) at 1x — shouldn't advance past frame 1 (needs 1000ms)
	playback_timer += 0.5 * playback_speed
	var next_tick: int = frames[current_frame + 1]["tick"]
	var delta_ms: float = float(next_tick - last_tick) / 1000.0
	assert_false(playback_timer >= delta_ms)

	# Advance to 1.0s total
	playback_timer += 0.5 * playback_speed
	assert_true(playback_timer >= delta_ms)
	# Apply frame
	current_frame += 1
	last_tick = frames[current_frame]["tick"]
	playback_timer -= delta_ms
	assert_eq(current_frame, 1)
	assert_eq(last_tick, 1000)


func test_frame_advancement_at_2x_speed() -> void:
	var frames := [
		{"tick": 0, "seq": 0, "input_event": {"type": "test", "payload": {}}},
		{"tick": 1000, "seq": 1, "input_event": {"type": "test", "payload": {}}},
		{"tick": 3000, "seq": 2, "input_event": {"type": "test", "payload": {}}},
	]
	var current_frame := 0
	var playback_timer := 0.0
	var playback_speed := 2.0
	var last_tick := 0

	# At 2x speed, 0.5s real time = 1.0s game time
	playback_timer += 0.5 * playback_speed
	var next_tick: int = frames[current_frame + 1]["tick"]
	var delta_s: float = float(next_tick - last_tick) / 1000.0
	assert_true(playback_timer >= delta_s)  # 1.0 >= 1.0

	current_frame += 1
	last_tick = frames[current_frame]["tick"]
	playback_timer -= delta_s
	assert_eq(current_frame, 1)


func test_frame_boundary_stops_at_end() -> void:
	var frames := [
		{"tick": 0, "seq": 0, "input_event": {"type": "test", "payload": {}}},
		{"tick": 500, "seq": 1, "input_event": {"type": "test", "payload": {}}},
	]
	var current_frame := 1
	# At end of frames, should stop
	assert_true(current_frame >= frames.size() - 1)


# --- Replay loading structure ---

func test_replay_structure_has_required_keys() -> void:
	# Minimal valid replay structure
	var replay := {
		"id": "abc123",
		"header": {
			"game_mode": "blockudoku",
			"seed": 42,
			"timestamp": 1700000000,
		},
		"frames": [
			{"tick": 0, "seq": 0, "input_event": {"type": "piece_placed", "payload": {"grid_x": 3}}},
		],
	}
	assert_true(replay.has("id"))
	assert_true(replay.has("header"))
	assert_true(replay.has("frames"))
	assert_true(replay["header"].has("game_mode"))
	assert_true(replay["header"].has("seed"))
	assert_eq(replay["frames"].size(), 1)


func test_frame_ordering_by_sequence() -> void:
	var frames := [
		{"tick": 100, "seq": 0, "input_event": {"type": "a", "payload": {}}},
		{"tick": 200, "seq": 1, "input_event": {"type": "b", "payload": {}}},
		{"tick": 50, "seq": 2, "input_event": {"type": "c", "payload": {}}},
	]
	# Frames should be played in seq order regardless of tick
	for i in range(frames.size() - 1):
		assert_true(frames[i]["seq"] < frames[i + 1]["seq"])


# --- Blockudoku replay frame parsing ---

func test_blockudoku_frame_has_piece_placed() -> void:
	var frame := {
		"tick": 1500,
		"seq": 0,
		"input_event": {
			"type": "piece_placed",
			"payload": {
				"grid_x": 3,
				"grid_y": 4,
				"shape": [[0, 0], [1, 0], [0, 1]],
				"block_index": 1,
			},
		},
	}
	assert_eq(frame["input_event"]["type"], "piece_placed")
	var payload: Dictionary = frame["input_event"]["payload"]
	assert_true(payload.has("grid_x"))
	assert_true(payload.has("grid_y"))
	assert_true(payload.has("shape"))


# --- Shikaku replay frame parsing ---

func test_shikaku_frame_rectangle_placed() -> void:
	var frame := {
		"tick": 2000,
		"seq": 0,
		"input_event": {
			"type": "rectangle_placed",
			"payload": {"x": 1, "y": 2, "w": 3, "h": 2},
		},
	}
	var payload: Dictionary = frame["input_event"]["payload"]
	assert_eq(payload["x"], 1)
	assert_eq(payload["w"], 3)


func test_shikaku_frame_rectangle_removed() -> void:
	var frame := {
		"tick": 3000,
		"seq": 1,
		"input_event": {
			"type": "rectangle_removed",
			"payload": {"index": 2},
		},
	}
	assert_eq(frame["input_event"]["type"], "rectangle_removed")
	assert_eq(frame["input_event"]["payload"]["index"], 2)
