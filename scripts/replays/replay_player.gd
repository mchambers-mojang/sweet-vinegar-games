extends PanelContainer

## Generic replay playback engine.
## Drives game-specific replay rendering through a GameReplayAdapter.
## Handles play/pause, speed cycling, and backward scrubbing for all games.

const TimeFormat := preload("res://scripts/utils/time_format.gd")

@onready var back_button: Button = %BackButton
@onready var play_button: Button = %PlayButton
@onready var speed_button: Button = %SpeedButton
@onready var step_back_button: Button = %StepBackButton
@onready var scrub_bar: HSlider = %ScrubBar
@onready var progress_label: Label = %ProgressLabel
@onready var info_label: Label = %InfoLabel
@onready var adapter_container: Control = %AdapterContainer

var _adapter: GameReplayAdapter = null
var _replay: Dictionary = {}
var _frames: Array[Dictionary] = []
var _current_frame: int = 0
var _playing: bool = false
var _playback_timer: float = 0.0
var _playback_speed: float = 1.0
var _visual: Control = null
var _initial_state: Dictionary = {}
var _scrub_updating: bool = false

const SPEED_OPTIONS := [1, 2, 4]
var _speed_index: int = 0
const FRAME_INTERVAL := 0.6


func _ready() -> void:
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(Scenes.REPLAYS)
	)
	play_button.pressed.connect(_toggle_play)
	speed_button.pressed.connect(_cycle_speed)
	speed_button.text = "1x"
	step_back_button.pressed.connect(_step_back)
	scrub_bar.value_changed.connect(_on_scrub_bar_value_changed)
	set_process(false)

	var replay := ReplaySystem.get_pending_playback()
	if not replay.is_empty():
		_load_replay(replay)


func _load_replay(replay: Dictionary) -> void:
	_replay = replay
	var header: Dictionary = _replay.get("header", {})
	var game_mode := str(header.get("game_mode", ""))
	_initial_state = header.get("initial_state", {})

	_adapter = _create_adapter(game_mode)
	if _adapter == null:
		push_error("ReplayPlayer: Unknown game mode '%s'" % game_mode)
		return

	# Build the board visual and add it to the container.
	# add_child() triggers _ready() synchronously on the new node when the
	# parent is already inside the scene tree, so the board is fully
	# initialized by the time reset_to_state() is called below.
	_visual = _adapter.setup_playback(_initial_state)
	if _visual == null:
		push_error("ReplayPlayer: Adapter returned null visual for '%s'" % game_mode)
		return
	_visual.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	adapter_container.add_child(_visual)
	_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Board _ready() has now run; initialize to the recorded initial state.
	_adapter.reset_to_state(_initial_state, _visual)

	# Collect only visually meaningful frames, applying both the type filter
	# and the adapter's fine-grained per-frame filter.
	var visual_types := _adapter.get_visual_event_types()
	_frames = []
	for frame in _replay.get("frames", []):
		var event_type := str(frame.get("input_event", {}).get("type", ""))
		if visual_types.is_empty() or event_type in visual_types:
			if _adapter.should_include_frame(frame):
				_frames.append(frame)

	_current_frame = 0
	_playing = false
	_update_ui()


func _toggle_play() -> void:
	if _adapter == null or _visual == null:
		return
	if _current_frame >= _frames.size():
		# Reset to beginning for replay
		_current_frame = 0
		_adapter.reset_to_state(_initial_state, _visual)

	_playing = not _playing
	_playback_timer = 0.0
	set_process(_playing)
	_update_ui()


func _cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % SPEED_OPTIONS.size()
	_playback_speed = SPEED_OPTIONS[_speed_index]
	speed_button.text = str(int(_playback_speed)) + "x"


func _step_back() -> void:
	scrub_to(_current_frame - 1)


## Jump to an arbitrary frame index, rebuilding state from scratch when going backward.
func scrub_to(target_frame: int) -> void:
	if _adapter == null or _visual == null:
		return
	target_frame = clampi(target_frame, 0, _frames.size())
	_playing = false
	set_process(false)
	_adapter.reset_to_state(_initial_state, _visual)
	for i in range(maxi(target_frame - 1, 0)):
		_adapter.apply_frame(_frames[i], _visual, true)
	if target_frame > 0:
		_adapter.apply_frame(_frames[target_frame - 1], _visual, false)
	_current_frame = target_frame
	_update_ui()


func _on_scrub_bar_value_changed(value: float) -> void:
	if _scrub_updating:
		return
	scrub_to(int(value))


func _process(delta: float) -> void:
	if not _playing:
		return
	_playback_timer += delta * _playback_speed
	while _playback_timer >= FRAME_INTERVAL and _current_frame < _frames.size():
		_playback_timer -= FRAME_INTERVAL
		_adapter.apply_frame(_frames[_current_frame], _visual)
		_current_frame += 1
		_update_ui()

	if _current_frame >= _frames.size():
		_playing = false
		set_process(false)
		_update_ui()


func _update_ui() -> void:
	var total := _frames.size()
	progress_label.text = "%s / %s" % [
		TimeFormat.format_time(_get_current_time_seconds(), true),
		TimeFormat.format_time(_get_total_time_seconds(), true),
	]
	play_button.text = ""
	AppTheme.apply_icon(play_button, "pause" if _playing else "play")
	info_label.text = "Move %d" % _current_frame
	step_back_button.disabled = _current_frame <= 0
	_scrub_updating = true
	scrub_bar.max_value = max(total, 1)
	scrub_bar.value = _current_frame
	_scrub_updating = false


func _get_current_time_seconds() -> float:
	if _current_frame <= 0:
		return 0.0
	if _current_frame >= _frames.size():
		return _get_total_time_seconds()
	return float(_frames[_current_frame - 1].get("tick", 0)) / 1000.0


func _get_total_time_seconds() -> float:
	var footer: Dictionary = _replay.get("footer", {})
	return float(footer.get("duration", 0.0))


func _create_adapter(game_mode: String) -> GameReplayAdapter:
	match game_mode:
		"blockudoku":
			return BlockudokuReplayAdapter.new()
		"shikaku":
			return ShikakuReplayAdapter.new()
		"sudoku":
			return SudokuReplayAdapter.new()
	return null
