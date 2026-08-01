extends GameScreen

## Shikaku game screen — board, timer, controls


const SIZE_NAMES := {5: "5×5", 7: "7×7", 8: "8×8", 10: "10×10", 12: "12×12", 15: "15×15"}

# Game state
var grid_width: int = 10
var grid_height: int = 10
var mode: int = ShikakuLogic.RULE_SET_STANDARD
var is_paused: bool = false
var logic: ShikakuLogic = ShikakuLogic.new()

# Cheat
var _cheat_active: bool = false
var _cheat_timer: float = 0.0
const CHEAT_INTERVAL := 0.3

# Background generation state (follows the KillerSudoku thread pattern)
## Pre-generated puzzle data stored by the generation thread.
var _pending_shikaku_data: Dictionary = {}
## Background generation thread (non-null while generation is running).
var _gen_thread: Thread = null
## Mutex protecting _generation_cancelled.
var _generation_mutex: Mutex = Mutex.new()
## Set to true before joining the thread so deferred callbacks become no-ops.
var _generation_cancelled: bool = false
## Tween driving the "Generating…" spinner animation.
var _spinner_tween: Tween = null

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
	return not logic.anchors.is_empty()


func _is_completed() -> bool:
	return logic.is_completed


func _serialize_state() -> Dictionary:
	var data: Dictionary = logic.serialize()
	data["elapsed_time"] = elapsed_time
	data["replay_id"] = replay_id
	data["mode"] = mode
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


func start_new_game(w: int, h: int, p_mode: int = ShikakuLogic.RULE_SET_STANDARD) -> void:
	grid_width = w
	grid_height = h
	mode = p_mode
	_set_generation_cancelled(false)
	_show_generating_spinner(true)
	_gen_thread = Thread.new()
	_gen_thread.start(_run_generation)
	# begin_session() is called by _on_generation_complete() after the thread finishes.


func launch(params: LaunchParams) -> void:
	start_new_game(params.option_value, params.option_value, params.rule_set)


func resume_game(data: Dictionary) -> void:
	grid_width = data.get("width", 10)
	grid_height = data.get("height", 10)
	mode = int(data.get("mode", ShikakuLogic.RULE_SET_STANDARD))
	begin_session(data)


# --- Background generation (follows the KillerSudokuGenerator thread pattern) ---

func _exit_tree() -> void:
	# Signal cancellation under the mutex so the worker can poll it, then join.
	_set_generation_cancelled(true)
	if _gen_thread != null:
		_gen_thread.wait_to_finish()
		_gen_thread = null
	if _spinner_tween != null:
		_spinner_tween.kill()
		_spinner_tween = null
	super._exit_tree()


## Mutex-protected write: sets the cancellation flag.
func _set_generation_cancelled(val: bool) -> void:
	_generation_mutex.lock()
	_generation_cancelled = val
	_generation_mutex.unlock()


## Mutex-protected read: returns the current cancellation flag.
## Safe to call from any thread.
func _get_generation_cancelled() -> bool:
	_generation_mutex.lock()
	var val := _generation_cancelled
	_generation_mutex.unlock()
	return val


## Runs in a background thread: generates a complete Shikaku puzzle.
func _run_generation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var gen_seed := int(Time.get_ticks_usec()) ^ rng.randi()
	var result: Dictionary = ShikakuGenerator.generate(
		grid_width, grid_height, gen_seed, mode,
		func() -> bool: return _get_generation_cancelled()
	)
	if result.is_empty():
		_pending_shikaku_data = {}
	else:
		_pending_shikaku_data = result.duplicate()
		_pending_shikaku_data["random_seed"] = gen_seed
	if not _get_generation_cancelled():
		call_deferred("_on_generation_complete")


## Called on the main thread after generation finishes.
func _on_generation_complete() -> void:
	if _get_generation_cancelled():
		return
	if _gen_thread != null:
		_gen_thread.wait_to_finish()
		_gen_thread = null
	_show_generating_spinner(false)
	if _pending_shikaku_data.is_empty():
		_suppress_auto_resume = true
		if SceneTransition.is_transitioning:
			SceneTransition.transition_completed.connect(
				_abort_generation_failure, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
		else:
			_abort_generation_failure()
		return
	begin_session()


func _abort_generation_failure() -> void:
	SceneTransition.navigate(Scenes.SHIKAKU_MENU)


## Show or hide the "Generating…" overlay label with animated cycling dots.
func _show_generating_spinner(visible: bool) -> void:
	var overlay := get_node_or_null("_GeneratingOverlay")
	if overlay == null:
		if not visible:
			return
		var lbl := Label.new()
		lbl.name = "_GeneratingOverlay"
		lbl.text = "Generating puzzle"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.z_index = 10
		var style := StyleBoxFlat.new()
		style.bg_color = AppTheme.get_color("background")
		style.bg_color.a = 0.85
		lbl.add_theme_stylebox_override("panel", style)
		add_child(lbl)
		overlay = lbl
		lbl.set_meta("dot_frame", 0)
		_spinner_tween = create_tween().set_loops()
		_spinner_tween.tween_callback(func() -> void:
			if is_instance_valid(lbl) and lbl.visible:
				var frame: int = lbl.get_meta("dot_frame", 0)
				frame = (frame + 1) % 4
				lbl.set_meta("dot_frame", frame)
				lbl.text = "Generating puzzle" + ".".repeat(frame)
		).set_delay(0.4)
	overlay.visible = visible
	if not visible and _spinner_tween != null:
		_spinner_tween.kill()
		_spinner_tween = null


# --- Session ceremony hooks ---

func _should_tick_timer() -> bool:
	return not logic.is_completed and not is_paused


func _get_start_crash_params() -> Dictionary:
	return {"width": grid_width, "height": grid_height, "mode": mode}


func _get_resume_crash_params(saved_data: Dictionary) -> Dictionary:
	return {"width": saved_data.get("width", 10), "height": saved_data.get("height", 10), "mode": saved_data.get("mode", 0)}


func _get_initial_state() -> Dictionary:
	var serialized := logic.serialize()
	return {
		"width": grid_width,
		"height": grid_height,
		"mode": mode,
		"anchors": serialized.get("anchors", {}),
	}


func _get_settings_snapshot() -> Dictionary:
	return {"show_timer": PlatformSettings.show_timer}


func _setup_game(saved_data: Dictionary) -> void:
	if saved_data.is_empty():
		# New game — use pre-generated puzzle data produced by _run_generation().
		var gen_seed := int(_pending_shikaku_data.get("random_seed", random_seed))
		random_seed = gen_seed
		logic.init_from_generated(_pending_shikaku_data, gen_seed, mode)
		_pending_shikaku_data = {}
	else:
		logic.init_from_save(saved_data)
	grid_width = logic.grid_width
	grid_height = logic.grid_height
	mode = logic.mode
	random_seed = logic.random_seed
	board.setup(grid_width, grid_height, logic.anchors)
	for rect in logic.placed_rects:
		board.add_rect(rect)
	_refresh_error_display()
	size_label.text = SIZE_NAMES.get(grid_width, "%dx%d" % [grid_width, grid_height])
	_update_button_states()


func _increment_stats() -> void:
	_stats.increment_counter("shikaku", "games_started")
	var size_key := "started_s%d" % grid_width
	if mode == ShikakuLogic.RULE_SET_SHAPES:
		_stats.increment_counter("shikaku", "started_shapes_s%d" % grid_width)
	else:
		_stats.increment_counter("shikaku", size_key)


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
	_refresh_error_display()
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
	_refresh_error_display()
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
	_refresh_error_display()
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
	_refresh_error_display()
	_update_button_states()
	_save_current_state()


func _on_hint() -> void:
	if not logic.can_hint():
		return
	var result: ShikakuLogic.HintResult = logic.use_hint()
	if result.rect.is_empty():
		return
	_crash.register_user_action("shikaku_hint_used")
	# Remove any wrong placements that were cleared to unblock the hint rect.
	for removed in result.removed_rects:
		var removed_rect: Rect2i = _rect_from_dict(removed)
		for i in range(board.placed_rects.size() - 1, -1, -1):
			if board.placed_rects[i] == removed_rect:
				board.remove_rect(i)
				break
	var hint_rect: Rect2i = _rect_from_dict(result.rect)
	_recorder.record_input(elapsed_time, "rectangle_placed", {
		"x": hint_rect.position.x,
		"y": hint_rect.position.y,
		"w": hint_rect.size.x,
		"h": hint_rect.size.y,
	})
	board.add_rect(hint_rect)
	_refresh_error_display()
	_sound.play_place()
	_haptic.vibrate_medium()
	_update_button_states()
	if result.game_won:
		_handle_win()
	_save_current_state()


## Refresh the board's error highlighting to show wrong (non-solution) placements.
func _refresh_error_display() -> void:
	board.refresh_error_state(logic.get_wrong_placed_rects())


func _on_pause() -> void:
	is_paused = not is_paused
	pause_button.text = "Resume" if is_paused else "Pause"
	board.visible = not is_paused
	_crash.register_user_action("shikaku_pause_toggled", {"is_paused": is_paused})


func _on_back() -> void:
	var completed: Dictionary = _recorder.finish_session("abandoned", logic.placed_rects.size(), elapsed_time, {
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
	# Leaderboard: emit with mode-aware key.
	# Standard: use raw size string (e.g. "5"); Shapes: use "shapes_5".
	var lb_key: String
	if mode == ShikakuLogic.RULE_SET_SHAPES:
		lb_key = "shapes_%d" % grid_width
	else:
		lb_key = str(grid_width)
	GameEvents.leaderboard_score_ready.emit("shikaku", lb_key, elapsed_time)
	var completed: Dictionary = _recorder.finish_session("win", logic.placed_rects.size(), elapsed_time, {
		"width": grid_width,
		"height": grid_height,
		"mode": mode,
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
		"mode": mode,
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
	var mode_prefix := "shapes_" if mode == ShikakuLogic.RULE_SET_SHAPES else ""
	var best_ms: int = _stats.get_counter("shikaku", "best_%ss%d" % [mode_prefix, grid_width])
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
			var success: bool = _storage.bookmark_latest_replay()
			if success:
				dialog.dialog_text += "\n\n✓ Replay bookmarked!"
			else:
				dialog.dialog_text += "\n\n✗ No replay to bookmark"
	)


func _restart_same_game() -> void:
	var w := grid_width
	var h := grid_height
	var m := mode
	SceneTransition.navigate(Scenes.SHIKAKU_GAME, func(game_scene: Node) -> void:
		game_scene.start_new_game(w, h, m)
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
	var mode_prefix := "shapes_" if mode == ShikakuLogic.RULE_SET_SHAPES else ""
	_stats.record("shikaku", {
		"type": "completion",
		"grid_size": grid_size,
		"time": time,
		"mode": mode,
	})
	_stats.increment_counter("shikaku", "completed_%ss%d" % [mode_prefix, grid_size])
	# Best time (stored as ms int)
	var best_key := "best_%ss%d" % [mode_prefix, grid_size]
	var best_ms: int = _stats.get_counter("shikaku", best_key)
	var time_ms := int(time * 1000)
	if best_ms == 0 or time_ms < best_ms:
		_stats.set_counter("shikaku", best_key, time_ms)
	# Streak
	var streak: int = _stats.get_counter("shikaku", "current_streak") + 1
	_stats.set_counter("shikaku", "current_streak", streak)
	var best_streak: int = _stats.get_counter("shikaku", "best_streak")
	if streak > best_streak:
		_stats.set_counter("shikaku", "best_streak", streak)
