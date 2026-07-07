extends Control

## Statistics display screen

const TimeFormat := preload("res://scripts/utils/time_format.gd")

@onready var back_button: Button = %BackButton
@onready var stats_list: VBoxContainer = %StatsList

const DIFFICULTY_NAMES := ["Easy", "Medium", "Hard", "Expert", "Evil"]


func _ready() -> void:
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(Scenes.SUDOKU_MENU)
	)
	_build_stats_ui()
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


func _build_stats_ui() -> void:
	for child in stats_list.get_children():
		child.queue_free()

	# Global stats
	_add_header("Overall")
	var total_games: int = GameStatsManager.get_counter("sudoku", "games_started")
	var current_streak: int = GameStatsManager.get_counter("sudoku", "current_streak")
	var best_streak: int = GameStatsManager.get_counter("sudoku", "best_streak")
	_add_stat_row("Total Games", str(total_games))
	_add_stat_row("Current Streak", str(current_streak))
	_add_stat_row("Best Streak", str(best_streak))

	_add_separator()

	# Per-difficulty stats
	for d in range(5):
		_add_header(DIFFICULTY_NAMES[d])

		var best_ms: int = GameStatsManager.get_counter("sudoku", "best_d%d" % d)
		var best: float = float(best_ms) / 1000.0 if best_ms > 0 else -1.0
		_add_stat_row("Best Time", TimeFormat.format_time(best, true) if best >= 0 else "--")

		# Average from history
		var history: Array = _get_time_history_for_difficulty(d)
		var avg: float = _compute_average(history)
		_add_stat_row("Average Time", TimeFormat.format_time(avg, true) if avg >= 0 else "--")

		if not history.is_empty():
			_add_time_graph(history)

		var started: int = GameStatsManager.get_counter("sudoku", "started_d%d" % d)
		var completed: int = GameStatsManager.get_counter("sudoku", "completed_d%d" % d)
		var abandoned: int = GameStatsManager.get_counter("sudoku", "abandoned_d%d" % d)
		_add_stat_row("Started / Completed", "%d / %d" % [started, completed])
		_add_stat_row("Abandoned", str(abandoned))

		var won: int = GameStatsManager.get_counter("sudoku", "won_d%d" % d)
		var lost: int = GameStatsManager.get_counter("sudoku", "lost_d%d" % d)
		_add_stat_row("Strict W/L", "%d / %d" % [won, lost])

		var rate: float = (float(completed) / float(started) * 100.0) if started > 0 else 0.0
		_add_stat_row("Completion Rate", "%.0f%%" % rate)

		_add_separator()

	# Reset button at the bottom
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


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)


func _on_reset_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Reset Statistics"
	dialog.dialog_text = "Are you sure? This will permanently delete all statistics."
	dialog.ok_button_text = "Reset"
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		GameStatsManager.clear("sudoku")
		_build_stats_ui()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())


func _get_time_history_for_difficulty(d: int) -> Array:
	var all_history: Array = GameStatsManager.get_history("sudoku")
	var times: Array = []
	for entry in all_history:
		if entry is Dictionary and entry.get("difficulty") == d and entry.has("time"):
			times.append(entry["time"])
	return times


func _compute_average(times: Array) -> float:
	if times.is_empty():
		return -1.0
	var total := 0.0
	for t in times:
		total += float(t)
	return total / float(times.size())
