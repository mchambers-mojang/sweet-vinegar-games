extends Control

## Blockudoku game screen — board, score, block tray, drag-to-place

const BLOCKS_PER_SET := 3
const ROTATE_TAP_DISTANCE_THRESHOLD := 12.0
const COMBO_PULSE_BASE_SCALE := 1.02
const COMBO_PULSE_SCALE_PER_COMBO := 0.002
const COMBO_PULSE_MAX_SCALE := 1.04
const COMBO_PULSE_HALF_DURATION := 0.15

# Game state
var score: int = 0
var turns: int = 0
var combo_count: int = 0
var is_game_over: bool = false
var _new_best_shown: bool = false

# Current set of blocks to place (each is Array of Vector2i)
var available_blocks: Array[Array] = []
var blocks_placed_this_set: int = 0

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
@onready var timer_label: Label = %TimerLabel
@onready var back_button: Button = %BackButton
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var block_tray: HBoxContainer = %BlockTray
@onready var settings_button: Button = %SettingsButton

var elapsed_time: float = 0.0
var random_seed: int = 0
var replay_id: String = ""
var _rng := RandomNumberGenerator.new()

# Block tray piece display nodes
var _tray_panels: Array[Control] = []
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []


func _ready() -> void:
	CrashReporter.register_state_provider(_get_crash_state)
	CrashReporter.register_user_action("blockudoku_screen_opened")
	back_button.pressed.connect(_on_back)
	undo_button.pressed.connect(_on_undo_pressed)
	redo_button.pressed.connect(_on_redo_pressed)
	settings_button.pressed.connect(func() -> void:
		var SettingsScreen := load("res://scripts/settings_screen.gd")
		SettingsScreen.return_scene = "res://scenes/blockudoku_game.tscn"
		SceneTransition.transition_to("res://scenes/settings.tscn")
	)
	_setup_help_button()
	_apply_theme()
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_theme())
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)

	# Cosmetic drag effect is now a global autoload


func _exit_tree() -> void:
	CrashReporter.unregister_state_provider(_get_crash_state)


func _setup_help_button() -> void:
	var btn := Button.new()
	btn.text = "?"
	btn.custom_minimum_size = Vector2(36, 0)
	btn.pressed.connect(func() -> void: HowToPlay.show_for(self, "blockudoku"))
	back_button.get_parent().add_child(btn)


func start_new_game() -> void:
	CrashReporter.register_user_action("blockudoku_start_new_game")
	score = 0
	turns = 0
	combo_count = 0
	_new_best_shown = false
	elapsed_time = 0.0
	is_game_over = false
	random_seed = _create_session_seed()
	_rng.seed = random_seed
	undo_stack.clear()
	redo_stack.clear()
	board.reset()
	_deal_new_blocks()
	_update_score_display()
	_update_undo_redo_buttons()
	BlockudokuStatsManager.record_game_started()
	replay_id = ReplayManager.start_session("blockudoku", random_seed, {
		"board_state": board.get_state(),
		"available_blocks": _serialize_blocks(available_blocks),
	}, {
		"drag_offset": SettingsManager.blockudoku_drag_offset,
		"show_timer": SettingsManager.show_timer,
	})
	AchievementManager.track_game_started("blockudoku")
	AnalyticsManager.log_event("game_started", {
		"game": "blockudoku",
	})
	_save_current_state()


func resume_game(data: Dictionary) -> void:
	CrashReporter.register_user_action("blockudoku_resume_game", {"score": data.get("score", 0)})
	score = data.get("score", 0)
	turns = data.get("turns", 0)
	combo_count = data.get("combo_count", 0)
	_new_best_shown = data.get("new_best_shown", false)
	elapsed_time = data.get("elapsed_time", 0.0)
	is_game_over = false
	random_seed = int(data.get("random_seed", 0))
	_rng.seed = random_seed
	if data.has("rng_state"):
		_rng.state = int(data.get("rng_state", 0))
	replay_id = str(data.get("replay_id", ""))
	undo_stack.clear()
	redo_stack.clear()
	board.set_state(data.get("board_state", {}))

	# Restore available blocks
	available_blocks = _deserialize_blocks(data.get("available_blocks", []))

	blocks_placed_this_set = data.get("blocks_placed_this_set", 0)
	_build_tray()
	_update_score_display()
	if not ReplayManager.has_active_session():
		replay_id = ReplayManager.start_session("blockudoku", random_seed, {
			"board_state": board.get_state(),
			"available_blocks": _serialize_blocks(available_blocks),
		}, {
			"drag_offset": SettingsManager.blockudoku_drag_offset,
			"show_timer": SettingsManager.show_timer,
		})
	_update_undo_redo_buttons()


func _process(delta: float) -> void:
	if not is_game_over:
		elapsed_time += delta
		if SettingsManager.show_timer:
			timer_label.text = _format_time(elapsed_time)
			timer_label.visible = true
		else:
			timer_label.visible = false


func _deal_new_blocks() -> void:
	available_blocks = BlockudokuShapes.pick_random(BLOCKS_PER_SET, _rng)
	# Normalize all shapes
	for i in available_blocks.size():
		available_blocks[i] = BlockudokuShapes.normalize(available_blocks[i])
	blocks_placed_this_set = 0
	_build_tray()


func _build_tray() -> void:
	# Clear existing
	for child in block_tray.get_children():
		child.queue_free()
	_tray_panels.clear()

	var cell_px := 20.0
	var tray_height := block_tray.custom_minimum_size.y

	for i in available_blocks.size():
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
		if index >= available_blocks.size():
			return
		var s: Array = available_blocks[index]
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
		if is_game_over or board.is_clear_animating:
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
	_drag_shape = available_blocks[index]
	_drag_screen_pos = screen_pos
	_drag_start_screen_pos = screen_pos
	_drag_moved = false
	_drag_last_grid_pos = Vector2i(-999, -999)
	ReplayManager.record_input(elapsed_time, "piece_selected", {
		"tray_index": index,
	})
	DragEffect.suppress()

	# Visual + haptic feedback on grab
	HapticManager.vibrate_light()
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
	var offset_multiplier := SettingsManager.blockudoku_drag_offset  # 0=None, 1=Small, 2=Medium, 3=Large
	if offset_multiplier > 0:
		local_pos.y -= cell_size * offset_multiplier
	var grid_pos := board.screen_to_grid(local_pos)
	if grid_pos != _drag_last_grid_pos:
		# Only haptic if we've moved before (skip initial grab) and piece is on the board
		if _drag_last_grid_pos != Vector2i(-999, -999) and grid_pos.x >= 0 and grid_pos.x < 9 and grid_pos.y >= 0 and grid_pos.y < 9:
			HapticManager.vibrate_light()
		_drag_last_grid_pos = grid_pos
	board.show_preview(_drag_shape, grid_pos.x, grid_pos.y)


func _end_drag(screen_pos: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
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
	var offset_multiplier := SettingsManager.blockudoku_drag_offset
	if offset_multiplier > 0:
		local_pos.y -= cell_size * offset_multiplier
	var grid_pos := board.screen_to_grid(local_pos)

	board.clear_preview()

	if SettingsManager.blockudoku_rotation_mode and not _drag_moved and _drag_block_index >= 0 and _drag_block_index < available_blocks.size():
		var shape: Array = available_blocks[_drag_block_index]
		if shape.size() > 0:
			var rotated_shape: Array = BlockudokuShapes.rotate_clockwise(shape)
			ReplayManager.record_input(elapsed_time, "piece_rotated", {
				"tray_index": _drag_block_index,
				"shape": _serialize_shape(rotated_shape),
			})
			available_blocks[_drag_block_index] = rotated_shape
			if _drag_block_index < _tray_panels.size():
				_tray_panels[_drag_block_index].queue_redraw()
			_save_current_state()
		_drag_block_index = -1
		_drag_shape = []
		return

	if board.can_place(_drag_shape, grid_pos.x, grid_pos.y):
		var before_state := _capture_move_state()
		ReplayManager.record_input(elapsed_time, "piece_placed", {
			"tray_index": _drag_block_index,
			"grid_x": grid_pos.x,
			"grid_y": grid_pos.y,
			"shape": _serialize_shape(_drag_shape),
		})
		var block_color := BlockudokuShapes.get_shape_color(_drag_shape)
		board.place_block(_drag_shape, grid_pos.x, grid_pos.y, block_color)
		SoundManager.play_place()
		HapticManager.vibrate_light()

		# Neon placement effects
		if ThemeManager.is_neon:

			# Per-cell burst — small burst on each cell of the shape
			for cell_offset in _drag_shape:
				var co: Vector2i = cell_offset
				var cell_center := origin + Vector2(
					(grid_pos.x + co.x + 0.5) * cell_size,
					(grid_pos.y + co.y + 0.5) * cell_size
				)
				NeonBurst.create(board, cell_center, block_color, 6, 0.5)

			# Expanding ring from shape center
			var bounds := BlockudokuShapes.get_bounds(_drag_shape)
			var shape_center := origin + Vector2(
				(grid_pos.x + bounds.x / 2.0) * cell_size,
				(grid_pos.y + bounds.y / 2.0) * cell_size
			)
			NeonRing.create(board, shape_center, block_color, cell_size * 2.0, 0.25, 0.3)

			# Cell flash — briefly brighten placed cells
			board.flash_placed_cells(_drag_shape, grid_pos.x, grid_pos.y, block_color)

			# Light screen shake
			NeonFxManager.screen_shake(3.0, 0.1)

		# Remove from available blocks
		available_blocks[_drag_block_index] = []
		blocks_placed_this_set += 1

		# Hide the tray panel
		if _drag_block_index < _tray_panels.size():
			_tray_panels[_drag_block_index].visible = false

		# Score placement
		var shape_size := _drag_shape.size()
		score += shape_size
		turns += 1
		AnalyticsManager.log_event("piece_placed", {
			"game": "blockudoku",
			"turn": turns,
			"cells": shape_size,
			"x": grid_pos.x,
			"y": grid_pos.y,
		})

		# Check for clears
		var result := board.check_and_clear()
		var cleared: int = result["cleared"]
		var lines: int = result["lines"]
		var boxes: int = result["boxes"]

		if cleared > 0:
			# Combo tracking
			combo_count += 1
			var combo_bonus := 0
			if combo_count > 1:
				combo_bonus = combo_count * 10
				if lines + boxes >= 2:
					_pulse_board_for_combo(combo_count)
				# Scale shockwave with combo
				if ThemeManager.is_neon:
					var combo_center := origin + Vector2(cell_size * 4.5, cell_size * 4.5)
					var combo_amp := minf(0.5 + combo_count * 0.3, 2.0)
					NeonRing.create(board, combo_center, Color(2.0, 0.3, 1.8), cell_size * (4.0 + combo_count), 0.4, combo_amp)
			# Scoring: 10 per line/box cleared + combo bonus
			var clear_score := (lines + boxes) * 18 + cleared + combo_bonus
			score += clear_score
			BlockudokuStatsManager.record_clears(lines + boxes)
			AchievementManager.track_blockudoku_clear(lines + boxes)
			AnalyticsManager.log_event("line_cleared", {
				"game": "blockudoku",
				"cleared": cleared,
				"lines": lines,
				"boxes": boxes,
			})
			if combo_count > 1:
				AnalyticsManager.log_event("combo", {
					"game": "blockudoku",
					"combo": combo_count,
					"bonus": combo_bonus,
				})
			SoundManager.play_win()
			HapticManager.vibrate_medium()

			# Show combo/multi-clear celebration text
			_show_combo_text(lines + boxes, combo_count)
		else:
			combo_count = 0

		_check_for_new_best()
		_update_score_display()

		# Check if we need new blocks
		if blocks_placed_this_set >= BLOCKS_PER_SET:
			_deal_new_blocks()

		# Check game over
		var remaining_shapes: Array = []
		for shape in available_blocks:
			if shape.size() > 0:
				remaining_shapes.append(shape)
		redo_stack.clear()
		if not board.has_valid_placement(remaining_shapes):
			_update_undo_redo_buttons()
			_handle_game_over()
		else:
			undo_stack.append({
				"before": before_state,
				"after": _capture_move_state(),
			})
			_update_undo_redo_buttons()
			_save_current_state()
	else:
		# Invalid placement — do nothing
		ReplayManager.record_input(elapsed_time, "placement_rejected", {
			"tray_index": _drag_block_index,
			"grid_x": grid_pos.x,
			"grid_y": grid_pos.y,
		})

	_drag_block_index = -1
	_drag_shape = []


var _shatter_tween: Tween = null


func _pulse_board_for_combo(combo: int) -> void:
	if not SettingsManager.screen_shake_enabled:
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
	CrashReporter.register_user_action("blockudoku_game_over", {"score": score, "turns": turns})
	is_game_over = true
	ReplayManager.finish_session("game_over", score, elapsed_time, {
		"turns": turns,
		"board_state": board.get_state(),
	})
	_update_undo_redo_buttons()
	BlockudokuStatsManager.record_game_over(score, turns)
	AnalyticsManager.log_event("game_over", {
		"game": "blockudoku",
		"won": false,
		"ended_reason": "no_valid_moves",
		"score": score,
		"turns": turns,
		"elapsed_time": elapsed_time,
		"combo_count": combo_count,
	})
	BlockudokuSaveManager.clear_save()
	HapticManager.vibrate_success()

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
					color = ThemeManager.get_color("cell_given")
				GlassShatter.create(board, rect, color, 6)
				board.grid[cell_pos.y * board.GRID_SIZE + cell_pos.x] = 0
				board.cell_colors[cell_pos.y * board.GRID_SIZE + cell_pos.x] = Color.TRANSPARENT
			board.queue_redraw()
		).set_delay(delay if row_idx > 0 else 0.3)

	if ThemeManager.is_neon:
		_shatter_tween.tween_callback(func() -> void:
			var board_center := origin + Vector2(cell_size * 4.5, cell_size * 4.5)
			NeonRing.create(board, board_center, Color(2.0, 0.0, 0.3), cell_size * 8.0, 0.5, 1.5)
			NeonFxManager.screen_shake(8.0, 0.3)
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
	dialog.dialog_text = "Score: %d\nTurns: %d" % [score, turns]
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
			SceneTransition.transition_to("res://scenes/blockudoku_menu.tscn")
		elif action == "bookmark":
			var success := ReplayManager.bookmark_latest_replay()
			if success:
				dialog.dialog_text += "\n\n✓ Replay bookmarked!"
			else:
				dialog.dialog_text += "\n\n✗ No replay to bookmark"
	)


func _restart_game() -> void:
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load("res://scenes/blockudoku_game.tscn").instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.start_new_game()
		queue_free()
	)


func _show_combo_text(total_clears: int, combo: int) -> void:
	var text := ""
	# Multi-clear in a single move
	if total_clears >= 3:
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
	if ThemeManager.is_neon:
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
	if not BlockudokuStatsManager.record_high_score_candidate(score):
		return
	_new_best_shown = true

	var color := Color(0.0, 2.0, 1.5) if ThemeManager.is_neon else Color(0.2, 0.75, 1.0)
	var cell_size := board._get_cell_size()
	var origin := board._get_grid_origin()
	var center := origin + Vector2(cell_size * 4.5, cell_size * 4.5)
	ComboLabel.create(board, center, "NEW BEST!", color)
	HapticManager.vibrate_medium()


func _on_back() -> void:
	CrashReporter.register_user_action("blockudoku_back_to_menu")
	if not is_game_over:
		ReplayManager.finish_session("abandoned", score, elapsed_time, {
			"turns": turns,
			"board_state": board.get_state(),
		})
		_save_current_state()
	SceneTransition.transition_to("res://scenes/blockudoku_menu.tscn")


func _update_score_display() -> void:
	score_label.text = "Score: %d" % score


func _on_undo_pressed() -> void:
	if is_game_over:
		return
	if undo_stack.is_empty():
		return
	var move: Dictionary = undo_stack.pop_back()
	redo_stack.append(move)
	_apply_move_state(move.get("before", {}))
	_update_undo_redo_buttons()
	_save_current_state()


func _on_redo_pressed() -> void:
	if is_game_over:
		return
	if redo_stack.is_empty():
		return
	var move: Dictionary = redo_stack.pop_back()
	undo_stack.append(move)
	_apply_move_state(move.get("after", {}))
	_update_undo_redo_buttons()
	_save_current_state()


func _update_undo_redo_buttons() -> void:
	undo_button.disabled = is_game_over or undo_stack.is_empty()
	redo_button.disabled = is_game_over or redo_stack.is_empty()


func _capture_move_state() -> Dictionary:
	return {
		"score": score,
		"turns": turns,
		"combo_count": combo_count,
		"board_state": board.get_state(),
		"available_blocks": _serialize_blocks(available_blocks),
		"blocks_placed_this_set": blocks_placed_this_set,
		"rng_state": _rng.state,
	}


func _apply_move_state(state: Dictionary) -> void:
	score = state.get("score", score)
	turns = state.get("turns", turns)
	combo_count = state.get("combo_count", combo_count)
	board.set_state(state.get("board_state", board.get_state()))
	available_blocks = _deserialize_blocks(state.get("available_blocks", []))
	blocks_placed_this_set = state.get("blocks_placed_this_set", blocks_placed_this_set)
	if state.has("rng_state"):
		_rng.state = state.get("rng_state")
	_build_tray()
	_update_score_display()


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


func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%d:%02d" % [mins, secs]


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("background")
	add_theme_stylebox_override("panel", style)


func _save_current_state() -> void:
	if is_game_over:
		return
	BlockudokuSaveManager.save_game({
		"score": score,
		"turns": turns,
		"combo_count": combo_count,
		"new_best_shown": _new_best_shown,
		"elapsed_time": elapsed_time,
		"board_state": board.get_state(),
		"available_blocks": _serialize_blocks(available_blocks),
		"blocks_placed_this_set": blocks_placed_this_set,
		"random_seed": random_seed,
		"rng_state": _rng.state,
		"replay_id": replay_id,
	})


func _create_session_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(Time.get_ticks_usec() ^ rng.randi())


func _get_crash_state() -> Dictionary:
	return {
		"game": "blockudoku",
		"score": score,
		"turns": turns,
		"combo_count": combo_count,
		"elapsed_time": elapsed_time,
		"is_game_over": is_game_over,
		"blocks_placed_this_set": blocks_placed_this_set,
		"available_block_count": available_blocks.size(),
	}
