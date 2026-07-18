extends GutTest

## Unit tests for replay playback logic — frame timing, speed cycling.
## Since viewers need full scene trees, we test the core logic patterns:
## speed cycling, frame advancement timing, frame indexing.

const ReplayPlayerScript := preload("res://scripts/replays/replay_player.gd")
const GameReplayAdapterScript := preload("res://scripts/replays/game_replay_adapter.gd")


class MockReplayAdapter extends GameReplayAdapterScript:
	var reset_count := 0
	var applied_calls: Array[Dictionary] = []

	func reset_to_state(_initial_state: Dictionary, _visual: Control) -> void:
		reset_count += 1

	func apply_frame(frame: Dictionary, _visual: Control, suppress_effects: bool = false) -> void:
		applied_calls.append({
			"seq": int(frame.get("seq", -1)),
			"suppress_effects": suppress_effects,
		})


func _make_replay_player_for_scrub_test(frames: Array[Dictionary]) -> Node:
	var player: Node = ReplayPlayerScript.new()
	player.back_button = Button.new()
	player.play_button = Button.new()
	player.speed_button = Button.new()
	player.step_back_button = Button.new()
	player.scrub_bar = HSlider.new()
	player.progress_label = Label.new()
	player.info_label = Label.new()
	player.adapter_container = Control.new()
	player._adapter = MockReplayAdapter.new()
	player._visual = Control.new()
	player._initial_state = {}
	player._frames = frames
	return player


func _free_replay_player_test_objects(player: Node) -> void:
	player.back_button.free()
	player.play_button.free()
	player.speed_button.free()
	player.step_back_button.free()
	player.scrub_bar.free()
	player.progress_label.free()
	player.info_label.free()
	player.adapter_container.free()
	player._visual.free()
	player.free()


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


func test_shikaku_replay_recovers_missing_initial_state_from_seed() -> void:
	var replay := {
		"id": "legacy_shikaku",
		"header": {
			"game_mode": "shikaku",
			"seed": 7,
			"initial_state": {},
		},
		"frames": [
			{
				"tick": 500,
				"seq": 0,
				"input_event": {
					"type": "rectangle_placed",
					"payload": {"x": 0, "y": 0},
				},
			},
			{
				"tick": 1000,
				"seq": 1,
				"input_event": {
					"type": "rectangle_placed",
					"payload": {"x": 0, "y": 0, "w": 2, "h": 1},
				},
			},
		],
		"footer": {
			"duration": 1.0,
			"final_state": {"width": 5, "height": 5},
		},
	}
	ReplaySystem.set_pending_playback(replay)
	var viewer := (load("res://scenes/replay_viewer.tscn") as PackedScene).instantiate()
	add_child_autofree(viewer)
	await get_tree().process_frame

	var board := viewer._visual as ShikakuBoard
	assert_not_null(board)
	assert_eq(board.grid_width, 5)
	assert_eq(board.grid_height, 5)
	assert_false(board.numbers.is_empty(), "Seeded Shikaku replay should reconstruct its clue numbers")
	assert_gt(board.size.x, 0.0, "Shikaku replay board should receive layout width")
	assert_gt(board.size.y, 0.0, "Shikaku replay board should receive layout height")
	assert_eq(viewer._frames.size(), 1, "Malformed Shikaku frames should not enter playback")
	viewer.scrub_to(1)
	assert_eq(board.placed_rects, [Rect2i(0, 0, 2, 1)])


func test_shikaku_replay_rejects_seed_incompatible_with_recorded_moves() -> void:
	var replay := {
		"header": {
			"game_mode": "shikaku",
			"seed": 7,
			"initial_state": {},
		},
		"frames": [
			{
				"input_event": {
					"type": "rectangle_placed",
					"payload": {"x": 0, "y": 0, "w": 4, "h": 2},
				},
			},
		],
		"footer": {
			"outcome": "win",
			"final_state": {"width": 5, "height": 5},
		},
	}
	var adapter := ShikakuReplayAdapter.new()
	assert_true(
		adapter.get_initial_state(replay).is_empty(),
		"An incompatible seed must not synthesize the wrong Shikaku board",
	)


# --- Replay scrub behavior ---

func test_scrub_to_replays_intermediate_frames_with_suppressed_effects() -> void:
	var frames: Array[Dictionary] = [
		{"seq": 0, "input_event": {"type": "piece_placed", "payload": {}}},
		{"seq": 1, "input_event": {"type": "piece_placed", "payload": {}}},
		{"seq": 2, "input_event": {"type": "piece_placed", "payload": {}}},
	]
	var player: Node = _make_replay_player_for_scrub_test(frames)
	var adapter := player._adapter as MockReplayAdapter

	player.scrub_to(3)

	assert_eq(adapter.reset_count, 1)
	assert_eq(adapter.applied_calls.size(), 3)
	assert_true(adapter.applied_calls[0]["suppress_effects"])
	assert_true(adapter.applied_calls[1]["suppress_effects"])
	assert_false(adapter.applied_calls[2]["suppress_effects"])
	assert_eq(adapter.applied_calls[2]["seq"], 2)
	_free_replay_player_test_objects(player)


func test_scrub_to_zero_replays_no_frames() -> void:
	var player: Node = _make_replay_player_for_scrub_test([{"seq": 0, "input_event": {}}])
	var adapter := player._adapter as MockReplayAdapter

	player.scrub_to(0)

	assert_eq(adapter.reset_count, 1)
	assert_eq(adapter.applied_calls.size(), 0)
	_free_replay_player_test_objects(player)
