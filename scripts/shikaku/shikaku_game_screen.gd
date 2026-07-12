extends GameScreen

## Shikaku game screen — board, timer, controls


const SIZE_NAMES := {5: "5×5", 7: "7×7", 8: "8×8", 10: "10×10", 12: "12×12", 15: "15×15"}

# Game state
var grid_width: int = 10
var grid_height: int = 10
var is_paused: bool = false
var logic: ShikakuLogic = ShikakuLogic.new()

# Cheat
var _cheat_active: bool = false
var _cheat_timer: float = 0.0
const CHEAT_INTERVAL := 0.3

# Node references
@onready var board: ShikakuBoard = %ShikakuBoard
@onready var size_label: Label = %SizeLabel
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var hint_button: Button = %HintButton
@onready var pause_button: Button = %PauseButton
@onready var back_button: Button = %BackButton
@onready var settings_button: Button = %SettingsButton



# --- GameScreen overrides ---

func _get_game_id() -> String:
	return "shikaku"


func _get_scene_path() -> String:
	return Scenes.SHIKAKU_GAME


func _get_save_adapter() -> GameSaveAdapter:
	return ShikakuSaveAdapter.new()


func _is_initialized() -> bool:
	return not logic.numbers.is_empty()


func _is_completed() -> bool:
	return logic.is_completed


func _serialize_state() -> Dictionary:
	var data: Dictionary = logic.serialize()
	data["elapsed_time"] = elapsed_time
	data["replay_id"] = replay_id
	return data


func _deserialize_state(data: Dictionary) -> void:
	resume_game(data)


func _get_crash_state() -> Dictionary:
	return {
		"game": "shikaku",
		"width": grid_width,
		"height": grid_height,
		"elapsed_time": elapsed_time,
		"is_completed": logic.is_completed,
		"is_paused": is_paused,
		"hints_used": logic.hints_used,
		"placed_rects": logic.placed_rects.size(),
	}


func _apply_game_theme() -> void:
	_apply_theme()


func _on_game_screen_ready() -> void:
	board.rectangle_placed.connect(_on_rectangle_placed)
	board.rectangle_tapped.connect(_on_rectangle_tapped)
	undo_button.pressed.connect(_on_undo)
	redo_button.pressed.connect(_on_redo)
	hint_button.pressed.connect(_on_hint)
	pause_button.pressed.connect(_on_pause)
	back_button.pressed.connect(_on_back)
	_update_button_states()


func start_new_game(w: int, h: int) -> void:
	grid_width = w
	grid_height = h
	begin_session()


func launch(params: LaunchParams) -> void:
	start_new_game(params.option_value, params.option_value)


func resume_game(data: Dictionary) -> void:
	grid_width = data.get("width", 10)
	grid_height = data.get("height", 10)
	begin_session(data)


# --- Session ceremony hooks ---

func _should_tick_timer() -> bool:
	return not logic.is_completed and not is_paused


func _get_start_crash_params() -> Dictionary:
	return {"width": grid_width, "height": grid_height}


func _get_resume_crash_params(saved_data: Dictionary) -> Dictionary:
	return {"width": saved_data.get("width", 10), "height": saved_data.get("height", 10)}


func _get_initial_state() -> Dictionary:
	return {
		"width": grid_width,
		"height": grid_height,
		"numbers": logic.serialize().get("numbers", {}),
	}


func _get_settings_snapshot() -> Dictionary:
	return {"show_timer": PlatformSettings.show_timer}


func _setup_game(saved_data: Dictionary) -> void:
	if saved_data.is_empty():
		logic.init_new_game(grid_width, grid_height, random_seed)
	else:
		logic.init_from_save(saved_data)
	grid_width = logic.grid_width
	grid_height = logic.grid_height
	random_seed = logic.random_seed
	board.setup(grid_width, grid_height, logic.numbers)
	for rect in logic.placed_rects:
		board.add_rect(rect)
	size_label.text = SIZE_NAMES.get(grid_width, "%dx%d" % [grid_width, grid_height])
	_update_button_states()


func _increment_stats() -> void:
	_stats.increment_counter("shikaku", "games_started")
	_stats.increment_counter("shikaku", "started_s%d" % grid_width)


func _get_analytics_params() -> Dictionary:
	return {"game": "shikaku", "width": grid_width, "height": grid_height}


func _process(delta: float) -> void:
	super._process(delta)

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
			print("Shikaku cheat auto-solve: %s" % ("ON" if _cheat_active else "OFF"))
			get_viewport().set_input_as_handled()


func _on_rectangle_placed(rect: Rect2i) -> void:
	if logic.is_completed:
		return
	var result: ShikakuLogic.PlaceRectResult = logic.place_rectangle(rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	if not result.valid:
		return
	GameEvents.move_made.emit("shikaku", {
		"elapsed_time": elapsed_time,
		"event_type": "rectangle_placed",
		"x": rect.position.x,
		"y": rect.position.y,
		"w": rect.size.x,
		"h": rect.size.y,
	})
	board.add_rect(rect)
	_sound.play_place()
	_haptic.vibrate_light()
	# Neon shockwave on rect placement
	if AppTheme.is_neon:
		var cell_size := board._get_cell_size()
		var origin := board._get_grid_origin()
		var center := origin + Vector2(
			(rect.position.x + rect.size.x / 2.0) * cell_size,
			(rect.position.y + rect.size.y / 2.0) * cell_size
		)
		EffectFactory.neon_ring(board, center, Color(0.0, 1.5, 1.5), cell_size * 2.5, 0.25, 0.3)
	_update_button_states()
	if result.game_won:
		_handle_win()
	_save_current_state()


func _on_rectangle_tapped(index: int) -> void:
	if logic.is_completed:
		return
	if index < 0 or index >= board.placed_rects.size() or index >= logic.placed_rects.size():
		return
	var rect: Rect2i = board.placed_rects[index]
	var result: ShikakuLogic.RemoveRectResult = logic.remove_rectangle(rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	if not result.was_present:
		return
	_recorder.record_input(elapsed_time, "rectangle_removed", {"index": index})
	board.remove_rect(index)
	_haptic.vibrate_light()
	_update_button_states()
	_save_current_state()


func _on_undo() -> void:
	if logic.is_completed:
		return
	var result: ShikakuLogic.UndoRedoResult = logic.undo()
	if result.action_type.is_empty():
		return
	if result.action_type == "place":
		# Undo a placement = remove the last rect
		var placed_rect: Rect2i = _rect_from_dict(result.rect)
		# Find and remove it
		for i in range(board.placed_rects.size() - 1, -1, -1):
			if board.placed_rects[i] == placed_rect:
				_recorder.record_input(elapsed_time, "rectangle_removed", {"index": i})
				board.remove_rect(i)
				break
	elif result.action_type == "remove":
		# Undo a removal = re-add the rect
		var removed_rect: Rect2i = _rect_from_dict(result.rect)
		_recorder.record_input(elapsed_time, "rectangle_placed", {
			"x": removed_rect.position.x,
			"y": removed_rect.position.y,
			"w": removed_rect.size.x,
			"h": removed_rect.size.y,
		})
		board.add_rect(removed_rect)
	_update_button_states()
	_save_current_state()


func _on_redo() -> void:
	if logic.is_completed:
		return
	var result: ShikakuLogic.UndoRedoResult = logic.redo()
	if result.action_type.is_empty():
		return
	if result.action_type == "place":
		var redo_rect: Rect2i = _rect_from_dict(result.rect)
		_recorder.record_input(elapsed_time, "rectangle_placed", {
			"x": redo_rect.position.x,
			"y": redo_rect.position.y,
			"w": redo_rect.size.x,
			"h": redo_rect.size.y,
		})
		board.add_rect(redo_rect)
	elif result.action_type == "remove":
		var removed_rect: Rect2i = _rect_from_dict(result.rect)
		for i in range(board.placed_rects.size() - 1, -1, -1):
			if board.placed_rects[i] == removed_rect:
				_recorder.record_input(elapsed_time, "rectangle_removed", {"index": i})
				board.remove_rect(i)
				break
	_update_button_states()
	_save_current_state()


func _on_hint() -> void:
	if not logic.can_hint():
		return
	var result: ShikakuLogic.HintResult = logic.use_hint()
	if result.rect.is_empty():
		return
	_crash.register_user_action("shikaku_hint_used")
	var hint_rect: Rect2i = _rect_from_dict(result.rect)
	_recorder.record_input(elapsed_time, "rectangle_placed", {
		"x": hint_rect.position.x,
		"y": hint_rect.position.y,
		"w": hint_rect.size.x,
		"h": hint_rect.size.y,
	})
	board.add_rect(hint_rect)
	_sound.play_place()
	_haptic.vibrate_medium()
	_update_button_states()
	if result.game_won:
		_handle_win()
	_save_current_state()


func _on_pause() -> void:
	is_paused = not is_paused
	pause_button.text = "Resume" if is_paused else "Pause"
	board.visible = not is_paused
	_crash.register_user_action("shikaku_pause_toggled", {"is_paused": is_paused})


func _on_back() -> void:
	var completed := _recorder.finish_session("abandoned", logic.placed_rects.size(), elapsed_time, {
		"width": grid_width,
		"height": grid_height,
	})
	_storage.save_replay(completed)
	_crash.register_user_action("shikaku_back_to_menu")
	if not logic.is_completed:
		_stats.set_counter("general", "current_win_streak", 0)
		_achievements.check_stats()
	_save_current_state()
	SceneTransition.navigate(Scenes.SHIKAKU_MENU)


func _handle_win() -> void:
	GameEvents.game_ended.emit("shikaku", "win", elapsed_time)
	# Leaderboard: submit completion time for board sizes with registered boards (5/7/10/14).
	if grid_width in [5, 7, 10, 14]:
		GameEvents.leaderboard_score_ready.emit("shikaku", str(grid_width), elapsed_time)
	var completed := _recorder.finish_session("win", logic.placed_rects.size(), elapsed_time, {
		"width": grid_width,
		"height": grid_height,
		"hints_used": logic.hints_used,
	})
	_storage.save_replay(completed)
	var is_new_best := _is_new_best_time()
	_record_shikaku_completion(grid_width, elapsed_time)
	_stats.increment_counter("general", "games_won")
	_stats.increment_counter("general", "current_win_streak")
	_stats.increment_counter("shikaku", "games_won")
	if elapsed_time < 60.0:
		_stats.increment_counter("shikaku", "wins_under_60s")
	_achievements.check_stats()
	_analytics.log_event("game_over", {
		"game": "shikaku",
		"won": true,
		"width": grid_width,
		"height": grid_height,
		"elapsed_time": elapsed_time,
		"hints_used": logic.hints_used,
	})
	clear_save()
	_sound.play_win()
	_haptic.vibrate_success()
	if is_new_best:
		_show_new_best_indicator()
	# Neon win shockwave
	if AppTheme.is_neon:
		var cell_size := board._get_cell_size()
		var origin := board._get_grid_origin()
		var center := origin + Vector2(
			(board.grid_width / 2.0) * cell_size,
			(board.grid_height / 2.0) * cell_size
		)
		EffectFactory.neon_ring(board, center, Color(0.0, 2.0, 1.5), cell_size * 6.0, 0.5, 1.2)
		AppTheme.screen_shake(6.0, 0.2)
	board.flash_all(Color(1.2, 1.1, 0.8), 0.4)
	var timer := get_tree().create_timer(0.5)
	timer.timeout.connect(_show_win_dialog)


func _is_new_best_time() -> bool:
	var best_ms: int = _stats.get_counter("shikaku", "best_s%d" % grid_width)
	return best_ms == 0 or elapsed_time < (float(best_ms) / 1000.0)


func _show_new_best_indicator() -> void:
	var cell_size := board._get_cell_size()
	var origin := board._get_grid_origin()
	var center := origin + Vector2(
		(board.grid_width / 2.0) * cell_size,
		(board.grid_height / 2.0) * cell_size
	)
	var color := Color(0.0, 2.0, 1.5) if AppTheme.is_neon else Color(0.2, 0.75, 1.0)
	ComboLabel.create(board, center, "NEW BEST!", color)
	_haptic.vibrate_medium()


func _show_win_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Congratulations!"
	dialog.dialog_text = "You solved the %s puzzle\nin %s!" % [SIZE_NAMES.get(grid_width, ""), TimeFormat.format_time(elapsed_time, true)]
	if logic.hints_used > 0:
		dialog.dialog_text += "\nHints used: %d" % logic.hints_used
	dialog.ok_button_text = "Play Again"
	dialog.add_button("Menu", true, "menu")
	dialog.add_button("Save Replay", true, "bookmark")
	dialog.min_size = Vector2i(300, 0)
	dialog.max_size = Vector2i(int(get_viewport_rect().size.x * 0.9), 600)
	add_child(dialog)
	dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		_restart_same_game()
	)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "menu":
			dialog.queue_free()
			SceneTransition.navigate(Scenes.SHIKAKU_MENU)
		elif action == "bookmark":
			var success := _storage.bookmark_latest_replay()
			if success:
				dialog.dialog_text += "\n\n✓ Replay bookmarked!"
			else:
				dialog.dialog_text += "\n\n✗ No replay to bookmark"
	)


func _restart_same_game() -> void:
	var w := grid_width
	var h := grid_height
	SceneTransition.navigate(Scenes.SHIKAKU_GAME, func(game_scene: Node) -> void:
		game_scene.start_new_game(w, h)
	)


func _update_button_states() -> void:
	undo_button.disabled = not logic.can_undo()
	redo_button.disabled = not logic.can_redo()
	hint_button.disabled = not logic.can_hint()


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)


func _cheat_place_one() -> void:
	if logic.solution.is_empty():
		_cheat_active = false
		return
	# Find a solution rect not already placed
	for rect in logic.get_unplaced_solution_rects():
		var result: ShikakuLogic.PlaceRectResult = logic.place_rectangle(rect.position.x, rect.position.y, rect.size.x, rect.size.y)
		if not result.valid:
			continue
		board.add_rect(rect)
		_sound.play_place()
		if result.game_won:
			_handle_win()
		_save_current_state()
		return
	_cheat_active = false


func _rect_from_dict(data: Dictionary) -> Rect2i:
	return Rect2i(int(data.get("x", 0)), int(data.get("y", 0)), int(data.get("w", 1)), int(data.get("h", 1)))


func _record_shikaku_completion(grid_size: int, time: float) -> void:
	_stats.record("shikaku", {
		"type": "completion",
		"grid_size": grid_size,
		"time": time,
	})
	_stats.increment_counter("shikaku", "completed_s%d" % grid_size)
	# Best time (stored as ms int)
	var best_ms: int = _stats.get_counter("shikaku", "best_s%d" % grid_size)
	var time_ms := int(time * 1000)
	if best_ms == 0 or time_ms < best_ms:
		_stats.set_counter("shikaku", "best_s%d" % grid_size, time_ms)
	# Streak
	var streak: int = _stats.get_counter("shikaku", "current_streak") + 1
	_stats.set_counter("shikaku", "current_streak", streak)
	var best_streak: int = _stats.get_counter("shikaku", "best_streak")
	if streak > best_streak:
		_stats.set_counter("shikaku", "best_streak", streak)
