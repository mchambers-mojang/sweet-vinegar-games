extends Control

## Shikaku replay playback viewer.
## Steps through rectangle placements on the puzzle grid.

@onready var board: ShikakuBoard = %ShikakuBoard
@onready var back_button: Button = %BackButton
@onready var play_button: Button = %PlayButton
@onready var speed_button: Button = %SpeedButton
@onready var progress_label: Label = %ProgressLabel
@onready var info_label: Label = %InfoLabel

var _replay: Dictionary = {}
var _frames: Array = []
var _current_frame: int = 0
var _playing: bool = false
var _playback_timer: float = 0.0
var _playback_speed: float = 1.0

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

	var replay := ReplayManager.get_pending_playback()
	if not replay.is_empty():
		load_replay(replay)


func load_replay(replay: Dictionary) -> void:
	_replay = replay
	var header: Dictionary = _replay.get("header", {})
	var initial_state: Dictionary = header.get("initial_state", {})

	# Set up board
	var w := int(initial_state.get("width", 5))
	var h := int(initial_state.get("height", 5))
	var numbers_data: Dictionary = initial_state.get("numbers", {})
	var numbers: Dictionary = {}
	for key in numbers_data.keys():
		numbers[key] = int(numbers_data[key])
	board.setup(w, h, numbers)

	# Collect placement frames
	_frames = []
	for frame in _replay.get("frames", []):
		var input_event: Dictionary = frame.get("input_event", {})
		var event_type := str(input_event.get("type", ""))
		if event_type == "rectangle_placed" or event_type == "rectangle_removed":
			_frames.append(frame)

	_current_frame = 0
	_playing = false
	_update_ui()
	board.queue_redraw()


func _toggle_play() -> void:
	if _current_frame >= _frames.size():
		_current_frame = 0
		# Reset board
		var header: Dictionary = _replay.get("header", {})
		var initial_state: Dictionary = header.get("initial_state", {})
		var w := int(initial_state.get("width", 5))
		var h := int(initial_state.get("height", 5))
		var numbers_data: Dictionary = initial_state.get("numbers", {})
		var numbers: Dictionary = {}
		for key in numbers_data.keys():
			numbers[key] = int(numbers_data[key])
		board.setup(w, h, numbers)
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
	var event_type := str(input_event.get("type", ""))
	var payload: Dictionary = input_event.get("payload", {})

	if event_type == "rectangle_placed":
		var rect := Rect2i(
			int(payload.get("x", 0)),
			int(payload.get("y", 0)),
			int(payload.get("w", 1)),
			int(payload.get("h", 1)),
		)
		board.add_rect(rect)
	elif event_type == "rectangle_removed":
		var index := int(payload.get("index", -1))
		if index >= 0 and index < board.placed_rects.size():
			board.remove_rect(index)
	board.queue_redraw()


func _update_ui() -> void:
	var total := _frames.size()
	progress_label.text = "%d / %d" % [_current_frame, total]
	play_button.text = "⏸" if _playing else "▶"
	info_label.text = "Move %d" % _current_frame
