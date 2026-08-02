extends Control
class_name CrownGridStatsScreen

## Crown Grid statistics display screen

const TimeFormat := preload("res://scripts/utils/time_format.gd")
const CROWN_GRID_MENU_SCENE := "res://scenes/crown_grid_menu.tscn"

@onready var back_button: Button = %BackButton
@onready var stats_list: VBoxContainer = %StatsList

const TIER_NAMES := ["Easy", "Medium", "Hard", "Expert"]
const TIER_SIZES := [6, 7, 8, 9]


func _ready() -> void:
	back_button.pressed.connect(func() -> void:
		SceneTransition.navigate(CROWN_GRID_MENU_SCENE)
	)
	_build_stats_ui()
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


func _build_stats_ui() -> void:
	for child in stats_list.get_children():
		child.queue_free()

	_add_header("Overall")
	var total := GameStatsManager.get_counter("crown_grid", "games_started")
	var streak := GameStatsManager.get_counter("crown_grid", "current_streak")
	var best_streak := GameStatsManager.get_counter("crown_grid", "best_streak")
	_add_stat_row("Total Games", str(total))
	_add_stat_row("Current Streak", str(streak))
	_add_stat_row("Best Streak", str(best_streak))
	_add_separator()

	for t in range(4):
		_add_header(TIER_NAMES[t] + " (%d×%d)" % [TIER_SIZES[t], TIER_SIZES[t]])

		var best_ms: int = GameStatsManager.get_counter("crown_grid", "best_t%d" % t)
		var best: float = float(best_ms) / 1000.0 if best_ms > 0 else -1.0
		_add_stat_row("Best Time", TimeFormat.format_time(best, true) if best >= 0 else "--")

		var history := _get_history_for_tier(t)
		var avg := _compute_avg(history)
		_add_stat_row("Average Time", TimeFormat.format_time(avg, true) if avg >= 0 else "--")

		if not history.is_empty():
			_add_time_graph(history)

		var started: int = GameStatsManager.get_counter("crown_grid", "started_t%d" % t)
		var completed: int = GameStatsManager.get_counter("crown_grid", "completed_t%d" % t)
		_add_stat_row("Started / Completed", "%d / %d" % [started, completed])
		var rate: float = (float(completed) / float(started) * 100.0) if started > 0 else 0.0
		_add_stat_row("Completion Rate", "%.0f%%" % rate)
		_add_separator()

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
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(val)
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
	dialog.dialog_text = "Are you sure? This will permanently\ndelete all Crown Grid statistics."
	dialog.ok_button_text = "Reset"
	dialog.cancel_button_text = "Cancel"
	dialog.min_size = Vector2i(300, 0)
	add_child(dialog)
	dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		GameStatsManager.clear("crown_grid")
		_build_stats_ui()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())


func _get_history_for_tier(t: int) -> Array:
	var all_history: Array = GameStatsManager.get_history("crown_grid")
	var result: Array = []
	for entry in all_history:
		if entry is Dictionary and entry.get("tier") == t and entry.has("time"):
			result.append(entry["time"])
	return result


func _compute_avg(times: Array) -> float:
	if times.is_empty():
		return -1.0
	var total := 0.0
	for t in times:
		total += float(t)
	return total / float(times.size())
