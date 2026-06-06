extends Control

## Blockudoku replay playback viewer.
## Renders the board and steps through recorded piece placements.

@onready var board: BlockudokuBoard = %BlockudokuBoard
@onready var back_button: Button = %BackButton
@onready var play_button: Button = %PlayButton
@onready var speed_button: Button = %SpeedButton
@onready var progress_label: Label = %ProgressLabel
@onready var score_label: Label = %ScoreLabel

var _replay: Dictionary = {}
var _frames: Array = []
var _current_frame: int = 0
var _playing: bool = false
var _playback_timer: float = 0.0
var _playback_speed: float = 1.0
var _last_tick: int = 0

const SPEED_OPTIONS := [1, 2, 4]
var _speed_index: int = 0


func _ready() -> void:
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/replays.tscn")
	)
	play_button.pressed.connect(_toggle_play)
	speed_button.pressed.connect(_cycle_speed)
	speed_button.text = "1x"
	set_process(false)

	# Load the replay that was queued for playback
	var replay := ReplayManager.get_pending_playback()
	if not replay.is_empty():
		load_replay(replay)


func load_replay(replay: Dictionary) -> void:
	_replay = replay
	var header: Dictionary = _replay.get("header", {})
	var initial_state: Dictionary = header.get("initial_state", {})

	# Set up board from initial state
	board.reset()
	if initial_state.has("board_state"):
		board.set_state(initial_state.get("board_state"))

	# Collect only placement frames (the meaningful visual events)
	_frames = []
	for frame in _replay.get("frames", []):
		var input_event: Dictionary = frame.get("input_event", {})
		var event_type := str(input_event.get("type", ""))
		if event_type == "piece_placed":
			_frames.append(frame)

	_current_frame = 0
	_playing = false
	_update_ui()
	board.queue_redraw()


func _toggle_play() -> void:
	if _current_frame >= _frames.size():
		# Reset to beginning
		_current_frame = 0
		var header: Dictionary = _replay.get("header", {})
		var initial_state: Dictionary = header.get("initial_state", {})
		board.reset()
		if initial_state.has("board_state"):
			board.set_state(initial_state.get("board_state"))
		board.queue_redraw()

	_playing = not _playing
	_playback_timer = 0.0
	set_process(_playing)
	_update_ui()


func _cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % SPEED_OPTIONS.size()
	_playback_speed = SPEED_OPTIONS[_speed_index]
	speed_button.text = str(_playback_speed) + "x"


func _process(delta: float) -> void:
	if not _playing:
		return
	_playback_timer += delta * _playback_speed
	# Step through frames at ~0.6s intervals (adjusted by speed)
	while _playback_timer >= 0.6 and _current_frame < _frames.size():
		_playback_timer -= 0.6
		_apply_frame(_frames[_current_frame])
		_current_frame += 1
		_update_ui()

	if _current_frame >= _frames.size():
		_playing = false
		set_process(false)
		_update_ui()


func _apply_frame(frame: Dictionary) -> void:
	var input_event: Dictionary = frame.get("input_event", {})
	var payload: Dictionary = input_event.get("payload", {})
	var grid_x := int(payload.get("grid_x", 0))
	var grid_y := int(payload.get("grid_y", 0))
	var shape_data: Array = payload.get("shape", [])

	# Reconstruct shape as Array[Vector2i]
	var shape: Array[Vector2i] = []
	for cell in shape_data:
		if cell is Array and cell.size() >= 2:
			shape.append(Vector2i(int(cell[0]), int(cell[1])))
		elif cell is Dictionary:
			shape.append(Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0))))

	if shape.is_empty():
		return

	# Place on board (skip occupancy check — replay data is trusted)
	board.place_block(shape, grid_x, grid_y)
	board.check_and_clear()
	board.queue_redraw()


func _update_ui() -> void:
	var total := _frames.size()
	progress_label.text = "%d / %d" % [_current_frame, total]
	play_button.text = ""
	IconManager.apply_icon(play_button, "pause" if _playing else "play")
	score_label.text = "Move %d" % _current_frame
