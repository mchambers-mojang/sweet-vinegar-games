class_name LeaderboardPanel
extends PanelContainer

## Leaderboard display panel for Game Menu screens.
## Shows top 10 players and the current player's rank for a given game:mode.
## Call refresh(game_id, mode, is_time_based) to load data.
## Shows a loading state while fetching; shows a fallback message on error.

const TimeFormat := preload("res://scripts/utils/time_format.gd")

## How long (seconds) a cached response is considered fresh.
const CACHE_TTL := 30.0

@onready var _header: Label = %HeaderLabel
@onready var _status_label: Label = %StatusLabel
@onready var _entry_list: VBoxContainer = %EntryList
@onready var _footer_label: Label = %FooterLabel
@onready var _http: HTTPRequest = $HTTPRequest

## Cache: key "game:mode" → { time: float, data: Dictionary }
var _cache: Dictionary = {}
## Key that was sent with the in-flight request; used to discard stale responses.
var _inflight_key: String = ""
var _current_key: String = ""
var _is_time_based: bool = true


func _ready() -> void:
	_http.request_completed.connect(_on_request_completed)
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


## Load (or refresh) the leaderboard for a given game and mode.
## Pass is_time_based = true for time boards (MM:SS.cc), false for score boards.
## Pass an empty mode string to hide the panel entirely (no leaderboard for this mode).
func refresh(game_id: String, mode: String, is_time_based: bool) -> void:
	if mode.is_empty():
		visible = false
		return
	visible = true
	_is_time_based = is_time_based
	var key := "%s:%s" % [game_id, mode]
	_current_key = key

	# Serve from cache when fresh
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
		PlayerIdentity.REST_BASE_URL, game_id, mode, device_id,
	]
	_inflight_key = key
	if _http.request(url) != OK:
		_show_error()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	# Discard responses for modes the player has since navigated away from.
	if _inflight_key != _current_key:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_show_error()
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		_show_error()
		return
	_cache[_current_key] = {
		"time": Time.get_unix_time_from_system(),
		"data": parsed,
	}
	_show_data(parsed)


func _show_loading() -> void:
	_status_label.visible = true
	_status_label.text = "Loading…"
	_entry_list.visible = false
	_footer_label.visible = false


func _show_error() -> void:
	_status_label.visible = true
	_status_label.text = "Leaderboard unavailable"
	_entry_list.visible = false
	_footer_label.visible = false


func _show_data(data: Dictionary) -> void:
	var top: Array = data.get("top", [])
	var player_rank = data.get("player_rank", null)
	var player_score = data.get("player_score", null)

	_status_label.visible = false
	_entry_list.visible = true

	# Rebuild entry rows
	for child in _entry_list.get_children():
		child.queue_free()

	var device_id: String = PlayerIdentity.device_id
	var player_in_top := false

	for entry in top:
		var is_player: bool = entry.get("device_id", "") == device_id
		if is_player:
			player_in_top = true
		_entry_list.add_child(_make_row(entry, is_player))

	# Footer: player rank when outside top 10
	if player_in_top:
		_footer_label.visible = false
	elif player_rank == null:
		_footer_label.visible = true
		_footer_label.text = "Play to get ranked!"
	else:
		_footer_label.visible = true
		_footer_label.text = "Your rank: #%d (%s)" % [
			int(player_rank), _format_value(player_score),
		]


func _make_row(entry: Dictionary, is_player: bool) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	var rank_lbl := Label.new()
	var raw_rank = entry.get("rank", 0)
	rank_lbl.text = "#%-3d" % int(raw_rank)
	rank_lbl.custom_minimum_size = Vector2(40, 0)
	rank_lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(rank_lbl)

	var name_lbl := Label.new()
	name_lbl.text = str(entry.get("display_name", ""))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = _format_value(entry.get("value", null))
	val_lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(val_lbl)

	if is_player:
		var highlight_color: Color = AppTheme.get_color("text_placed")
		for lbl: Label in [rank_lbl, name_lbl, val_lbl]:
			lbl.add_theme_color_override("font_color", highlight_color)

	return hbox


func _format_value(value) -> String:
	if value == null:
		return "--"
	if not (value is int or value is float):
		return "--"
	if _is_time_based:
		return TimeFormat.format_time(float(value), true)
	return str(int(value))


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("cell_background")
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)

	_header.add_theme_color_override("font_color", AppTheme.get_color("text_given"))
	_status_label.add_theme_color_override("font_color", AppTheme.get_color("text_pencil"))
	_footer_label.add_theme_color_override("font_color", AppTheme.get_color("text_pencil"))

