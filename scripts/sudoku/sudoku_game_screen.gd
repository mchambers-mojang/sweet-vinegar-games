extends Control

## Main game screen — contains the board, controls, timer, and all game logic

# Game state
var puzzle: Array[int] = []
var solution: Array[int] = []
var current_grid: Array[int] = []
var difficulty: int = 0
var elapsed_time: float = 0.0
var strikes: int = 0
var is_failed: bool = false
var is_completed: bool = false
var _can_continue_after_failure: bool = false
var is_paused: bool = false
var hints_used: int = 0
var notes_mode: bool = false

# Cheat auto-solve
var _cheat_active: bool = false
var _cheat_timer: float = 0.0
const CHEAT_INTERVAL := 0.5

# Undo/redo
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []

# Node references
@onready var board: SudokuBoard = %Board
@onready var timer_label: Label = %TimerLabel
@onready var strikes_container: HBoxContainer = %StrikesContainer
@onready var difficulty_label: Label = %DifficultyLabel
@onready var notes_button: Button = %NotesButton
@onready var hint_button: Button = %HintButton
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var erase_button: Button = %EraseButton
@onready var number_container: HBoxContainer = %NumberContainer
@onready var color_container: HBoxContainer = %ColorContainer
@onready var pause_button: Button = %PauseButton
@onready var back_button: Button = %BackButton

# Color palette for cell coloring
const CELL_COLORS: Array[Color] = [
	Color.TRANSPARENT,          # Clear
	Color(1.0, 0.85, 0.85),    # Light red
	Color(1.0, 0.93, 0.8),     # Light orange
	Color(1.0, 1.0, 0.8),      # Light yellow
	Color(0.85, 1.0, 0.85),    # Light green
	Color(0.85, 0.93, 1.0),    # Light blue
	Color(0.93, 0.85, 1.0),    # Light purple
]

# Darker palette for neon mode — avoids bloom washing out distinctions
const NEON_CELL_COLORS: Array[Color] = [
	Color.TRANSPARENT,          # Clear
	Color(0.4, 0.1, 0.1),      # Dark red
	Color(0.4, 0.25, 0.08),    # Dark orange
	Color(0.35, 0.35, 0.08),   # Dark yellow
	Color(0.1, 0.35, 0.1),     # Dark green
	Color(0.1, 0.2, 0.4),      # Dark blue
	Color(0.25, 0.1, 0.4),     # Dark purple
]

const DIFFICULTY_NAMES := ["Easy", "Medium", "Hard", "Expert", "Evil"]

var _number_buttons: Array[Button] = []
var _strike_indicators: Array[Control] = []
var _color_buttons: Array[Button] = []
var _last_color_press_time: float = 0.0
var _last_color_pressed: Color = Color.TRANSPARENT
const DOUBLE_CLICK_TIME := 0.4
var _multi_selected_color: Color = Color.TRANSPARENT  # Active multi-selection color
var _last_cell_press_time: float = 0.0
var _last_cell_pressed: int = -1
var _selected_number: int = 0  # For number-first mode


func _ready() -> void:
	board.cell_selected.connect(_on_cell_selected)
	notes_button.pressed.connect(_on_notes_pressed)
	hint_button.pressed.connect(_on_hint_pressed)
	undo_button.pressed.connect(_on_undo_pressed)
	redo_button.pressed.connect(_on_redo_pressed)
	erase_button.pressed.connect(_on_erase_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	back_button.pressed.connect(_on_back_pressed)

	_setup_number_buttons()
	_setup_color_buttons()
	_setup_strike_indicators()
	_setup_help_button()
	_update_button_states()

	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_theme())
	_apply_theme()

	# Adjust for mobile safe area (notch, status bar)
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)

	# Cosmetic drag effect is now a global autoload


func _setup_help_button() -> void:
	var btn := Button.new()
	btn.text = "?"
	btn.custom_minimum_size = Vector2(36, 0)
	btn.pressed.connect(func() -> void: HowToPlay.show_for(self, "sudoku"))
	pause_button.get_parent().add_child(btn)


func start_new_game(diff: int) -> void:
	difficulty = diff
	difficulty_label.text = DIFFICULTY_NAMES[difficulty]

	var generator := SudokuGenerator.new()
	var result := generator.generate(difficulty)

	puzzle = []
	puzzle.assign(result["puzzle"])
	solution = []
	solution.assign(result["solution"])
	current_grid = []
	current_grid.assign(puzzle.duplicate())

	elapsed_time = 0.0
	strikes = 0
	is_failed = false
	is_completed = false
	_can_continue_after_failure = false
	is_paused = false
	hints_used = 0
	notes_mode = false
	undo_stack.clear()
	redo_stack.clear()

	board.load_puzzle(puzzle)
	_update_strikes_display()
	_update_button_states()
	_update_number_completion()

	StatsManager.record_game_started(difficulty)
	AnalyticsManager.log_event("game_started", {
		"game": "sudoku",
		"difficulty": difficulty,
	})
	_save_current_state()


func resume_game(data: Dictionary) -> void:
	puzzle = []
	puzzle.assign(data["puzzle"])
	solution = []
	solution.assign(data["solution"])
	current_grid = []
	current_grid.assign(data["current_grid"])
	difficulty = data["difficulty"]
	elapsed_time = data["elapsed_time"]
	strikes = data["strikes"]
	is_failed = data["is_failed"]
	_can_continue_after_failure = data.get("can_continue_after_failure", false)
	hints_used = data.get("hints_used", 0)
	is_completed = false
	is_paused = false
	notes_mode = false
	undo_stack.clear()
	redo_stack.clear()

	difficulty_label.text = DIFFICULTY_NAMES[difficulty]
	board.load_state(current_grid, puzzle, data.get("pencil_marks", {}), data.get("cell_colors", {}))
	_update_strikes_display()
	_update_button_states()
	_update_number_completion()
	if is_failed and _is_board_locked():
		# Re-show the fail dialog for failed saves so players can choose Continue/Menu.
		call_deferred("_show_fail_dialog")


func _process(delta: float) -> void:
	if not is_completed and not is_paused:
		elapsed_time += delta
		if SettingsManager.show_timer:
			timer_label.text = _format_time(elapsed_time)
			timer_label.visible = true
		else:
			timer_label.visible = false

		# Cheat auto-solve
		if _cheat_active:
			_cheat_timer += delta
			if _cheat_timer >= CHEAT_INTERVAL:
				_cheat_timer = 0.0
				_cheat_place_one()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_Q and key.ctrl_pressed and key.shift_pressed:
			_cheat_active = not _cheat_active
			_cheat_timer = 0.0
			print("Cheat auto-solve: %s" % ("ON" if _cheat_active else "OFF"))
			get_viewport().set_input_as_handled()


func _cheat_place_one() -> void:
	if _is_board_locked():
		_cheat_active = false
		return
	# Find all unsolved cells (empty or wrong) and pick one at random
	var unsolved_indices: Array[int] = []
	for i in 81:
		if current_grid[i] != solution[i]:
			unsolved_indices.append(i)
	if unsolved_indices.is_empty():
		_cheat_active = false
		return
	unsolved_indices.shuffle()
	var index := unsolved_indices[0]
	var number := solution[index]
	var cell := board.cells[index]

	# Select the cell visually
	board.select_cell(index)

	# Place the number through normal flow
	cell.set_value(number)
	cell.set_error(false)
	cell.set_cell_color(Color.TRANSPARENT)
	current_grid[index] = number
	if SettingsManager.auto_remove_pencil_marks:
		_remove_pencil_marks_for_number(index, number)
	_check_unit_completion(index)
	_update_number_completion()
	board._update_highlighting()
	if _check_win():
		_cheat_active = false
		_handle_win()
	_save_current_state()


func _on_cell_selected(index: int) -> void:
	if _is_board_locked():
		return

	var now := Time.get_ticks_msec() / 1000.0
	var cell := board.cells[index]

	# Double-click detection
	if index == _last_cell_pressed and (now - _last_cell_press_time) < DOUBLE_CLICK_TIME:
		if cell.cell_color != Color.TRANSPARENT:
			# Double-click on colored cell: multi-select all cells with same color
			_fill_colored_cells(cell.cell_color)
		else:
			# Double-click on non-colored cell: toggle row/col/box highlighting
			board.show_row_col_box = SettingsManager.highlight_row_col_box
			board._update_highlighting()
		_last_cell_pressed = -1
		return

	_last_cell_press_time = now
	_last_cell_pressed = index

	# Single click: clear row/col/box highlighting and filters
	board.show_row_col_box = false
	board.filter_number = 0
	board.filter_color = Color.TRANSPARENT

	# Clear multi-selection when tapping a different cell
	if _multi_selected_color != Color.TRANSPARENT:
		_clear_multi_selection()

	board._update_highlighting()

	if SettingsManager.input_mode == "number_first":
		_handle_number_first_cell_tap(index)
	_update_number_completion()


func _handle_number_first_cell_tap(index: int) -> void:
	if _selected_number == 0:
		return
	var cell := board.cells[index]
	if cell.is_given:
		return
	# Place the pre-selected number into this cell
	if notes_mode:
		_push_undo(index)
		cell.toggle_pencil_mark(_selected_number)
		redo_stack.clear()
	else:
		if cell.value == _selected_number:
			return
		if SettingsManager.error_mode == "strict" and solution[index] != _selected_number:
			strikes += 1
			_update_strikes_display()
			_play_error_feedback()
			cell.set_value(_selected_number)
			cell.set_error(true)
			var revert_cell := cell

			# Neon glass shatter + shockwave on error
			if ThemeManager.is_neon:
				var cell_rect := board.get_cell_rect(index)
				GlassShatter.create(board, cell_rect, Color(2.0, 0.0, 0.2), 10)
				var err_center := cell_rect.position + cell_rect.size / 2.0
				NeonRing.create(board, err_center, Color(2.0, 0.0, 0.2), cell_rect.size.x * 2.5, 0.2, 0.4)
				NeonFxManager.screen_shake(5.0, 0.15)

			var revert_tween := create_tween()
			revert_tween.tween_interval(0.4)
			revert_tween.tween_callback(func() -> void:
				revert_cell.value = 0
				revert_cell.is_error = false
				revert_cell.queue_redraw()
			)
			if strikes >= 4 and not is_failed:
				is_failed = true
				_can_continue_after_failure = false
				_update_button_states()
				AnalyticsManager.log_event("game_over", {
					"game": "sudoku",
					"won": false,
					"difficulty": difficulty,
					"elapsed_time": elapsed_time,
					"strikes": strikes,
				})
				_show_fail_dialog()
			_save_current_state()
			_update_number_completion()
			board._update_highlighting()
			return
		_push_undo(index)
		cell.set_value(_selected_number)
		cell.set_error(false)
		cell.set_cell_color(Color.TRANSPARENT)
		current_grid[index] = _selected_number
		redo_stack.clear()

		# Neon burst on correct placement
		if ThemeManager.is_neon:
			var cell_rect := board.get_cell_rect(index)
			var center := cell_rect.position + cell_rect.size / 2.0
			NeonBurst.create(board, center, Color(0.0, 2.0, 1.6), 10, 0.8)

		if SettingsManager.auto_remove_pencil_marks:
			_remove_pencil_marks_for_number(index, _selected_number)
		_check_unit_completion(index)
		_update_number_completion()
		board._update_highlighting()
		if _check_win():
			_handle_win()
	_save_current_state()


func _on_number_pressed(number: int) -> void:
	if _is_board_locked():
		return

	# If multi-selection is active, apply to all selected cells
	if _multi_selected_color != Color.TRANSPARENT:
		_apply_number_to_multi_selection(number)
		return

	if SettingsManager.input_mode == "cell_first":
		_place_or_note_number(number)
	else:
		# Number-first mode: just select the number, wait for cell tap
		_select_number_button(number)


func _place_or_note_number(number: int) -> void:
	var index := board.selected_index
	if index < 0:
		if notes_mode:
			# No cell selected: toggle number filter highlighting
			board.filter_number = number if board.filter_number != number else 0
			board.filter_color = Color.TRANSPARENT
			board._update_highlighting()
		return
	var cell := board.cells[index]
	if cell.is_given:
		return

	if notes_mode:
		_push_undo(index)
		cell.toggle_pencil_mark(number)
		redo_stack.clear()
		SoundManager.play_pencil()
		HapticManager.vibrate_light()
	else:
		if cell.value == number:
			return  # Already placed

		# Lock correctly placed cells in strict mode
		if SettingsManager.error_mode == "strict" and cell.value != 0 and cell.value == solution[index]:
			return

		# Check if correct in strict mode
		if SettingsManager.error_mode == "strict" and solution[index] != number:
			strikes += 1
			_update_strikes_display()
			_play_error_feedback()
			# Briefly flash the wrong number then revert
			cell.set_value(number)
			cell.set_error(true)
			var revert_cell := cell

			# Neon glass shatter + shockwave on error
			if ThemeManager.is_neon:
				var cell_rect := board.get_cell_rect(index)
				GlassShatter.create(board, cell_rect, Color(2.0, 0.0, 0.2), 10)
				var err_center := cell_rect.position + cell_rect.size / 2.0
				NeonRing.create(board, err_center, Color(2.0, 0.0, 0.2), cell_rect.size.x * 2.5, 0.2, 0.4)
				NeonFxManager.screen_shake(5.0, 0.15)

			var revert_tween := create_tween()
			revert_tween.tween_interval(0.4)
			revert_tween.tween_callback(func() -> void:
				revert_cell.value = 0
				revert_cell.is_error = false
				revert_cell.queue_redraw()
			)

			if strikes >= 4 and not is_failed:
				is_failed = true
				_can_continue_after_failure = false
				_update_button_states()
				AnalyticsManager.log_event("game_over", {
					"game": "sudoku",
					"won": false,
					"difficulty": difficulty,
					"elapsed_time": elapsed_time,
					"strikes": strikes,
				})
				_show_fail_dialog()
			_save_current_state()
			_update_number_completion()
			board._update_highlighting()
			return

		_push_undo(index)
		cell.set_value(number)
		cell.set_error(false)
		cell.set_cell_color(Color.TRANSPARENT)
		current_grid[index] = number
		redo_stack.clear()
		SoundManager.play_place()
		HapticManager.vibrate_light()

		# Neon burst on correct placement
		if ThemeManager.is_neon:
			var cell_rect := board.get_cell_rect(index)
			var center := cell_rect.position + cell_rect.size / 2.0
			NeonBurst.create(board, center, Color(0.0, 2.0, 1.6), 10, 0.8)

		# Auto-remove pencil marks if enabled
		if SettingsManager.auto_remove_pencil_marks:
			_remove_pencil_marks_for_number(index, number)

		_check_unit_completion(index)
		_update_number_completion()
		board._update_highlighting()

		if _check_win():
			_handle_win()

	_save_current_state()


func _on_notes_pressed() -> void:
	notes_mode = not notes_mode
	notes_button.text = "Notes: ON" if notes_mode else "Notes"
	color_container.modulate = Color(1, 1, 1, 1) if notes_mode else Color(1, 1, 1, 0)
	color_container.mouse_filter = Control.MOUSE_FILTER_STOP if notes_mode else Control.MOUSE_FILTER_IGNORE
	_update_button_states()


func _on_hint_pressed() -> void:
	if _is_board_locked() or hints_used >= 1:
		return

	var index: int = -1

	# Use selected cell if it's unsolved
	if board.selected_index >= 0:
		var sel := board.selected_index
		var sel_cell := board.cells[sel]
		if not sel_cell.is_given and current_grid[sel] != solution[sel]:
			index = sel

	# Otherwise pick a random unsolved cell
	if index < 0:
		var empty_cells: Array[int] = []
		for i in 81:
			if current_grid[i] == 0 or current_grid[i] != solution[i]:
				empty_cells.append(i)
		if empty_cells.is_empty():
			return
		empty_cells.shuffle()
		index = empty_cells[0]

	var cell := board.cells[index]
	board.selected_index = index

	_push_undo(index)
	cell.set_value(solution[index])
	cell.set_error(false)
	cell.is_given = false
	current_grid[index] = solution[index]
	hints_used += 1
	redo_stack.clear()
	hint_button.disabled = true

	if SettingsManager.auto_remove_pencil_marks:
		_remove_pencil_marks_for_number(index, solution[index])

	_check_unit_completion(index)
	_update_number_completion()
	board._update_highlighting()

	if _check_win():
		_handle_win()

	_save_current_state()


func _on_erase_pressed() -> void:
	if _is_board_locked():
		return
	var index := board.selected_index
	if index < 0:
		return
	var cell := board.cells[index]
	if cell.is_given:
		return
	# Don't allow erasing correctly placed cells in strict mode
	if SettingsManager.error_mode == "strict" and cell.value != 0 and cell.value == solution[index]:
		return

	_push_undo(index)
	cell.clear_cell()
	current_grid[index] = 0
	redo_stack.clear()
	SoundManager.play_erase()
	HapticManager.vibrate_light()
	_update_number_completion()
	board._update_highlighting()
	_save_current_state()


func _on_pause_pressed() -> void:
	is_paused = not is_paused
	pause_button.text = "Resume" if is_paused else "Pause"
	# Hide board when paused
	board.visible = not is_paused


func _on_back_pressed() -> void:
	_save_current_state()
	SceneTransition.transition_to("res://scenes/main_menu.tscn")


func _on_undo_pressed() -> void:
	if _is_board_locked():
		return
	if undo_stack.is_empty():
		return
	var state: Dictionary = undo_stack.pop_back()
	var index: int = state["index"]
	var cell := board.cells[index]

	# Save current state for redo
	redo_stack.append(_capture_cell_state(index))

	# Restore
	_restore_cell_state(cell, state)
	current_grid[index] = cell.value
	_update_button_states()
	_update_number_completion()
	board._update_highlighting()
	_save_current_state()


func _on_redo_pressed() -> void:
	if _is_board_locked():
		return
	if redo_stack.is_empty():
		return
	var state: Dictionary = redo_stack.pop_back()
	var index: int = state["index"]
	var cell := board.cells[index]

	# Save current state for undo
	undo_stack.append(_capture_cell_state(index))

	# Restore
	_restore_cell_state(cell, state)
	current_grid[index] = cell.value
	_update_button_states()
	_update_number_completion()
	board._update_highlighting()
	_save_current_state()


func _push_undo(index: int) -> void:
	undo_stack.append(_capture_cell_state(index))
	_update_button_states()


func _capture_cell_state(index: int) -> Dictionary:
	var cell := board.cells[index]
	return {
		"index": index,
		"value": cell.value,
		"is_error": cell.is_error,
		"pencil_marks": cell.pencil_marks.duplicate(),
		"cell_color": cell.cell_color,
	}


func _restore_cell_state(cell: SudokuCell, state: Dictionary) -> void:
	cell.value = state["value"]
	cell.is_error = state["is_error"]
	cell.pencil_marks = state["pencil_marks"].duplicate()
	cell.cell_color = state["cell_color"]
	cell.queue_redraw()


func _remove_pencil_marks_for_number(placed_index: int, number: int) -> void:
	var row := placed_index / 9
	var col := placed_index % 9
	var box_row := (row / 3) * 3
	var box_col := (col / 3) * 3

	for i in 9:
		board.cells[row * 9 + i].set_pencil_mark(number, false)
		board.cells[i * 9 + col].set_pencil_mark(number, false)
		var br := box_row + i / 3
		var bc := box_col + i % 3
		board.cells[br * 9 + bc].set_pencil_mark(number, false)


func _check_win() -> bool:
	for i in 81:
		if current_grid[i] != solution[i]:
			return false
	return true


func _handle_win() -> void:
	is_completed = true
	var won := not is_failed
	StatsManager.record_game_completed(difficulty, elapsed_time, SettingsManager.error_mode == "strict", won)
	AnalyticsManager.log_event("game_over", {
		"game": "sudoku",
		"won": won,
		"difficulty": difficulty,
		"elapsed_time": elapsed_time,
		"strikes": strikes,
		"hints_used": hints_used,
	})
	SaveManager.clear_save()
	_play_win_celebration()


func _play_win_celebration() -> void:
	SoundManager.play_win()
	HapticManager.vibrate_success()
	# Neon win shockwave from board center
	if ThemeManager.is_neon:
		var center_rect := board.get_cell_rect(40)  # Center cell (row 4, col 4)
		var center := center_rect.position + center_rect.size / 2.0
		NeonRing.create(board, center, Color(0.0, 2.0, 1.5), center_rect.size.x * 8.0, 0.5, 1.2)
		NeonFxManager.screen_shake(6.0, 0.2)
	# Cascade reveal: flash each cell in sequence from top-left to bottom-right
	var tween := create_tween()
	for i in 81:
		var cell := board.cells[i]
		tween.tween_callback(func() -> void:
			cell.flash(Color(1.0, 0.85, 0.4), 0.25)
		).set_delay(0.018)
	# Show win dialog after cascade completes
	tween.tween_callback(_show_win_dialog).set_delay(0.5)


func _check_unit_completion(index: int) -> void:
	var row := index / 9
	var col := index % 9
	var box_row := (row / 3) * 3
	var box_col := (col / 3) * 3
	var flash_indices: Dictionary = {}  # Use as set to deduplicate

	# Check row
	var row_complete := true
	for c in 9:
		if current_grid[row * 9 + c] == 0 or current_grid[row * 9 + c] != solution[row * 9 + c]:
			row_complete = false
			break
	if row_complete:
		for c in 9:
			flash_indices[row * 9 + c] = true

	# Check column
	var col_complete := true
	for r in 9:
		if current_grid[r * 9 + col] == 0 or current_grid[r * 9 + col] != solution[r * 9 + col]:
			col_complete = false
			break
	if col_complete:
		for r in 9:
			flash_indices[r * 9 + col] = true

	# Check box
	var box_complete := true
	for r in range(box_row, box_row + 3):
		for c in range(box_col, box_col + 3):
			if current_grid[r * 9 + c] == 0 or current_grid[r * 9 + c] != solution[r * 9 + c]:
				box_complete = false
				break
	if box_complete:
		for r in range(box_row, box_row + 3):
			for c in range(box_col, box_col + 3):
				flash_indices[r * 9 + c] = true

	# Flash all unique cells once
	if not flash_indices.is_empty():
		SoundManager.play_unit_complete()
		for idx in flash_indices.keys():
			board.cells[idx].flash(Color(1.0, 0.85, 0.4), 0.35)
		# Neon shockwave from center of completed unit
		if ThemeManager.is_neon:
			var avg_x := 0.0
			var avg_y := 0.0
			for idx in flash_indices.keys():
				var cell_rect := board.get_cell_rect(idx)
				avg_x += cell_rect.position.x + cell_rect.size.x / 2.0
				avg_y += cell_rect.position.y + cell_rect.size.y / 2.0
			var center := Vector2(avg_x / flash_indices.size(), avg_y / flash_indices.size())
			NeonRing.create(board, center, Color(0.0, 2.0, 1.5), board.get_cell_rect(0).size.x * 4.0, 0.35, 0.6)

			# Neon sweep on completed rows
			if row_complete:
				var first := board.get_cell_rect(row * 9)
				var last := board.get_cell_rect(row * 9 + 8)
				var sweep_rect := Rect2(first.position, Vector2(last.position.x + last.size.x - first.position.x, first.size.y))
				NeonSweep.create(board, sweep_rect, true, Color(0.0, 2.0, 1.5))

			# Neon sweep on completed columns
			if col_complete:
				var first := board.get_cell_rect(col)
				var last := board.get_cell_rect(72 + col)
				var sweep_rect := Rect2(first.position, Vector2(first.size.x, last.position.y + last.size.y - first.position.y))
				NeonSweep.create(board, sweep_rect, false, Color(2.0, 0.3, 1.8))

			# Neon sweep on completed box
			if box_complete:
				var first := board.get_cell_rect(box_row * 9 + box_col)
				var last := board.get_cell_rect((box_row + 2) * 9 + box_col + 2)
				var sweep_rect := Rect2(first.position, Vector2(last.position.x + last.size.x - first.position.x, last.position.y + last.size.y - first.position.y))
				NeonSweep.create(board, sweep_rect, true, Color(1.5, 0.2, 1.0))


func _update_number_completion() -> void:
	var counts: Array[int] = []
	counts.resize(10)
	counts.fill(0)
	for i in 81:
		if current_grid[i] > 0:
			counts[current_grid[i]] += 1

	for i in range(9):
		if i < _number_buttons.size():
			var btn := _number_buttons[i]
			var num := i + 1
			btn.disabled = counts[num] >= 9
			if counts[num] >= 9:
				btn.modulate = Color(1, 1, 1, 0.3)
			else:
				btn.modulate = Color.WHITE


func _update_strikes_display() -> void:
	if SettingsManager.error_mode != "strict":
		strikes_container.visible = false
		return
	strikes_container.visible = true
	for i in range(_strike_indicators.size()):
		var indicator := _strike_indicators[i]
		if i < strikes:
			indicator.modulate = ThemeManager.get_color("strike_active")
		else:
			indicator.modulate = ThemeManager.get_color("strike_inactive")


func _update_button_states() -> void:
	var board_locked := _is_board_locked()
	undo_button.disabled = board_locked or undo_stack.is_empty()
	redo_button.disabled = board_locked or redo_stack.is_empty()
	erase_button.visible = SettingsManager.error_mode != "strict"
	hint_button.disabled = board_locked or hints_used >= 1


func _select_number_button(number: int) -> void:
	# Toggle: if same number pressed again, deselect
	if _selected_number == number:
		_selected_number = 0
	else:
		_selected_number = number
	# Update visual state of all number buttons
	for i in range(_number_buttons.size()):
		var btn := _number_buttons[i]
		var num := i + 1
		if num == _selected_number:
			btn.add_theme_color_override("font_color", ThemeManager.get_color("cell_selected"))
		else:
			btn.remove_theme_color_override("font_color")


func _play_error_feedback() -> void:
	SoundManager.play_error()
	HapticManager.vibrate_error()
	# Screen shake
	var original_pos := position
	var tween := create_tween()
	tween.tween_property(self, "position", original_pos + Vector2(4, 0), 0.04)
	tween.tween_property(self, "position", original_pos - Vector2(4, 0), 0.04)
	tween.tween_property(self, "position", original_pos + Vector2(2, 0), 0.04)
	tween.tween_property(self, "position", original_pos, 0.04)


func _show_fail_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Game Over"
	dialog.dialog_text = "You've used all 3 strikes!"
	dialog.ok_button_text = "Play Again"
	dialog.add_button("Continue", true, "continue")
	dialog.add_button("Back to Menu", true, "menu")
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		_restart_same_game()
	)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "continue":
			_can_continue_after_failure = true
			_update_button_states()
			_save_current_state()
			dialog.queue_free()
		elif action == "menu":
			dialog.queue_free()
			SceneTransition.transition_to("res://scenes/main_menu.tscn")
	)


func _show_win_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Congratulations!"
	var time_text := _format_time(elapsed_time)
	dialog.dialog_text = "You solved the %s puzzle in %s!" % [DIFFICULTY_NAMES[difficulty], time_text]
	if hints_used > 0:
		dialog.dialog_text += "\nHints used: %d" % hints_used
	dialog.ok_button_text = "Play Again"
	dialog.add_button("Back to Menu", true, "menu")
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		_restart_same_game()
	)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "menu":
			dialog.queue_free()
			SceneTransition.transition_to("res://scenes/main_menu.tscn")
	)


func _restart_same_game() -> void:
	var diff := difficulty
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load("res://scenes/game.tscn").instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.start_new_game(diff)
		queue_free()
	)


func _setup_number_buttons() -> void:
	for child in number_container.get_children():
		child.queue_free()
	_number_buttons.clear()

	for i in range(1, 10):
		var btn := Button.new()
		btn.text = str(i)
		btn.custom_minimum_size = Vector2(36, 50)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var num := i
		btn.pressed.connect(func() -> void: _on_number_pressed(num))
		number_container.add_child(btn)
		_number_buttons.append(btn)


func _setup_color_buttons() -> void:
	for child in color_container.get_children():
		child.queue_free()
	_color_buttons.clear()
	color_container.modulate = Color(1, 1, 1, 0)
	color_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var palette := NEON_CELL_COLORS if ThemeManager.is_neon else CELL_COLORS
	for i in range(palette.size()):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(36, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == 0:
			btn.text = "X"  # Clear color
		else:
			# Use a StyleBoxFlat so the button shows the exact color
			var style := StyleBoxFlat.new()
			style.bg_color = palette[i]
			style.set_corner_radius_all(6)
			style.set_content_margin_all(4)
			btn.add_theme_stylebox_override("normal", style)
			var hover := style.duplicate()
			hover.bg_color = palette[i].lightened(0.15)
			btn.add_theme_stylebox_override("hover", hover)
			var pressed := style.duplicate()
			pressed.bg_color = palette[i].darkened(0.1)
			btn.add_theme_stylebox_override("pressed", pressed)
		var color := palette[i]
		btn.pressed.connect(func() -> void: _on_color_pressed(color))
		color_container.add_child(btn)
		_color_buttons.append(btn)


func _on_color_pressed(color: Color) -> void:
	if _is_board_locked():
		return
	var now := Time.get_ticks_msec() / 1000.0

	# Double-click detection: apply number to all cells with this color
	if color == _last_color_pressed and color != Color.TRANSPARENT and (now - _last_color_press_time) < DOUBLE_CLICK_TIME:
		_fill_colored_cells(color)
		_last_color_pressed = Color.TRANSPARENT
		return

	_last_color_press_time = now
	_last_color_pressed = color

	# Single click: apply color to selected cell
	var index := board.selected_index
	if index < 0:
		# No cell selected: toggle color filter highlighting
		if color != Color.TRANSPARENT:
			board.filter_color = color if board.filter_color != color else Color.TRANSPARENT
			board.filter_number = 0
			board._update_highlighting()
		return
	var cell := board.cells[index]
	_push_undo(index)
	cell.set_cell_color(color)
	redo_stack.clear()
	board._update_highlighting()
	_save_current_state()


func _fill_colored_cells(color: Color) -> void:
	# Select all cells with this color visually
	_multi_selected_color = color
	var count := 0
	for cell in board.cells:
		var match := cell.cell_color == color and cell.cell_color != Color.TRANSPARENT and not cell.is_given
		cell.set_multi_selected(match)
		if match:
			count += 1
	if count == 0:
		_multi_selected_color = Color.TRANSPARENT


func _apply_number_to_multi_selection(number: int) -> void:
	# Apply number (or pencil mark) to all multi-selected cells
	var wrong_cells: Array[SudokuCell] = []
	for cell in board.cells:
		if not cell.is_multi_selected:
			continue
		if cell.is_given:
			continue
		if notes_mode:
			_push_undo(cell.index)
			cell.toggle_pencil_mark(number)
		else:
			if cell.value == number:
				continue  # Already placed
			if SettingsManager.error_mode == "strict" and solution[cell.index] != number:
				strikes += 1
				cell.set_value(number)
				cell.set_error(true)
				wrong_cells.append(cell)
			else:
				_push_undo(cell.index)
				cell.set_value(number)
				cell.set_error(false)
				cell.set_cell_color(Color.TRANSPARENT)
				current_grid[cell.index] = number
				if SettingsManager.auto_remove_pencil_marks:
					_remove_pencil_marks_for_number(cell.index, number)

	# Flash and revert wrong cells after a delay
	if wrong_cells.size() > 0:
		_play_error_feedback()
		_update_strikes_display()
		var tween := create_tween()
		tween.tween_interval(0.4)
		tween.tween_callback(func() -> void:
			for c: SudokuCell in wrong_cells:
				c.value = 0
				c.is_error = false
				c.queue_redraw()
		)
		if strikes >= 4 and not is_failed:
			is_failed = true
			_can_continue_after_failure = false
			_update_button_states()
			AnalyticsManager.log_event("game_over", {
				"game": "sudoku",
				"won": false,
				"difficulty": difficulty,
				"elapsed_time": elapsed_time,
				"strikes": strikes,
			})
			_show_fail_dialog()

	redo_stack.clear()
	_clear_multi_selection()
	_update_strikes_display()
	_update_number_completion()
	board._update_highlighting()
	if _check_win():
		_handle_win()
	_save_current_state()


func _clear_multi_selection() -> void:
	_multi_selected_color = Color.TRANSPARENT
	for cell in board.cells:
		cell.set_multi_selected(false)


func _setup_strike_indicators() -> void:
	for child in strikes_container.get_children():
		child.queue_free()
	_strike_indicators.clear()

	for i in 3:
		var indicator := ColorRect.new()
		indicator.custom_minimum_size = Vector2(12, 12)
		indicator.color = ThemeManager.get_color("strike_inactive")
		strikes_container.add_child(indicator)
		_strike_indicators.append(indicator)


func _save_current_state() -> void:
	if is_completed:
		return
	SaveManager.save_game({
		"puzzle": puzzle,
		"solution": solution,
		"current_grid": current_grid,
		"pencil_marks": board.get_pencil_marks_dict(),
		"cell_colors": board.get_cell_colors_dict(),
		"difficulty": difficulty,
		"elapsed_time": elapsed_time,
		"strikes": strikes,
		"error_mode": SettingsManager.error_mode,
		"is_failed": is_failed,
		"can_continue_after_failure": _can_continue_after_failure,
		"hints_used": hints_used,
	})


func _is_board_locked() -> bool:
	# Locked after completion, or after failure until Continue is chosen.
	return is_completed or (is_failed and not _can_continue_after_failure)


func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%d:%02d" % [mins, secs]


func _apply_theme() -> void:
	var bg := ThemeManager.get_color("background")
	# Set background via a stylebox or just clear color
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	add_theme_stylebox_override("panel", style)
	_update_strikes_display()
