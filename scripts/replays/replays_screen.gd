extends Control

## Replay collection viewer — browse, bookmark, delete, and (future) play back replays.

@onready var back_button: Button = %BackButton
@onready var replay_list: VBoxContainer = %ReplayList


func _ready() -> void:
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/game_picker.tscn")
	)
	_build_ui()
	_apply_theme()
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


func _build_ui() -> void:
	for child in replay_list.get_children():
		child.queue_free()

	var replays := ReplayManager.get_recent_replays(50)
	if replays.is_empty():
		var empty_label := Label.new()
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
		_add_section_header("🎥 Bookmarked")
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
	header.text = title
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", ThemeManager.get_color("text_given"))
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
	panel.custom_minimum_size = Vector2(0, 80)
	replay_list.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	# Left: game info
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var title := Label.new()
	var bookmark_prefix := "🎥 " if is_bookmarked else ""
	title.text = "%s%s — %s" % [bookmark_prefix, game_mode.capitalize(), outcome]
	title.add_theme_font_size_override("font_size", 16)
	info.add_child(title)

	var details := Label.new()
	var time_str := _format_time(duration)
	var date_str := _format_date(timestamp)
	details.text = "Score: %d  |  %s  |  %s" % [score, time_str, date_str]
	details.add_theme_font_size_override("font_size", 13)
	info.add_child(details)

	# Right: delete button
	var delete_btn := Button.new()
	delete_btn.text = "✕"
	delete_btn.custom_minimum_size = Vector2(36, 36)
	delete_btn.pressed.connect(func() -> void:
		ReplayManager.delete_replay(replay_id)
		_build_ui()
	)
	row.add_child(delete_btn)


func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%d:%02d" % [mins, secs]


func _format_date(unix_time: int) -> String:
	if unix_time == 0:
		return "Unknown"
	var dt := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%d/%d/%d" % [dt.get("month", 0), dt.get("day", 0), dt.get("year", 0) % 100]


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("background")
	add_theme_stylebox_override("panel", style)
