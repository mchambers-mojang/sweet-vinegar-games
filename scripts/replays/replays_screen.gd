extends Control

const TimeFormat := preload("res://scripts/utils/time_format.gd")

## Replay collection viewer — browse, bookmark, delete, and (future) play back replays.

@onready var back_button: Button = %BackButton
@onready var replay_list: VBoxContainer = %ReplayList


func _ready() -> void:
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(Scenes.GAME_PICKER)
	)
	_build_ui()
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


func _build_ui() -> void:
	for child in replay_list.get_children():
		child.queue_free()

	# Import button at top
	var import_btn := Button.new()
	import_btn.text = "📋 Import Replay Code"
	import_btn.custom_minimum_size = Vector2(0, 44)
	import_btn.pressed.connect(_import_from_clipboard)
	replay_list.add_child(import_btn)

	var replays := ReplayStorage.get_recent_replays(50)
	if replays.is_empty():
		var empty_label := Label.new()
		empty_label.mouse_filter = Control.MOUSE_FILTER_PASS
		empty_label.text = "No replays yet.\nFinish a game to record one!"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		replay_list.add_child(empty_label)
		return

	# Show bookmarked first, then recent (newest first)
	var bookmarked: Array[Dictionary] = []
	var recent: Array[Dictionary] = []
	for replay in replays:
		if replay.get("bookmarked", false):
			bookmarked.append(replay)
		else:
			recent.append(replay)

	if not bookmarked.is_empty():
		_add_section_header("Bookmarked")
		bookmarked.reverse()
		for replay in bookmarked:
			_add_replay_row(replay)

	if not recent.is_empty():
		_add_section_header("Recent")
		recent.reverse()
		for replay in recent:
			_add_replay_row(replay)


func _add_section_header(title: String) -> void:
	var header := Label.new()
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header.text = title
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", AppTheme.get_color("text_given"))
	replay_list.add_child(header)


func _add_replay_row(replay: Dictionary) -> void:
	var header: Dictionary = replay.get("header", {})
	var footer: Dictionary = replay.get("footer", {})
	var replay_id := str(replay.get("id", ""))

	var game_mode := str(header.get("game_mode", "unknown"))
	var timestamp := int(header.get("timestamp", 0))
	var score := int(footer.get("final_score", 0))
	var duration := float(footer.get("duration", 0.0))
	var outcome := str(footer.get("outcome", ""))
	var is_bookmarked := bool(replay.get("bookmarked", false))

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	replay_list.add_child(panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Top line: game info
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	var bookmark_prefix := "[Saved] " if is_bookmarked else ""
	title.text = "%s%s — %s" % [bookmark_prefix, game_mode.capitalize(), outcome]
	title.add_theme_font_size_override("font_size", 16)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(title)

	var details := Label.new()
	details.mouse_filter = Control.MOUSE_FILTER_PASS
	var time_str := TimeFormat.format_time(duration, true)
	var date_str := _format_date(timestamp)
	details.text = "Score: %d  |  %s  |  %s" % [score, time_str, date_str]
	details.add_theme_font_size_override("font_size", 13)
	details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(details)

	# Bottom line: action buttons
	var btn_row := HBoxContainer.new()
	btn_row.mouse_filter = Control.MOUSE_FILTER_PASS
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	# Play button — all supported games use the generic replay viewer
	var can_play := game_mode in ["blockudoku", "shikaku", "sudoku"]
	if can_play:
		var play_btn := Button.new()
		play_btn.text = "▶ Play"
		play_btn.custom_minimum_size = Vector2(0, 36)
		play_btn.pressed.connect(func() -> void:
			var full_replay := ReplayStorage.get_replay_by_id(replay_id)
			ReplayStorage.set_pending_playback(full_replay)
			SceneTransition.transition_to(Scenes.REPLAY_VIEWER)
		)
		btn_row.add_child(play_btn)

	# Share button
	var share_btn := Button.new()
	share_btn.text = "📤 Share"
	share_btn.custom_minimum_size = Vector2(0, 36)
	share_btn.pressed.connect(func() -> void:
		var code := ReplayStorage.export_replay_code(replay_id)
		if code.is_empty():
			return
		DisplayServer.clipboard_set(code)
		_show_toast("Replay code copied!")
	)
	btn_row.add_child(share_btn)

	# Delete button
	var delete_btn := Button.new()
	delete_btn.text = "✕"
	delete_btn.custom_minimum_size = Vector2(36, 36)
	delete_btn.pressed.connect(func() -> void:
		ReplayStorage.delete_replay(replay_id)
		_build_ui()
	)
	btn_row.add_child(delete_btn)


func _format_date(unix_time: int) -> String:
	if unix_time == 0:
		return "Unknown"
	var dt := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%d/%d/%d" % [dt.get("month", 0), dt.get("day", 0), dt.get("year", 0) % 100]


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)


func _import_from_clipboard() -> void:
	var code := DisplayServer.clipboard_get().strip_edges()
	if code.is_empty():
		_show_toast("Clipboard is empty")
		return
	var replay := ReplayStorage.import_replay_code(code)
	if replay.is_empty():
		_show_toast("Invalid replay code")
		return
	# Determine game mode and play it
	var header: Dictionary = replay.get("header", {})
	var game_mode := str(header.get("game_mode", ""))
	if game_mode not in ["blockudoku", "shikaku", "sudoku"]:
		_show_toast("Unknown game mode: %s" % game_mode)
		return
	ReplayStorage.set_pending_playback(replay)
	SceneTransition.transition_to(Scenes.REPLAY_VIEWER)


func _show_toast(message: String) -> void:
	var toast := Label.new()
	toast.text = message
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 14)
	toast.add_theme_color_override("font_color", AppTheme.get_color("text_given"))
	toast.modulate.a = 1.0
	add_child(toast)
	toast.anchors_preset = Control.PRESET_CENTER_BOTTOM
	toast.position.y -= 60
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(toast, "modulate:a", 0.0, 0.5)
	tween.tween_callback(toast.queue_free)
