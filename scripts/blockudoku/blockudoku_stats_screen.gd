extends Control

## Blockudoku statistics display

@onready var back_button: Button = %BackButton
@onready var stats_list: VBoxContainer = %StatsList

const ScoreHistoryGraph := preload("res://scripts/blockudoku/score_history_graph.gd")


func _ready() -> void:
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/blockudoku_menu.tscn")
	)
	_build_stats_ui()
	_apply_theme()
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


func _build_stats_ui() -> void:
	for child in stats_list.get_children():
		child.queue_free()

	_add_header("Blockudoku Stats")
	var score_history: Array = BlockudokuStatsManager.get_score_history()

	_add_stat_row("Games Played", str(BlockudokuStatsManager.games_played))
	_add_stat_row("High Score", str(BlockudokuStatsManager.high_score))
	_add_stat_row("Best Turns", str(BlockudokuStatsManager.best_turns) if BlockudokuStatsManager.best_turns > 0 else "--")

	var avg_turns := BlockudokuStatsManager.get_average_turns()
	_add_stat_row("Average Turns", "%.1f" % avg_turns if avg_turns > 0 else "--")

	_add_stat_row("Total Score", str(BlockudokuStatsManager.total_score))
	_add_stat_row("Total Turns", str(BlockudokuStatsManager.total_turns))
	_add_stat_row("Total Lines Cleared", str(BlockudokuStatsManager.total_clears))
	_add_stat_row("Average Score", "%.1f" % BlockudokuStatsManager.get_average_score() if not score_history.is_empty() else "--")

	_add_separator()
	_add_header("Score History (Last 30 Games)")

	if score_history.is_empty():
		_add_stat_row("History", "No completed games yet")
	else:
		var graph := ScoreHistoryGraph.new()
		graph.custom_minimum_size = Vector2(0, 220)
		graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		graph.set_scores(score_history)
		stats_list.add_child(graph)

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
	stats_list.add_child(label)


func _add_stat_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	stats_list.add_child(row)


func _add_separator() -> void:
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 10)
	stats_list.add_child(sep)


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("background")
	add_theme_stylebox_override("panel", style)


func _on_reset_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Reset Statistics"
	dialog.dialog_text = "Are you sure? This will permanently\ndelete all Blockudoku statistics."
	dialog.ok_button_text = "Reset"
	dialog.cancel_button_text = "Cancel"
	dialog.min_size = Vector2i(300, 0)
	add_child(dialog)
	dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		BlockudokuStatsManager.reset_all()
		_build_stats_ui()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
