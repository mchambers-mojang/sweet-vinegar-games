extends GameScreen

## Blockudoku game screen — board, score, block tray, drag-to-place


const BLOCKS_PER_SET := 3
const ROTATE_TAP_DISTANCE_THRESHOLD := 12.0
const COMBO_PULSE_BASE_SCALE := 1.02
const COMBO_PULSE_SCALE_PER_COMBO := 0.002
const COMBO_PULSE_MAX_SCALE := 1.04
const COMBO_PULSE_HALF_DURATION := 0.15

# Pure game logic — all rule decisions delegated here
var logic: BlockudokuLogic

var _new_best_shown: bool = false

# Drag state
var _dragging: bool = false
var _drag_block_index: int = -1
var _drag_shape: Array = []
var _drag_screen_pos: Vector2 = Vector2.ZERO
var _drag_start_screen_pos: Vector2 = Vector2.ZERO
var _drag_moved: bool = false
var _drag_last_grid_pos := Vector2i(-999, -999)
var _board_pulse_tween: Tween = null

# Node references
@onready var board: BlockudokuBoard = %BlockudokuBoard
@onready var score_label: Label = %ScoreLabel
@onready var back_button: Button = %BackButton
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var block_tray: HBoxContainer = %BlockTray
@onready var settings_button: Button = %SettingsButton

var _rng := RandomNumberGenerator.new()

# Block tray piece display nodes
var _tray_panels: Array[Control] = []


# --- GameScreen overrides ---

func _get_game_id() -> String:
	return "blockudoku"


func _get_scene_path() -> String:
	return Scenes.BLOCKUDOKU_GAME


func _get_save_adapter() -> GameSaveAdapter:
	return BlockudokuSaveAdapter.new()


func _is_initialized() -> bool:
	return logic != null and not logic.available_blocks.is_empty()


func _is_completed() -> bool:
	return logic != null and logic.is_game_over


func _serialize_state() -> Dictionary:
	return {
		"score": logic.score,
		"turns": logic.turns,
		"combo_count": logic.combo_count,
		"new_best_shown": _new_best_shown,
		"elapsed_time": elapsed_time,
		"board_state": board.get_state(),
		"available_blocks": _serialize_blocks(logic.available_blocks),
		"blocks_placed_this_set": logic.blocks_placed_this_set,
		"random_seed": random_seed,
		"rng_state": _rng.state,
		"replay_id": replay_id,
	}


func _deserialize_state(data: Dictionary) -> void:
	resume_game(data)


func _get_crash_state() -> Dictionary:
	return {
		"game": "blockudoku",
		"score": logic.score,
		"turns": logic.turns,
		"combo_count": logic.combo_count,
		"elapsed_time": elapsed_time,
		"is_game_over": logic.is_game_over,
		"blocks_placed_this_set": logic.blocks_placed_this_set,
		"available_block_count": logic.available_blocks.size(),
	}


func _apply_game_theme() -> void:
	_apply_theme()


func _on_game_screen_ready() -> void:
	back_button.pressed.connect(_on_back)
	undo_button.pressed.connect(_on_undo_pressed)
	redo_button.pressed.connect(_on_redo_pressed)


func start_new_game() -> void:
	_new_best_shown = false
	begin_session()


func launch(_params: LaunchParams) -> void:
	start_new_game()


func resume_game(data: Dictionary) -> void:
	_new_best_shown = data.get("new_best_shown", false)
	begin_session(data)


# --- Session ceremony hooks ---

func _should_tick_timer() -> bool:
	return logic != null and not logic.is_game_over


func _get_resume_crash_params(saved_data: Dictionary) -> Dictionary:
	return {"score": saved_data.get("score", 0)}


func _get_initial_state() -> Dictionary:
	return {
		"board_state": board.get_state(),
		"available_blocks": _serialize_blocks(logic.available_blocks),
	}


func _get_settings_snapshot() -> Dictionary:
	return {
		"drag_offset": GameRulesRegistry.get_rule("blockudoku", "drag_offset"),
		"show_timer": PlatformSettings.show_timer,
	}


func _setup_game(saved_data: Dictionary) -> void:
	var rotation_mode: bool = GameRulesRegistry.get_rule("blockudoku", "rotation_mode")
	logic = BlockudokuLogic.new(rotation_mode)
	logic.clear_undo_history()
	if saved_data.is_empty():
		_rng.seed = random_seed
		board.reset()
		_deal_new_blocks()
		_update_score_display()
		_update_undo_redo_buttons()
	else:
		# Restore seed first, then override the full internal state if available.
		_rng.seed = random_seed
		if saved_data.has("rng_state"):
			_rng.state = int(saved_data.get("rng_state", 0))
		var board_state: Dictionary = saved_data.get("board_state", {})
		board.set_state(board_state)
		# Build logic state from saved data — board_grid comes from board_state
		var logic_state := {
			"board_grid": board_state.get("grid", []),
			"score": saved_data.get("score", 0),
			"turns": saved_data.get("turns", 0),
			"combo_count": saved_data.get("combo_count", 0),
			"is_game_over": false,
			"available_blocks": saved_data.get("available_blocks", []),
			"blocks_placed_this_set": saved_data.get("blocks_placed_this_set", 0),
		}
		logic.set_state(logic_state)
		_build_tray()
		_update_score_display()
		_update_undo_redo_buttons()


func _increment_stats() -> void:
	_stats.increment_counter("blockudoku", "games_played")


func _get_analytics_params() -> Dictionary:
	return {"game": "blockudoku"}


func _deal_new_blocks() -> void:
	var new_shapes: Array[Array] = BlockudokuShapes.pick_random(BLOCKS_PER_SET, _rng)
	for i in new_shapes.size():
		new_shapes[i] = BlockudokuShapes.normalize(new_shapes[i])
	logic.deal_blocks(new_shapes)
	_build_tray()


func _build_tray() -> void:
	# Clear existing
	for child in block_tray.get_children():
		child.queue_free()
	_tray_panels.clear()

	var cell_px := 20.0
	var tray_height := block_tray.custom_minimum_size.y

	for i in logic.available_blocks.size():
		var panel := _create_block_panel(i, tray_height)
		block_tray.add_child(panel)
		_tray_panels.append(panel)


func _create_block_panel(index: int, fixed_height: float) -> Control:
	var cell_px := 20.0  # small preview cell size
	var panel := Control.new()
	# Fixed 5x5 grid slot so rotation/different shapes don't shift the tray
	panel.custom_minimum_size = Vector2(5 * cell_px + 16, fixed_height)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Draw function
	panel.draw.connect(func() -> void:
		if logic == null or index >= logic.available_blocks.size():
			return
		var s: Array = logic.available_blocks[index]
		var b := BlockudokuShapes.get_bounds(s)
		var cpx := minf((panel.size.x - 8) / b.x, (panel.size.y - 8) / b.y)
		cpx = minf(cpx, 24.0)
		var offset := (panel.size - Vector2(b.x * cpx, b.y * cpx)) / 2.0
		var color := BlockudokuShapes.get_shape_color(s)
		for cell in s:
			var c: Vector2i = cell
			var rect := Rect2(offset + Vector2(c.x * cpx, c.y * cpx) + Vector2(0.5, 0.5), Vector2(cpx - 1, cpx - 1))
			panel.draw_rect(rect, color)
	)

	# Input handling for drag
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if logic == null or logic.is_game_over or board.is_clear_animating:
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_start_drag(index, mb.global_position)
				elif _dragging and _drag_block_index == index:
					_end_drag(mb.global_position)
		elif event is InputEventMouseMotion and _dragging and _drag_block_index == index:
			_update_drag(event.global_position)
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_start_drag(index, st.position)
			elif _dragging and _drag_block_index == index:
				_end_drag(st.position)
		elif event is InputEventScreenDrag and _dragging and _drag_block_index == index:
			_update_drag(event.position)
	)

	return panel


func _start_drag(index: int, screen_pos: Vector2) -> void:
	if board.is_clear_animating:
		return
	_dragging = true
	_drag_block_index = index
	_drag_shape = logic.available_blocks[index].duplicate(true)
	_drag_screen_pos = screen_pos
	_drag_start_screen_pos = screen_pos
	_drag_moved = false
	_drag_last_grid_pos = Vector2i(-999, -999)
	_recorder.record_input(elapsed_time, "piece_selected", {
		"tray_index": index,
	})
	DragEffect.suppress()

	# Visual + haptic feedback on grab
	_haptic.vibrate_light()
	if index < _tray_panels.size():
		var panel := _tray_panels[index]
		panel.pivot_offset = panel.size / 2.0
		var tw := create_tween()
		tw.tween_property(panel, "scale", Vector2(1.15, 1.15), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(panel, "modulate", Color(1.3, 1.3, 1.3, 1.0), 0.1)

	_update_board_preview(screen_pos)


func _update_drag(screen_pos: Vector2) -> void:
	if not _drag_moved and screen_pos.distance_to(_drag_start_screen_pos) >= ROTATE_TAP_DISTANCE_THRESHOLD:
		_drag_moved = true
	_drag_screen_pos = screen_pos
	_update_board_preview(screen_pos)


func _update_board_preview(screen_pos: Vector2) -> void:
	var local_pos := board.get_local_mouse_position()
	# Offset upward so finger doesn't cover the placement
	var cell_size := board._get_cell_size()
	var offset_multiplier: int = GameRulesRegistry.get_rule("blockudoku", "drag_offset")  # 0=None, 1=Small, 2=Medium, 3=Large
	if offset_multiplier > 0:
		local_pos.y -= cell_size * offset_multiplier
	var grid_pos := board.screen_to_grid(local_pos)
	if grid_pos != _drag_last_grid_pos:
		# Only haptic if we've moved before (skip initial grab) and piece is on the board
		if _drag_last_grid_pos != Vector2i(-999, -999) and grid_pos.x >= 0 and grid_pos.x < 9 and grid_pos.y >= 0 and grid_pos.y < 9:
			_haptic.vibrate_light()
		_drag_last_grid_pos = grid_pos
	board.show_preview(_drag_shape, grid_pos.x, grid_pos.y)


func _end_drag(screen_pos: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	_haptic.stop()
	DragEffect.unsuppress()

	# Reset tray panel visual
	if _drag_block_index >= 0 and _drag_block_index < _tray_panels.size():
		var panel := _tray_panels[_drag_block_index]
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)

	var local_pos := board.get_local_mouse_position()
	var cell_size := board._get_cell_size()
	var origin := board._get_grid_origin()
	var offset_multiplier: int = GameRulesRegistry.get_rule("blockudoku", "drag_offset")
	if offset_multiplier > 0:
		local_pos.y -= cell_size * offset_multiplier
	var grid_pos := board.screen_to_grid(local_pos)

	board.clear_preview()

	# Tap = rotate (when rotation mode enabled)
	if logic.rotation_mode and not _drag_moved and _drag_block_index >= 0 and _drag_block_index < logic.available_blocks.size():
		var shape: Array = logic.available_blocks[_drag_block_index]
		if shape.size() > 0:
			logic.apply_rotation(_drag_block_index)
			var rotated_shape: Array = logic.available_blocks[_drag_block_index]
			_recorder.record_input(elapsed_time, "piece_rotated", {
				"tray_index": _drag_block_index,
				"shape": _serialize_shape(rotated_shape),
			})
			if _drag_block_index < _tray_panels.size():
				_tray_panels[_drag_block_index].queue_redraw()
			_save_current_state()
		_drag_block_index = -1
		_drag_shape = []
		return

	# Attempt placement via the logic module (validates + mutates logic board_grid).
	# Pass the current board visual so the undo entry captures the "before" colour state.
	var old_score := logic.score
	var place_result := logic.try_place(_drag_block_index, grid_pos, board.get_state())

	if place_result.valid:
		GameEvents.move_made.emit("blockudoku", {
			"elapsed_time": elapsed_time,
			"event_type": "piece_placed",
			"tray_index": _drag_block_index,
			"grid_x": grid_pos.x,
			"grid_y": grid_pos.y,
			"shape": _serialize_shape(_drag_shape),
		})
		var block_color := BlockudokuShapes.get_shape_color(_drag_shape)
		board.place_block(_drag_shape, grid_pos.x, grid_pos.y, block_color)
		_sound.play_place()
		_haptic.vibrate_light()

		# Neon placement effects
		if AppTheme.is_neon:

			# Per-cell burst — small burst on each cell of the shape
			for cell_offset in _drag_shape:
				var co: Vector2i = cell_offset
				var cell_center := origin + Vector2(
					(grid_pos.x + co.x + 0.5) * cell_size,
					(grid_pos.y + co.y + 0.5) * cell_size
				)
				EffectFactory.neon_burst(board, cell_center, block_color, 6, 0.5)

			# Expanding ring from shape center
			var bounds := BlockudokuShapes.get_bounds(_drag_shape)
			var shape_center := origin + Vector2(
				(grid_pos.x + bounds.x / 2.0) * cell_size,
				(grid_pos.y + bounds.y / 2.0) * cell_size
			)
			EffectFactory.neon_ring(board, shape_center, block_color, cell_size * 2.0, 0.25, 0.3)

			# Cell flash — briefly brighten placed cells
			board.flash_placed_cells(_drag_shape, grid_pos.x, grid_pos.y, block_color)

			# Light screen shake
			AppTheme.screen_shake(3.0, 0.1)

		# Hide the tray panel
		if _drag_block_index < _tray_panels.size():
			_tray_panels[_drag_block_index].visible = false

		_analytics.log_event("piece_placed", {
			"game": "blockudoku",
			"turn": logic.turns,
			"cells": place_result.cells_placed,
			"x": grid_pos.x,
			"y": grid_pos.y,
		})
		if logic.score != old_score:
			GameEvents.score_changed.emit("blockudoku", old_score, logic.score)

		# Visual clear animation (board.check_and_clear handles its own neon fx)
		board.check_and_clear()

		if place_result.total_cells_cleared > 0:
			if place_result.combo > 1:
				if place_result.lines_cleared + place_result.boxes_cleared >= 2:
					_pulse_board_for_combo(place_result.combo)
				# Scale shockwave with combo
				if AppTheme.is_neon:
					var combo_center := origin + Vector2(cell_size * 4.5, cell_size * 4.5)
					var combo_amp := minf(0.5 + place_result.combo * 0.3, 2.0)
					EffectFactory.neon_ring(board, combo_center, Color(2.0, 0.3, 1.8), cell_size * (4.0 + place_result.combo), 0.4, combo_amp)
			_stats.increment_counter("blockudoku", "total_clears", place_result.lines_cleared + place_result.boxes_cleared)
			_achievements.track("blockudoku.clear_count", place_result.lines_cleared + place_result.boxes_cleared)
			_achievements.track("blockudoku.combo_count", place_result.combo)
			_analytics.log_event("line_cleared", {
				"game": "blockudoku",
				"cleared": place_result.total_cells_cleared,
				"lines": place_result.lines_cleared,
				"boxes": place_result.boxes_cleared,
			})
			if place_result.combo > 1:
				_analytics.log_event("combo", {
					"game": "blockudoku",
					"combo": place_result.combo,
					"bonus": place_result.combo_bonus,
				})
			_sound.play_win()
			_haptic.vibrate_medium()

			# Show combo/multi-clear celebration text
			_show_combo_text(place_result.lines_cleared + place_result.boxes_cleared, place_result.combo)

		_check_for_new_best()
		_update_score_display()

		# Deal new blocks if needed; deal_blocks() now handles game-over detection.
		if place_result.new_blocks_dealt:
			_deal_new_blocks()

		# Game-over is fully determined by logic (set by try_place or deal_blocks).
		if logic.is_game_over:
			if board.is_clear_animating:
				# Wait for clear animation to finish before showing game over
				await board.clear_animation_finished
			_update_undo_redo_buttons()
			_handle_game_over()
		else:
			# Finalise the undo entry now that board visual reflects the completed move.
			logic.commit_move(board.get_state())
			_update_undo_redo_buttons()
			_save_current_state()
	else:
		# Invalid placement — do nothing
		_recorder.record_input(elapsed_time, "placement_rejected", {
			"tray_index": _drag_block_index,
			"grid_x": grid_pos.x,
			"grid_y": grid_pos.y,
		})

	_drag_block_index = -1
	_drag_shape = []


var _shatter_tween: Tween = null


func _pulse_board_for_combo(combo: int) -> void:
	if not PlatformSettings.screen_shake_enabled:
		return

	if _board_pulse_tween and _board_pulse_tween.is_valid():
		_board_pulse_tween.kill()

	board.scale = Vector2.ONE
	var peak_scale_factor := minf(
		COMBO_PULSE_BASE_SCALE + COMBO_PULSE_SCALE_PER_COMBO * float(combo - 1),
		COMBO_PULSE_MAX_SCALE
	)
	_board_pulse_tween = create_tween()
	var pulse_up := _board_pulse_tween.tween_property(board, "scale", Vector2(peak_scale_factor, peak_scale_factor), COMBO_PULSE_HALF_DURATION)
	pulse_up.set_trans(Tween.TRANS_BACK)
	pulse_up.set_ease(Tween.EASE_OUT)
	var pulse_down := _board_pulse_tween.tween_property(board, "scale", Vector2.ONE, COMBO_PULSE_HALF_DURATION)
	pulse_down.set_trans(Tween.TRANS_BACK)
	pulse_down.set_ease(Tween.EASE_IN)

func _handle_game_over() -> void:
	GameEvents.game_ended.emit("blockudoku", "game_over", elapsed_time)
	# Leaderboard: submit final score (blockudoku has one board: standard, higher = better).
	GameEvents.leaderboard_score_ready.emit("blockudoku", "standard", float(logic.score))
	logic.is_game_over = true
	var completed: Dictionary = _recorder.finish_session("game_over", logic.score, elapsed_time, {
		"turns": logic.turns,
		"board_state": board.get_state(),
	})
	_storage.save_replay(completed)
	_update_undo_redo_buttons()
	_record_blockudoku_game_over(logic.score, logic.turns)
	_stats.increment_counter("blockudoku", "games_completed")
	_stats.set_counter("general", "current_win_streak", 0)
	_achievements.check_stats()
	_analytics.log_event("game_over", {
		"game": "blockudoku",
		"won": false,
		"ended_reason": "no_valid_moves",
		"score": logic.score,
		"turns": logic.turns,
		"elapsed_time": elapsed_time,
		"combo_count": logic.combo_count,
	})
	clear_save()
	_haptic.vibrate_success()

	# Shatter animation runs in background
	_play_board_shatter()

	# Show dialog immediately
	_show_game_over_dialog()


func _play_board_shatter() -> void:
	var cell_size := board._get_cell_size()
	var origin := board._get_grid_origin()

	# Gather all filled cells
	var filled_cells: Array[Vector2i] = []
	for r in board.GRID_SIZE:
		for c in board.GRID_SIZE:
			if board.grid[r * board.GRID_SIZE + c] == 1:
				filled_cells.append(Vector2i(c, r))

	# Sweep bottom to top — shatter entire rows at once
	filled_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y > b.y  # Bottom rows first
	)

	# Group cells by row
	var rows_map: Dictionary = {}
	for cell_pos in filled_cells:
		if not rows_map.has(cell_pos.y):
			rows_map[cell_pos.y] = []
		rows_map[cell_pos.y].append(cell_pos)

	var sorted_rows: Array = rows_map.keys()
	sorted_rows.sort()
	sorted_rows.reverse()  # Bottom first

	_shatter_tween = create_tween()
	for row_idx in sorted_rows.size():
		var row_cells: Array = rows_map[sorted_rows[row_idx]]
		var delay := row_idx * 0.06
		_shatter_tween.tween_callback(func() -> void:
			for cell_pos in row_cells:
				var rect := Rect2(
					origin + Vector2(cell_pos.x * cell_size, cell_pos.y * cell_size),
					Vector2(cell_size, cell_size)
				)
				var color: Color = board.cell_colors[cell_pos.y * board.GRID_SIZE + cell_pos.x]
				if color == Color.TRANSPARENT:
					color = AppTheme.get_color("cell_given")
				EffectFactory.glass_shatter(board, rect, color, 6)
				board.grid[cell_pos.y * board.GRID_SIZE + cell_pos.x] = 0
				board.cell_colors[cell_pos.y * board.GRID_SIZE + cell_pos.x] = Color.TRANSPARENT
			board.queue_redraw()
		).set_delay(delay if row_idx > 0 else 0.3)

	if AppTheme.is_neon:
		_shatter_tween.tween_callback(func() -> void:
			var board_center := origin + Vector2(cell_size * 4.5, cell_size * 4.5)
			EffectFactory.neon_ring(board, board_center, Color(2.0, 0.0, 0.3), cell_size * 8.0, 0.5, 1.5)
			AppTheme.screen_shake(8.0, 0.3)
		).set_delay(0.1)


func _stop_shatter() -> void:
	if _shatter_tween and _shatter_tween.is_running():
		_shatter_tween.kill()
		_shatter_tween = null
	# Clear any remaining filled cells instantly
	for i in board.grid.size():
		board.grid[i] = 0
		board.cell_colors[i] = Color.TRANSPARENT
	board.queue_redraw()


func _show_game_over_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Game Over"
	dialog.dialog_text = "Score: %d\nTurns: %d\nTime: %s" % [logic.score, logic.turns, TimeFormat.format_time(elapsed_time, true)]
	dialog.ok_button_text = "Play Again"
	dialog.add_button("Menu", true, "menu")
	dialog.add_button("Save Replay", true, "bookmark")
	dialog.min_size = Vector2i(300, 0)
	dialog.max_size = Vector2i(int(get_viewport_rect().size.x * 0.9), 600)
	add_child(dialog)
	dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		_stop_shatter()
		dialog.queue_free()
		_restart_game()
	)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "menu":
			_stop_shatter()
			dialog.queue_free()
			SceneTransition.navigate(Scenes.BLOCKUDOKU_MENU)
		elif action == "bookmark":
			var success: bool = _storage.bookmark_latest_replay()
			if success:
				dialog.dialog_text += "\n\n✓ Replay bookmarked!"
			else:
				dialog.dialog_text += "\n\n✗ No replay to bookmark"
	)


func _restart_game() -> void:
	SceneTransition.navigate(Scenes.BLOCKUDOKU_GAME, func(game_scene: Node) -> void:
		game_scene.start_new_game()
	)


func _show_combo_text(total_clears: int, combo: int) -> void:
	var text := ""
	# Multi-clear in a single move
	if total_clears >= 8:
		text = "OCTAKILL!!"
	elif total_clears == 7:
		text = "GODLIKE!"
	elif total_clears == 6:
		text = "LEGENDARY!"
	elif total_clears == 5:
		text = "UNSTOPPABLE!"
	elif total_clears == 4:
		text = "Quad!"
	elif total_clears == 3:
		text = "Triple!"
	elif total_clears == 2:
		text = "Double!"

	# Consecutive combo streak
	if combo > 1:
		if text != "":
			text += " %dx" % combo
		else:
			text = "%dx Combo!" % combo

	if text == "":
		return

	var color: Color
	if AppTheme.is_neon:
		color = Color(0.0, 1.5, 1.5) if combo <= 2 else Color(2.0, 0.3, 1.8)
	else:
		color = Color(0.2, 0.6, 1.0) if combo <= 2 else Color(0.8, 0.2, 0.8)

	var cell_size := board._get_cell_size()
	var origin := board._get_grid_origin()
	var center := origin + Vector2(cell_size * 4.5, cell_size * 4.5)
	ComboLabel.create(board, center, text, color)


func _check_for_new_best() -> void:
	if _new_best_shown:
		return
	var high: int = _stats.get_counter("blockudoku", "high_score")
	if logic.score <= high:
		return
	_new_best_shown = true

	var color := Color(0.0, 2.0, 1.5) if AppTheme.is_neon else Color(0.2, 0.75, 1.0)
	var cell_size := board._get_cell_size()
	var origin := board._get_grid_origin()
	var center := origin + Vector2(cell_size * 4.5, cell_size * 4.5)
	ComboLabel.create(board, center, "NEW BEST!", color)
	_haptic.vibrate_medium()


func _on_back() -> void:
	_crash.register_user_action("blockudoku_back_to_menu")
	if not logic.is_game_over:
		var completed: Dictionary = _recorder.finish_session("abandoned", logic.score, elapsed_time, {
			"turns": logic.turns,
			"board_state": board.get_state(),
		})
		_storage.save_replay(completed)
		_stats.set_counter("general", "current_win_streak", 0)
		_achievements.check_stats()
		_save_current_state()
	SceneTransition.navigate(Scenes.BLOCKUDOKU_MENU)


func _update_score_display() -> void:
	score_label.text = "Score: %d" % logic.score


func _on_undo_pressed() -> void:
	var result := logic.undo()
	if not result.success:
		return
	if not result.board_visual.is_empty():
		board.set_state(result.board_visual)
	_build_tray()
	_update_score_display()
	_update_undo_redo_buttons()
	_save_current_state()


func _on_redo_pressed() -> void:
	var result := logic.redo()
	if not result.success:
		return
	if not result.board_visual.is_empty():
		board.set_state(result.board_visual)
	_build_tray()
	_update_score_display()
	_update_undo_redo_buttons()
	_save_current_state()


func _update_undo_redo_buttons() -> void:
	undo_button.disabled = logic.is_game_over or not logic.can_undo()
	redo_button.disabled = logic.is_game_over or not logic.can_redo()


func _serialize_blocks(blocks: Array) -> Array:
	var blocks_data: Array = []
	for shape in blocks:
		blocks_data.append(_serialize_shape(shape))
	return blocks_data


func _serialize_shape(shape: Array) -> Array:
	var shape_data: Array = []
	for cell in shape:
		var c: Vector2i = cell
		shape_data.append({"x": c.x, "y": c.y})
	return shape_data


func _deserialize_blocks(data: Array) -> Array[Array]:
	var blocks: Array[Array] = []
	for block_data in data:
		var shape: Array = []
		for cell_data in block_data:
			if cell_data is Dictionary:
				shape.append(Vector2i(int(cell_data.get("x", 0)), int(cell_data.get("y", 0))))
		blocks.append(shape)
	return blocks


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)


func _record_blockudoku_game_over(final_score: int, final_turns: int) -> void:
	_stats.record("blockudoku", {
		"type": "game_over",
		"score": final_score,
		"turns": final_turns,
	})
	_stats.increment_counter("blockudoku", "total_score", final_score)
	_stats.increment_counter("blockudoku", "total_turns", final_turns)
	var high: int = _stats.get_counter("blockudoku", "high_score")
	if final_score > high:
		_stats.set_counter("blockudoku", "high_score", final_score)
	var best_turns: int = _stats.get_counter("blockudoku", "best_turns")
	if final_turns > best_turns:
		_stats.set_counter("blockudoku", "best_turns", final_turns)
