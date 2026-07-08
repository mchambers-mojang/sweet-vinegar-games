class_name LeaderboardScreen
extends PanelContainer

## Full-screen leaderboard view. Shows top 10 + pinned player rank.
## Navigated from a Game Menu via transition_with_callback → setup().

const TimeFormat := preload("res://scripts/utils/time_format.gd")
const REST_BASE_URL := "https://carom-signaling-dae9dadjh0h9aqgb.westus3-01.azurewebsites.net"
const CACHE_TTL := 30.0

var _game_id: String = ""
var _modes: PackedStringArray = PackedStringArray()
var _mode_labels: PackedStringArray = PackedStringArray()
var _is_time_based: bool = true
var _return_scene: String = ""
var _current_mode: String = ""

var _cache: Dictionary = {}
var _inflight_key: String = ""

@onready var _back_button: Button = %BackButton
@onready var _title_label: Label = %TitleLabel
@onready var _mode_dropdown: OptionButton = %ModeDropdown
@onready var _status_label: Label = %StatusLabel
@onready var _entry_list: VBoxContainer = %EntryList
@onready var _player_row: HBoxContainer = %PlayerRow
@onready var _player_label: Label = %PlayerLabel
@onready var _http: HTTPRequest = $HTTPRequest


func _ready() -> void:
	theme = AppTheme.get_theme_resource()
	_http.request_completed.connect(_on_request_completed)
	_back_button.pressed.connect(_on_back_pressed)
	_mode_dropdown.item_selected.connect(_on_mode_selected)
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void:
		theme = AppTheme.get_theme_resource()
		_apply_theme()
	)


## Called by the Game Menu after instantiation.
func setup(game_id: String, modes: PackedStringArray, mode_labels: PackedStringArray,
		is_time_based: bool, selected_index: int, return_scene: String) -> void:
	_game_id = game_id
	_modes = modes
	_mode_labels = mode_labels
	_is_time_based = is_time_based
	_return_scene = return_scene

	# Populate dropdown (only if more than one mode)
	_mode_dropdown.clear()
	if _modes.size() > 1:
		_mode_dropdown.visible = true
		for i in range(_modes.size()):
			_mode_dropdown.add_item(_mode_labels[i] if i < _mode_labels.size() else _modes[i], i)
		var clamped_idx := clampi(selected_index, 0, _modes.size() - 1)
		_mode_dropdown.selected = clamped_idx
		_current_mode = _modes[clamped_idx]
	elif _modes.size() == 1:
		_mode_dropdown.visible = false
		_current_mode = _modes[0]
	else:
		_mode_dropdown.visible = false

	_fetch()


func _on_mode_selected(index: int) -> void:
	if index >= 0 and index < _modes.size():
		_current_mode = _modes[index]
		_fetch()


func _on_back_pressed() -> void:
	SceneTransition.transition_to(_return_scene)


func _fetch() -> void:
	if _current_mode.is_empty():
		_show_error("No leaderboard for this mode")
		return

	var key := "%s:%s" % [_game_id, _current_mode]
	_inflight_key = key

	# Serve from cache if fresh
	if _cache.has(key):
		var entry: Dictionary = _cache[key]
		var cache_time := float(entry.get("time", 0.0))
		if Time.get_unix_time_from_system() - cache_time < CACHE_TTL:
			_show_data(entry.get("data", {}))
			return

	_show_loading()
	_http.cancel_request()

	var device_id: String = PlayerIdentity.device_id
	var url := "%s/leaderboard?game=%s&mode=%s&device_id=%s" % [
		REST_BASE_URL, _game_id, _current_mode, device_id,
	]
	if _http.request(url) != OK:
		_show_error("Network error")


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	var key := "%s:%s" % [_game_id, _current_mode]
	if _inflight_key != key:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_show_error("Leaderboard unavailable")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		_show_error("Leaderboard unavailable")
		return
	_cache[key] = {
		"time": Time.get_unix_time_from_system(),
		"data": parsed,
	}
	_show_data(parsed)


func _show_loading() -> void:
	_status_label.visible = true
	_status_label.text = "Loading…"
	_entry_list.visible = false
	_player_row.visible = false


func _show_error(msg: String = "Leaderboard unavailable") -> void:
	_status_label.visible = true
	_status_label.text = msg
	_entry_list.visible = false
	_player_row.visible = false


func _show_data(data: Dictionary) -> void:
	var top: Array = data.get("top", [])
	var player_rank = data.get("player_rank", null)
	var player_score = data.get("player_score", null)

	_status_label.visible = top.is_empty()
	if top.is_empty():
		_status_label.text = "No scores yet"

	# Rebuild entry rows
	_entry_list.visible = not top.is_empty()
	for child in _entry_list.get_children():
		child.queue_free()

	var device_id: String = PlayerIdentity.device_id
	var player_in_top := false

	for entry in top:
		var is_player: bool = entry.get("device_id", "") == device_id
		if is_player:
			player_in_top = true
		var rank: int = entry.get("rank", 0)
		var display_name: String = entry.get("display_name", "???")
		var value: float = entry.get("value", 0.0)
		var row := _create_entry_row(rank, display_name, value, is_player)
		_entry_list.add_child(row)

	# Pinned player row (shown only if not in top 10)
	if player_rank != null and not player_in_top and player_score != null:
		_player_row.visible = true
		_player_label.text = "#%d  %s  %s" % [
			int(player_rank),
			PlayerIdentity.display_name,
			_format_value(float(player_score)),
		]
	else:
		_player_row.visible = false


func _create_entry_row(rank: int, display_name: String, value: float, is_player: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var rank_label := Label.new()
	rank_label.text = "#%d" % rank
	rank_label.custom_minimum_size = Vector2(40, 0)
	rank_label.add_theme_font_size_override("font_size", 15)
	row.add_child(rank_label)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 15)
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.text = _format_value(value)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 15)
	row.add_child(value_label)

	var color := AppTheme.get_color("text_primary")
	rank_label.add_theme_color_override("font_color", color)
	name_label.add_theme_color_override("font_color", color)
	value_label.add_theme_color_override("font_color", color)

	return row


func _format_value(value: float) -> String:
	if _is_time_based:
		return TimeFormat.format_time(value)
	return str(int(value))


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)

	if _title_label:
		_title_label.add_theme_color_override("font_color", AppTheme.get_color("text_primary"))
	if _status_label:
		_status_label.add_theme_color_override("font_color", AppTheme.get_color("text_primary"))
	if _player_label:
		_player_label.add_theme_color_override("font_color", AppTheme.get_color("text_primary"))
