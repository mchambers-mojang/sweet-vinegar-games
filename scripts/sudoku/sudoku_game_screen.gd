extends GameScreen

## Main game screen — orchestrates board UI, feeds input to SudokuLogic, dispatches side effects

# Pure game-rule logic — no UI, no autoloads
var logic: SudokuLogic = null

# UI-only state
var difficulty: int = 0
var _can_continue_after_failure: bool = false
var is_paused: bool = false
var notes_mode: bool = false

# Cheat auto-solve
var _cheat_active: bool = false
var _cheat_timer: float = 0.0
const CHEAT_INTERVAL := 0.5

# Node references
@onready var board: SudokuBoard = %Board
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
@onready var settings_button: Button = %SettingsButton

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
const LEGACY_SEED_HASH_INITIAL := 17
const LEGACY_SEED_HASH_MULTIPLIER := 31

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


# --- GameScreen overrides ---

func _get_game_id() -> String:
	return "sudoku"


func _get_scene_path() -> String:
	return Scenes.SUDOKU_GAME


func _get_save_adapter() -> GameSaveAdapter:
	return SudokuSaveAdapter.new()


func _is_initialized() -> bool:
	return logic != null and not logic.puzzle.is_empty()


func _is_completed() -> bool:
	return logic != null and logic.is_completed


func _serialize_state() -> Dictionary:
	var state := logic.serialize()
	state["elapsed_time"] = elapsed_time
	state["error_mode"] = GameRulesRegistry.get_rule("sudoku", "error_mode")
	state["can_continue_after_failure"] = _can_continue_after_failure
	state["random_seed"] = random_seed
	state["replay_id"] = replay_id
	return state


func _deserialize_state(data: Dictionary) -> void:
	resume_game(data)


func _get_crash_state() -> Dictionary:
	return {
		"game": "sudoku",
		"difficulty": logic.difficulty,
		"elapsed_time": elapsed_time,
		"strikes": logic.strikes,
		"is_failed": logic.is_failed,
		"is_completed": logic.is_completed,
		"is_paused": is_paused,
		"hints_used": logic.hints_used,
		"selected_index": board.selected_index,
	}


func _apply_game_theme() -> void:
	_apply_theme()


func _on_game_screen_ready() -> void:
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
	_update_button_states()


func start_new_game(diff: int) -> void:
	difficulty = diff
	_can_continue_after_failure = false
	is_paused = false
	notes_mode = false
	begin_session()


func resume_game(data: Dictionary) -> void:
	difficulty = data.get("difficulty", 0)
	_can_continue_after_failure = data.get("can_continue_after_failure", false)
	is_paused = false
	notes_mode = false
	begin_session(data)


# --- Session ceremony hooks ---

func _should_tick_timer() -> bool:
	return (logic == null or not logic.is_completed) and not is_paused


func _get_difficulty() -> int:
	return difficulty


func _get_start_crash_params() -> Dictionary:
	return {"difficulty": difficulty}


func _get_resume_crash_params(saved_data: Dictionary) -> Dictionary:
	return {"difficulty": saved_data.get("difficulty", 0)}


func _get_initial_state() -> Dictionary:
	return {
		"difficulty": logic.difficulty,
		"puzzle": logic.puzzle.duplicate(),
	}


func _get_settings_snapshot() -> Dictionary:
	return {
		"input_mode": GameRulesRegistry.get_rule("sudoku", "input_mode"),
		"error_mode": GameRulesRegistry.get_rule("sudoku", "error_mode"),
		"show_timer": PlatformSettings.show_timer,
	}


func _setup_game(saved_data: Dictionary) -> void:
	var strict_mode: bool = GameRulesRegistry.get_rule("sudoku", "error_mode") == "strict"
	var auto_remove: bool = GameRulesRegistry.get_rule("sudoku", "auto_remove_pencil_marks")
	logic = SudokuLogic.new(strict_mode, auto_remove)
	if saved_data.is_empty():
		logic.init_new_game(difficulty, random_seed)
		difficulty = logic.difficulty
		difficulty_label.text = DIFFICULTY_NAMES[logic.difficulty]
		board.load_puzzle(logic.puzzle)
	else:
		logic.init_from_save(saved_data)
		difficulty = logic.difficulty
		# Legacy fallback: old saves had no random_seed field.
		if random_seed == 0:
			random_seed = _derive_seed_from_puzzle(logic.puzzle)
		difficulty_label.text = DIFFICULTY_NAMES[logic.difficulty]
		_load_board_from_logic()
		if logic.is_failed and _is_board_locked():
			# Re-show the fail dialog for failed saves so players can choose Continue/Menu.
			call_deferred("_show_fail_dialog")
	_update_strikes_display()
	_update_button_states()
	_update_number_completion()


func _increment_stats() -> void:
	session.increment_stats_counter("sudoku", "games_started")
	session.increment_stats_counter("sudoku", "started_d%d" % difficulty)


func _get_analytics_params() -> Dictionary:
	return {"game": "sudoku", "difficulty": difficulty}


func _process(delta: float) -> void:
	super._process(delta)

	# Cheat auto-solve
	if _should_tick_timer() and _cheat_active:
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
		elif key.keycode >= KEY_1 and key.keycode <= KEY_9:
			var number := key.keycode - KEY_0
			_on_number_pressed(number)
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_BACKSPACE or key.keycode == KEY_DELETE:
			_on_erase_pressed()
			get_viewport().set_input_as_handled()


func _cheat_place_one() -> void:
	if _is_board_locked():
		_cheat_active = false
		return
	# Find all unsolved cells (empty or wrong) and pick one at random
	var unsolved_indices: Array[int] = []
	for i in 81:
		if logic.current_grid[i] != logic.solution[i]:
			unsolved_indices.append(i)
	if unsolved_indices.is_empty():
		_cheat_active = false
		return
	unsolved_indices.shuffle()
	var index := unsolved_indices[0]

	board.select_cell(index)

	var result := logic.apply_cheat_place(index)
	if not result.placed:
		return
	var cell := board.cells[index]
	cell.set_value(result.number)
	cell.set_error(false)
	cell.set_cell_color(Color.TRANSPARENT)
	for item in result.pencil_marks_removed:
		board.cells[item["index"]].set_pencil_mark(item["number"], false)
	_apply_unit_completion_effects(result.units_completed)
	_update_number_completion()
	board._update_highlighting()
	if result.game_won:
		_cheat_active = false
		_handle_win()
	_save_current_state()


func _on_cell_selected(index: int) -> void:
	if _is_board_locked():
		return
	session.record_input(elapsed_time, "cell_selected", {"index": index})

	var now := Time.get_ticks_msec() / 1000.0
	var cell := board.cells[index]

	# Double-click detection
	if index == _last_cell_pressed and (now - _last_cell_press_time) < DOUBLE_CLICK_TIME:
		if cell.cell_color != Color.TRANSPARENT:
			# Double-click on colored cell: multi-select all cells with same color
			_fill_colored_cells(cell.cell_color)
		else:
			# Double-click on non-colored cell: toggle row/col/box highlighting
			board.show_row_col_box = GameRulesRegistry.get_rule("sudoku", "highlight_row_col_box")
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

	if GameRulesRegistry.get_rule("sudoku", "input_mode") == "number_first":
		_handle_number_first_cell_tap(index)
	_update_number_completion()


func _handle_number_first_cell_tap(index: int) -> void:
	if _selected_number == 0:
		return
	var cell := board.cells[index]
	if cell.is_given:
		return
	# Place the pre-selected number into this cell
	GameEvents.move_made.emit("sudoku", {
		"elapsed_time": elapsed_time,
		"event_type": "number_input",
		"number": _selected_number,
		"cell_index": index,
		"notes_mode": notes_mode,
	})
	if notes_mode:
		var pr := logic.toggle_pencil_mark(index, _selected_number)
		if pr.valid:
			cell.pencil_marks = (logic.pencil_marks[index] as Array).duplicate()
			cell.queue_redraw()
			session.play_sound_pencil()
			session.vibrate_light()
	else:
		var result := logic.place_number(index, _selected_number)
		if not result.valid:
			return
		if result.strikes_added > 0:
			_update_strikes_display()
			_play_error_feedback()
			cell.set_value(_selected_number)
			cell.set_error(true)
			var revert_cell := cell

			# Neon glass shatter + shockwave on error
			if AppTheme.is_neon:
				var error_cell_rect := board.get_cell_rect(index)
				GlassShatter.create(board, error_cell_rect, Color(2.0, 0.0, 0.2), 10)
				var err_center := error_cell_rect.position + error_cell_rect.size / 2.0
				NeonRing.create(board, err_center, Color(2.0, 0.0, 0.2), error_cell_rect.size.x * 2.5, 0.2, 0.4)
				AppTheme.screen_shake(5.0, 0.15)

			var revert_tween := create_tween()
			revert_tween.tween_interval(0.4)
			revert_tween.tween_callback(func() -> void:
				revert_cell.value = 0
				revert_cell.is_error = false
				revert_cell.queue_redraw()
			)
			if result.game_failed:
				_can_continue_after_failure = false
				_update_button_states()
				session.set_stats_counter("general", "current_win_streak", 0)
				session.check_achievements()
				_log_game_over_analytics(false)
				_show_fail_dialog()
			_save_current_state()
			_update_number_completion()
			board._update_highlighting()
			return
		if result.placed:
			cell.set_value(result.number)
			cell.set_error(false)
			cell.set_cell_color(Color.TRANSPARENT)

			# Neon burst on correct placement
			if AppTheme.is_neon:
				var placed_cell_rect := board.get_cell_rect(index)
				var center := placed_cell_rect.position + placed_cell_rect.size / 2.0
				NeonBurst.create(board, center, Color(0.0, 2.0, 1.6), 10, 0.8)

			for item in result.pencil_marks_removed:
				board.cells[item["index"]].set_pencil_mark(item["number"], false)
			_apply_unit_completion_effects(result.units_completed)
			_update_number_completion()
			board._update_highlighting()
			if result.game_won:
				_handle_win()
	_save_current_state()


func _on_number_pressed(number: int) -> void:
	if _is_board_locked():
		return
	session.record_input(elapsed_time, "number_button", {
		"number": number,
		"notes_mode": notes_mode,
		"input_mode": GameRulesRegistry.get_rule("sudoku", "input_mode"),
	})

	# If multi-selection is active, apply to all selected cells
	if _multi_selected_color != Color.TRANSPARENT:
		_apply_number_to_multi_selection(number)
		return

	if GameRulesRegistry.get_rule("sudoku", "input_mode") == "cell_first":
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
	GameEvents.move_made.emit("sudoku", {
		"elapsed_time": elapsed_time,
		"event_type": "number_input",
		"number": number,
		"cell_index": index,
		"notes_mode": notes_mode,
	})
	if notes_mode:
		var pr := logic.toggle_pencil_mark(index, number)
		if pr.valid:
			cell.pencil_marks = (logic.pencil_marks[index] as Array).duplicate()
			cell.queue_redraw()
			session.play_sound_pencil()
			session.vibrate_light()
	else:
		var result := logic.place_number(index, number)
		if not result.valid:
			return
		if result.strikes_added > 0:
			_update_strikes_display()
			_play_error_feedback()
			# Briefly flash the wrong number then revert
			cell.set_value(number)
			cell.set_error(true)
			var revert_cell := cell

			# Neon glass shatter + shockwave on error
			if AppTheme.is_neon:
				var error_cell_rect := board.get_cell_rect(index)
				GlassShatter.create(board, error_cell_rect, Color(2.0, 0.0, 0.2), 10)
				var err_center := error_cell_rect.position + error_cell_rect.size / 2.0
				NeonRing.create(board, err_center, Color(2.0, 0.0, 0.2), error_cell_rect.size.x * 2.5, 0.2, 0.4)
				AppTheme.screen_shake(5.0, 0.15)

			var revert_tween := create_tween()
			revert_tween.tween_interval(0.4)
			revert_tween.tween_callback(func() -> void:
				revert_cell.value = 0
				revert_cell.is_error = false
				revert_cell.queue_redraw()
			)

			if result.game_failed:
				_can_continue_after_failure = false
				_update_button_states()
				session.set_stats_counter("general", "current_win_streak", 0)
				session.check_achievements()
				_log_game_over_analytics(false)
				_show_fail_dialog()
			_save_current_state()
			_update_number_completion()
			board._update_highlighting()
			return

		if result.placed:
			cell.set_value(result.number)
			cell.set_error(false)
			cell.set_cell_color(Color.TRANSPARENT)
			session.play_sound_place()
			session.vibrate_light()

			# Neon burst on correct placement
			if AppTheme.is_neon:
				var placed_cell_rect := board.get_cell_rect(index)
				var center := placed_cell_rect.position + placed_cell_rect.size / 2.0
				NeonBurst.create(board, center, Color(0.0, 2.0, 1.6), 10, 0.8)

			for item in result.pencil_marks_removed:
				board.cells[item["index"]].set_pencil_mark(item["number"], false)
			_apply_unit_completion_effects(result.units_completed)
			_update_number_completion()
			board._update_highlighting()

			if result.game_won:
				_handle_win()

	_save_current_state()


func _on_notes_pressed() -> void:
	notes_mode = not notes_mode
	notes_button.text = "Notes: ON" if notes_mode else "Notes"
	color_container.modulate = Color(1, 1, 1, 1) if notes_mode else Color(1, 1, 1, 0)
	color_container.mouse_filter = Control.MOUSE_FILTER_STOP if notes_mode else Control.MOUSE_FILTER_IGNORE
	_update_button_states()


func _on_hint_pressed() -> void:
	if _is_board_locked() or logic.hints_used >= 1:
		return
	session.user_action("sudoku_hint_used", {"selected_index": board.selected_index})

	var index: int = -1

	# Use selected cell if it's unsolved
	if board.selected_index >= 0:
		var sel := board.selected_index
		if not board.cells[sel].is_given and logic.current_grid[sel] != logic.solution[sel]:
			index = sel

	# Otherwise pick a random unsolved cell
	if index < 0:
		var empty_cells: Array[int] = []
		for i in 81:
			if logic.current_grid[i] == 0 or logic.current_grid[i] != logic.solution[i]:
				empty_cells.append(i)
		if empty_cells.is_empty():
			return
		empty_cells.shuffle()
		index = empty_cells[0]

	board.selected_index = index
	session.record_input(elapsed_time, "hint_pressed", {"index": index, "value": logic.solution[index]})

	var result := logic.use_hint(index)
	var cell := board.cells[index]
	cell.set_value(result.number)
	cell.set_error(false)
	hint_button.disabled = true

	for item in result.pencil_marks_removed:
		board.cells[item["index"]].set_pencil_mark(item["number"], false)
	_apply_unit_completion_effects(result.units_completed)
	_update_number_completion()
	board._update_highlighting()

	if result.game_won:
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
	session.record_input(elapsed_time, "erase_pressed", {"index": index})

	var result := logic.erase_cell(index)
	if not result.success:
		return
	cell.value = 0
	cell.is_error = false
	cell.pencil_marks = []
	cell.queue_redraw()
	session.play_sound_erase()
	session.vibrate_light()
	_update_number_completion()
	board._update_highlighting()
	_save_current_state()


func _on_pause_pressed() -> void:
	is_paused = not is_paused
	pause_button.text = "Resume" if is_paused else "Pause"
	# Hide board when paused
	board.visible = not is_paused
	session.user_action("sudoku_pause_toggled", {"is_paused": is_paused})


func _on_back_pressed() -> void:
	var completed: Dictionary = session.finish_replay("abandoned", logic.count_filled_cells(), elapsed_time, {
		"difficulty": difficulty,
		"strikes": logic.strikes,
	})
	session.save_completed_replay(completed)
	session.user_action("sudoku_back_to_menu")
	if not logic.is_completed:
		session.set_stats_counter("general", "current_win_streak", 0)
		session.check_achievements()
	_save_current_state()
	SceneTransition.transition_to(Scenes.SUDOKU_MENU)


func _on_undo_pressed() -> void:
	if _is_board_locked():
		return
	if logic.undo_stack.is_empty():
		return
	session.user_action("sudoku_undo")
	var result := logic.undo()
	if result.success:
		_sync_cell_display(result.cell_index)
	_update_button_states()
	_update_number_completion()
	board._update_highlighting()
	_save_current_state()


func _on_redo_pressed() -> void:
	if _is_board_locked():
		return
	if logic.redo_stack.is_empty():
		return
	session.user_action("sudoku_redo")
	var result := logic.redo()
	if result.success:
		_sync_cell_display(result.cell_index)
	_update_button_states()
	_update_number_completion()
	board._update_highlighting()
	_save_current_state()




func _handle_win() -> void:
	var won := not logic.is_failed
	var completed: Dictionary = session.finish_replay("win" if won else "completed_after_failure", logic.count_filled_cells(), elapsed_time, {
		"difficulty": difficulty,
		"strikes": logic.strikes,
		"hints_used": logic.hints_used,
	})
	session.save_completed_replay(completed)
	var previous_best: float = _get_best_time(difficulty)
	_record_sudoku_completion(difficulty, elapsed_time, GameRulesRegistry.get_rule("sudoku", "error_mode") == "strict", won)
	if won:
		session.increment_stats_counter("general", "games_won")
		session.increment_stats_counter("sudoku", "games_won")
		session.increment_stats_counter("general", "current_win_streak")
		if logic.strikes == 0:
			session.increment_stats_counter("sudoku", "perfect_wins")
		if elapsed_time < 300.0:
			session.increment_stats_counter("sudoku", "wins_under_300s")
		if elapsed_time < 180.0:
			session.increment_stats_counter("sudoku", "wins_under_180s")
	else:
		session.set_stats_counter("general", "current_win_streak", 0)
	session.check_achievements()
	_log_game_over_analytics(won)
	clear_save()
	_play_win_celebration()
	if previous_best < 0.0 or elapsed_time < previous_best:
		_show_new_best_indicator()


func _play_win_celebration() -> void:
	session.play_sound_win()
	session.vibrate_success()
	# Neon win shockwave from board center
	if AppTheme.is_neon:
		var center_rect := board.get_cell_rect(40)  # Center cell (row 4, col 4)
		var center := center_rect.position + center_rect.size / 2.0
		NeonRing.create(board, center, Color(0.0, 2.0, 1.5), center_rect.size.x * 8.0, 0.5, 1.2)
		AppTheme.screen_shake(6.0, 0.2)
	# Cascade reveal: flash each cell in sequence from top-left to bottom-right
	var tween := create_tween()
	for i in 81:
		var cell := board.cells[i]
		tween.tween_callback(func() -> void:
			cell.flash(Color(1.0, 0.85, 0.4), 0.25)
		).set_delay(0.018)
	# Show win dialog after cascade completes
	tween.tween_callback(_show_win_dialog).set_delay(0.5)


func _show_new_best_indicator() -> void:
	var center_index := int(board.cells.size() / 2)
	var center_rect := board.get_cell_rect(center_index)
	var center := center_rect.position + center_rect.size / 2.0
	var color := Color(0.0, 2.0, 1.5) if AppTheme.is_neon else Color(0.2, 0.75, 1.0)
	ComboLabel.create(board, center, "NEW BEST!", color)
	session.vibrate_medium()


func _sync_cell_display(cell_index: int) -> void:
	var cell := board.cells[cell_index]
	cell.value = logic.current_grid[cell_index]
	cell.is_error = false
	cell.pencil_marks = (logic.pencil_marks[cell_index] as Array).duplicate()
	cell.cell_color = logic.colors[cell_index]
	cell.queue_redraw()


func _load_board_from_logic() -> void:
	for i in 81:
		var cell := board.cells[i]
		cell.is_given = logic.puzzle[i] != 0
		cell.value = logic.current_grid[i]
		cell.pencil_marks = (logic.pencil_marks[i] as Array).duplicate()
		cell.cell_color = logic.colors[i]
		cell.is_error = false
		cell.queue_redraw()
	board.selected_index = -1
	board._update_highlighting()


func _apply_unit_completion_effects(units: Array) -> void:
	if units.is_empty():
		return
	var flash_indices: Dictionary = {}
	for unit: Dictionary in units:
		for idx: int in unit["cells"]:
			flash_indices[idx] = true

	session.play_sound_unit_complete()
	for idx: int in flash_indices.keys():
		board.cells[idx].flash(Color(1.0, 0.85, 0.4), 0.35)

	if not AppTheme.is_neon:
		return

	var avg_x := 0.0
	var avg_y := 0.0
	for idx: int in flash_indices.keys():
		var cell_rect := board.get_cell_rect(idx)
		avg_x += cell_rect.position.x + cell_rect.size.x / 2.0
		avg_y += cell_rect.position.y + cell_rect.size.y / 2.0
	var center := Vector2(avg_x / flash_indices.size(), avg_y / flash_indices.size())
	NeonRing.create(board, center, Color(0.0, 2.0, 1.5), board.get_cell_rect(0).size.x * 4.0, 0.35, 0.6)

	for unit: Dictionary in units:
		var unit_type: String = unit["type"]
		var unit_index: int = unit["unit_index"]
		if unit_type == "row":
			var row_first := board.get_cell_rect(unit_index * 9)
			var row_last := board.get_cell_rect(unit_index * 9 + 8)
			var row_sweep_rect := Rect2(row_first.position, Vector2(row_last.position.x + row_last.size.x - row_first.position.x, row_first.size.y))
			NeonSweep.create(board, row_sweep_rect, true, Color(0.0, 2.0, 1.5))
		elif unit_type == "col":
			var col_first := board.get_cell_rect(unit_index)
			var col_last := board.get_cell_rect(72 + unit_index)
			var col_sweep_rect := Rect2(col_first.position, Vector2(col_first.size.x, col_last.position.y + col_last.size.y - col_first.position.y))
			NeonSweep.create(board, col_sweep_rect, false, Color(2.0, 0.3, 1.8))
		elif unit_type == "box":
			var box_row := (unit_index / 3) * 3
			var box_col := (unit_index % 3) * 3
			var box_first := board.get_cell_rect(box_row * 9 + box_col)
			var box_last := board.get_cell_rect((box_row + 2) * 9 + box_col + 2)
			var box_sweep_rect := Rect2(box_first.position, Vector2(box_last.position.x + box_last.size.x - box_first.position.x, box_last.position.y + box_last.size.y - box_first.position.y))
			NeonSweep.create(board, box_sweep_rect, true, Color(1.5, 0.2, 1.0))


func _update_number_completion() -> void:
	if logic == null:
		return
	var counts: Array[int] = []
	counts.resize(10)
	counts.fill(0)
	for i in 81:
		if logic.current_grid[i] > 0:
			counts[logic.current_grid[i]] += 1

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
	if GameRulesRegistry.get_rule("sudoku", "error_mode") != "strict":
		strikes_container.visible = false
		return
	strikes_container.visible = true
	for i in range(_strike_indicators.size()):
		var indicator := _strike_indicators[i]
		if logic != null and i < logic.strikes:
			indicator.modulate = AppTheme.get_color("strike_active")
		else:
			indicator.modulate = AppTheme.get_color("strike_inactive")


func _update_button_states() -> void:
	if logic == null:
		return
	var board_locked := _is_board_locked()
	undo_button.disabled = board_locked or logic.undo_stack.is_empty()
	redo_button.disabled = board_locked or logic.redo_stack.is_empty()
	erase_button.visible = GameRulesRegistry.get_rule("sudoku", "error_mode") != "strict"
	hint_button.disabled = board_locked or logic.hints_used >= 1


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
			btn.add_theme_color_override("font_color", AppTheme.get_color("cell_selected"))
		else:
			btn.remove_theme_color_override("font_color")


func _play_error_feedback() -> void:
	session.play_sound_error()
	session.vibrate_error()
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
	dialog.add_button("Menu", true, "menu")
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		var completed: Dictionary = session.finish_replay("failed", logic.count_filled_cells(), elapsed_time, {
			"difficulty": difficulty,
			"strikes": logic.strikes,
		})
		session.save_completed_replay(completed)
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
			var completed: Dictionary = session.finish_replay("failed", logic.count_filled_cells(), elapsed_time, {
				"difficulty": difficulty,
				"strikes": logic.strikes,
			})
			session.save_completed_replay(completed)
			dialog.queue_free()
			SceneTransition.transition_to(Scenes.SUDOKU_MENU)
	)


func _show_win_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Congratulations!"
	var time_text := _format_time(elapsed_time)
	dialog.dialog_text = "You solved the %s puzzle in %s!" % [DIFFICULTY_NAMES[difficulty], time_text]
	if logic.hints_used > 0:
		dialog.dialog_text += "\nHints used: %d" % logic.hints_used
	dialog.ok_button_text = "Play Again"
	dialog.add_button("Menu", true, "menu")
	dialog.add_button("Save Replay", true, "bookmark")
	dialog.max_size = Vector2i(int(get_viewport_rect().size.x * 0.9), 600)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		_restart_same_game()
	)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "menu":
			dialog.queue_free()
			SceneTransition.transition_to(Scenes.SUDOKU_MENU)
		elif action == "bookmark":
			var success: bool = session.bookmark_replay()
			if success:
				dialog.dialog_text += "\n\n✓ Replay bookmarked!"
			else:
				dialog.dialog_text += "\n\n✗ No replay to bookmark"
	)


func _restart_same_game() -> void:
	var diff := difficulty
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load(Scenes.SUDOKU_GAME).instantiate()
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

	var palette := NEON_CELL_COLORS if AppTheme.is_neon else CELL_COLORS
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
	session.record_input(elapsed_time, "color_pressed", {
		"color": color.to_html(),
		"selected_index": board.selected_index,
	})
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
	logic.set_cell_color(index, color)
	cell.set_cell_color(color)
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
	var had_error := false
	var any_won := false
	for cell in board.cells:
		if not cell.is_multi_selected:
			continue
		if cell.is_given:
			continue
		var idx: int = cell.index
		if notes_mode:
			var pr := logic.toggle_pencil_mark(idx, number)
			if pr.valid:
				cell.pencil_marks = (logic.pencil_marks[idx] as Array).duplicate()
				cell.queue_redraw()
		else:
			var result := logic.place_number(idx, number)
			if not result.valid:
				continue
			if result.strikes_added > 0:
				had_error = true
				cell.set_value(number)
				cell.set_error(true)
				var revert_cell := cell
				var revert_tween := create_tween()
				revert_tween.tween_interval(0.4)
				revert_tween.tween_callback(func() -> void:
					revert_cell.value = 0
					revert_cell.is_error = false
					revert_cell.queue_redraw()
				)
				if result.game_failed:
					_can_continue_after_failure = false
					session.set_stats_counter("general", "current_win_streak", 0)
					session.check_achievements()
					_update_button_states()
					_log_game_over_analytics(false)
					_show_fail_dialog()
			elif result.placed:
				cell.set_value(result.number)
				cell.set_error(false)
				cell.set_cell_color(Color.TRANSPARENT)
				for item in result.pencil_marks_removed:
					board.cells[item["index"]].set_pencil_mark(item["number"], false)
				_apply_unit_completion_effects(result.units_completed)
				if result.game_won:
					any_won = true

	if had_error:
		_play_error_feedback()
		_update_strikes_display()

	_clear_multi_selection()
	_update_number_completion()
	board._update_highlighting()
	if any_won:
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
		indicator.color = AppTheme.get_color("strike_inactive")
		strikes_container.add_child(indicator)
		_strike_indicators.append(indicator)


func _is_board_locked() -> bool:
	if logic == null:
		return false
	return logic.is_completed or (logic.is_failed and not _can_continue_after_failure)


func _log_game_over_analytics(won: bool) -> void:
	GameEvents.game_ended.emit("sudoku", "win" if won else "game_over", elapsed_time)
	session.log_event("game_over", {
		"game": "sudoku",
		"won": won,
		"difficulty": difficulty,
		"elapsed_time": elapsed_time,
		"strikes": logic.strikes,
		"hints_used": logic.hints_used,
	})


func _apply_theme() -> void:
	var bg := AppTheme.get_color("background")
	# Set background via a stylebox or just clear color
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	add_theme_stylebox_override("panel", style)
	_update_strikes_display()


func _count_filled_cells() -> int:
	return logic.count_filled_cells() if logic != null else 0


func _derive_seed_from_puzzle(values: Array[int]) -> int:
	# Legacy fallback for saves created before explicit replay seeds existed.
	# 17/31 are standard hash multipliers chosen for stable deterministic mixing.
	var seed := LEGACY_SEED_HASH_INITIAL
	for value in values:
		seed = int((seed * LEGACY_SEED_HASH_MULTIPLIER + int(value)) & 0x7fffffff)
	return seed


func _record_sudoku_completion(diff: int, time: float, was_strict: bool, won: bool) -> void:
	session.record_stats("sudoku", {
		"type": "completion",
		"difficulty": diff,
		"time": time,
		"was_strict": was_strict,
		"won": won,
	})
	session.increment_stats_counter("sudoku", "completed_d%d" % diff)
	# Track best time
	var best: float = float(session.get_stats_counter("sudoku", "best_d%d" % diff))
	if best == 0 or time < best:
		session.set_stats_counter("sudoku", "best_d%d" % diff, int(time * 1000))
	# Streak tracking
	if was_strict:
		if won:
			var streak: int = session.get_stats_counter("sudoku", "current_streak") + 1
			session.set_stats_counter("sudoku", "current_streak", streak)
			var best_streak: int = session.get_stats_counter("sudoku", "best_streak")
			if streak > best_streak:
				session.set_stats_counter("sudoku", "best_streak", streak)
			session.increment_stats_counter("sudoku", "won_d%d" % diff)
		else:
			session.set_stats_counter("sudoku", "current_streak", 0)
			session.increment_stats_counter("sudoku", "lost_d%d" % diff)


func _get_best_time(diff: int) -> float:
	var best_ms: int = session.get_stats_counter("sudoku", "best_d%d" % diff)
	if best_ms == 0:
		return -1.0
	return float(best_ms) / 1000.0


