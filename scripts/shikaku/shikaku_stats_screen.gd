extends Control

## Shikaku statistics display screen

@onready var back_button: Button = %BackButton
@onready var stats_list: VBoxContainer = %StatsList

const SIZE_NAMES := {5: "5×5", 7: "7×7", 8: "8×8", 10: "10×10", 12: "12×12", 15: "15×15"}
const SIZES := [5, 7, 8, 10, 12, 15]


func _ready() -> void:
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/shikaku_menu.tscn")
	)
	_build_stats_ui()
	_apply_theme()
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


func _build_stats_ui() -> void:
	for child in stats_list.get_children():
		child.queue_free()

	# Global stats
	_add_header("Overall")
	_add_stat_row("Total Games", str(ShikakuStatsManager.total_games_played))
	_add_stat_row("Current Streak", str(ShikakuStatsManager.current_streak))
	_add_stat_row("Best Streak", str(ShikakuStatsManager.best_streak))

	_add_separator()

	# Per-size stats
	for s in SIZES:
		_add_header(SIZE_NAMES[s])

		var best: float = ShikakuStatsManager.best_times.get(s, -1.0)
		_add_stat_row("Best Time", _format_time(best) if best >= 0 else "--")

		var avg := ShikakuStatsManager.get_average_time(s)
		_add_stat_row("Average Time", _format_time(avg) if avg >= 0 else "--")

		# Time history graph
		var history := ShikakuStatsManager.get_time_history(s)
		if not history.is_empty():
			_add_time_graph(history)

		var started: int = ShikakuStatsManager.games_started.get(s, 0)
		var completed: int = ShikakuStatsManager.games_completed.get(s, 0)
		var abandoned: int = ShikakuStatsManager.games_abandoned.get(s, 0)
		_add_stat_row("Started / Completed", "%d / %d" % [started, completed])
		_add_stat_row("Abandoned", str(abandoned))

		var rate := ShikakuStatsManager.get_completion_rate(s)
		_add_stat_row("Completion Rate", "%.0f%%" % rate)

		_add_separator()

	# Reset button
	var reset_btn := Button.new()
	reset_btn.text = "Reset All Statistics"
	reset_btn.custom_minimum_size = Vector2(0, 44)
	reset_btn.pressed.connect(_on_reset_pressed)
	stats_list.add_child(reset_btn)


func _add_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	stats_list.add_child(label)


func _add_stat_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(value)
	stats_list.add_child(row)


func _add_separator() -> void:
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 10)
	sep.mouse_filter = Control.MOUSE_FILTER_PASS
	stats_list.add_child(sep)


func _add_time_graph(times: Array) -> void:
	var graph_script := load("res://scripts/ui/time_history_graph.gd")
	var graph := Control.new()
	graph.set_script(graph_script)
	graph.custom_minimum_size = Vector2(0, 100)
	graph.mouse_filter = Control.MOUSE_FILTER_PASS
	stats_list.add_child(graph)
	graph.set_times(times)


func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%d:%02d" % [mins, secs]


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("background")
	add_theme_stylebox_override("panel", style)


func _on_reset_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Reset Statistics"
	dialog.dialog_text = "Are you sure? This will permanently\ndelete all Shikaku statistics."
	dialog.ok_button_text = "Reset"
	dialog.cancel_button_text = "Cancel"
	dialog.min_size = Vector2i(300, 0)
	add_child(dialog)
	dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		ShikakuStatsManager.reset_all()
		_build_stats_ui()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
