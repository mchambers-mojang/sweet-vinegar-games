extends GameScreen

## Eclipse Grid game screen.
##
## Runs a background Thread for puzzle generation (EclipseGridGenerator can be
## slow for size 10).  Cancellation is polled at each generation checkpoint so
## teardown always joins promptly.

# Scene paths kept local until Eclipse Grid is registered in the shared collection.
const SCENE_GAME := "res://scenes/eclipse_grid_game.tscn"
const SCENE_MENU := "res://scenes/eclipse_grid_menu.tscn"

const SIZE_LABELS: Dictionary = {4: "Easy 4×4", 6: "Medium 6×6", 8: "Hard 8×8", 10: "Expert 10×10"}

# Game state
var grid_size: int = 4
var logic: EclipseGridLogic = EclipseGridLogic.new()
var is_paused: bool = false

# Background generation
var _gen_thread: Thread = null
var _gen_mutex: Mutex = Mutex.new()
var _gen_cancelled: bool = false
var _pending_data: Dictionary = {}
var _spinner_tween: Tween = null

# Node references
@onready var board: EclipseGridBoard = %EclipseGridBoard
@onready var size_label: Label = %SizeLabel
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var hint_button: Button = %HintButton
@onready var assist_button: Button = %AssistButton
@onready var pause_button: Button = %PauseButton
@onready var back_button: Button = %BackButton
@onready var settings_button: Button = %SettingsButton


# ---------------------------------------------------------------------------
# GameScreen virtual overrides
# ---------------------------------------------------------------------------

func _get_game_id() -> String:
	return "eclipse_grid"


func _get_scene_path() -> String:
	return SCENE_GAME


func _get_save_adapter() -> GameSaveAdapter:
	return EclipseGridSaveAdapter.new()


func _is_initialized() -> bool:
	return logic.size > 0


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
		"game": "eclipse_grid",
		"size": grid_size,
		"elapsed_time": elapsed_time,
		"is_completed": logic.is_completed,
		"is_paused": is_paused,
		"hints_used": logic.hints_used,
	}


func _apply_game_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)


func _on_game_screen_ready() -> void:
	board.cell_tapped.connect(_on_cell_tapped)
	undo_button.pressed.connect(_on_undo)
	redo_button.pressed.connect(_on_redo)
	hint_button.pressed.connect(_on_hint)
	assist_button.pressed.connect(_on_assist_toggle)
	pause_button.pressed.connect(_on_pause)
	back_button.pressed.connect(_on_back)
	_update_button_states()


func _should_tick_timer() -> bool:
	return not logic.is_completed and not is_paused


func _get_start_crash_params() -> Dictionary:
	return {"size": grid_size}


func _get_resume_crash_params(saved_data: Dictionary) -> Dictionary:
	return {"size": saved_data.get("size", 4)}


func _get_initial_state() -> Dictionary:
	return {
		"size": grid_size,
		"givens": logic.serialize().get("givens", []),
		"h_relations": logic.serialize().get("h_relations", {}),
		"v_relations": logic.serialize().get("v_relations", {}),
	}


func _get_settings_snapshot() -> Dictionary:
	return {"show_timer": PlatformSettings.show_timer}


func _setup_game(saved_data: Dictionary) -> void:
	if saved_data.is_empty():
		# Restore the generation seed: begin_session() overwrites random_seed with
		# _create_session_seed() before calling _setup_game(), so we must recover
		# the actual gen_seed from _pending_data here.
		var gen_seed: int = int(_pending_data.get("random_seed", 0))
		if gen_seed != 0:
			random_seed = gen_seed
		logic.init_new_game(grid_size, random_seed, _pending_data)
		_pending_data = {}
	else:
		logic.init_from_save(saved_data)
	grid_size = logic.size
	random_seed = logic.random_seed
	board.setup(logic.size, logic.givens, logic.cells, logic.h_relations, logic.v_relations)
	_refresh_board()
	size_label.text = SIZE_LABELS.get(grid_size, "%d×%d" % [grid_size, grid_size])
	_update_button_states()


func _increment_stats() -> void:
	_stats.increment_counter("eclipse_grid", "games_started")
	_stats.increment_counter("eclipse_grid", "started_s%d" % grid_size)


func _get_analytics_params() -> Dictionary:
	return {"game": "eclipse_grid", "size": grid_size}


func _exit_tree() -> void:
	_cancel_generation()
	super._exit_tree()


# ---------------------------------------------------------------------------
# Launch / Resume
# ---------------------------------------------------------------------------

func launch(params: LaunchParams) -> void:
	grid_size = params.option_value
	if grid_size not in [4, 6, 8, 10]:
		grid_size = 4
	# Suppress the deferred _try_auto_resume() that fires after _ready().
	# Without this, an existing save can resume while generation runs in the
	# background and then be overwritten when begin_session() is called from
	# _on_generation_complete().
	_suppress_auto_resume = true
	_gen_cancelled = false
	_show_spinner(true)
	_gen_thread = Thread.new()
	_gen_thread.start(_run_generation)


func start_new_game(sz: int) -> void:
	grid_size = sz
	begin_session()


func resume_game(data: Dictionary) -> void:
	grid_size = int(data.get("size", 4))
	begin_session(data)


# ---------------------------------------------------------------------------
# Background generation
# ---------------------------------------------------------------------------

func _run_generation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var gen_seed := int(Time.get_ticks_usec()) ^ rng.randi()
	var result: Dictionary = EclipseGridGenerator.generate(
			grid_size, gen_seed, func() -> bool: return _get_gen_cancelled())
	_pending_data = result
	_pending_data["random_seed"] = gen_seed
	if not _get_gen_cancelled():
		call_deferred("_on_generation_complete")


func _on_generation_complete() -> void:
	if _get_gen_cancelled():
		return
	if _gen_thread != null:
		_gen_thread.wait_to_finish()
		_gen_thread = null
	_show_spinner(false)
	if _pending_data.is_empty() or not _pending_data.has("givens"):
		push_error("EclipseGridGameScreen: generation failed")
		_suppress_auto_resume = true
		return
	# random_seed is restored inside _setup_game() from _pending_data["random_seed"]
	begin_session()


func _cancel_generation() -> void:
	_set_gen_cancelled()
	if _gen_thread != null:
		_gen_thread.wait_to_finish()
		_gen_thread = null
	_show_spinner(false)


func _set_gen_cancelled() -> void:
	_gen_mutex.lock()
	_gen_cancelled = true
	_gen_mutex.unlock()


func _get_gen_cancelled() -> bool:
	_gen_mutex.lock()
	var val := _gen_cancelled
	_gen_mutex.unlock()
	return val


func _show_spinner(visible: bool) -> void:
	if _spinner_tween != null:
		_spinner_tween.kill()
		_spinner_tween = null
	if not size_label:
		return
	size_label.text = "Generating" if visible else ""
	if visible:
		size_label.set_meta("spinner_frame", 0)
		_spinner_tween = create_tween().set_loops()
		_spinner_tween.tween_callback(func() -> void:
			if is_instance_valid(size_label):
				var frame: int = size_label.get_meta("spinner_frame", 0)
				frame = (frame + 1) % 4
				size_label.set_meta("spinner_frame", frame)
				size_label.text = "Generating" + ".".repeat(frame)
		).set_delay(0.4)


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------

func _on_cell_tapped(index: int) -> void:
	if logic.is_completed or is_paused:
		return
	var result: EclipseGridLogic.SetGlyphResult = logic.cycle_cell(index)
	if result.new_value == result.old_value and not result.rejected:
		return
	if result.rejected:
		# Strict mode feedback
		_sound.play_place() if _sound.has_method("play_place") else _sound.call("play_error") if _sound.has_method("play_error") else null
		_haptic.vibrate_light()
		return
	_recorder.record_input(elapsed_time, "glyph_changed", {
		"index": index,
		"old_value": result.old_value,
		"new_value": result.new_value,
	})
	_refresh_board()
	_haptic.vibrate_light()
	_update_button_states()
	if result.game_won:
		_handle_win()
	_save_current_state()


func _on_undo() -> void:
	if logic.is_completed:
		return
	var result: EclipseGridLogic.UndoRedoResult = logic.undo()
	if result.index < 0:
		return
	_recorder.record_input(elapsed_time, "glyph_changed", {
		"index": result.index,
		"old_value": result.old_value,
		"new_value": result.new_value,
	})
	_refresh_board()
	_update_button_states()
	_save_current_state()


func _on_redo() -> void:
	if logic.is_completed:
		return
	var result: EclipseGridLogic.UndoRedoResult = logic.redo()
	if result.index < 0:
		return
	_recorder.record_input(elapsed_time, "glyph_changed", {
		"index": result.index,
		"old_value": result.old_value,
		"new_value": result.new_value,
	})
	_refresh_board()
	_update_button_states()
	_save_current_state()


func _on_hint() -> void:
	if logic.is_completed:
		return
	var result: EclipseGridLogic.HintResult = logic.use_hint()
	if not result.had_step:
		return
	_crash.register_user_action("eclipse_grid_hint_used")
	_recorder.record_input(elapsed_time, "hint_applied", {"index": result.index, "value": result.value})
	_refresh_board()
	_haptic.vibrate_medium()
	_update_button_states()
	if result.game_won:
		_handle_win()
	_save_current_state()


func _on_assist_toggle() -> void:
	logic.assistance_mode = (logic.assistance_mode + 1) % 3
	_refresh_board()
	_update_button_states()
	_save_current_state()


func _on_pause() -> void:
	is_paused = not is_paused
	pause_button.text = "Resume" if is_paused else "Pause"
	board.visible = not is_paused


func _on_back() -> void:
	_cancel_generation()
	if _is_initialized() and not logic.is_completed:
		_stats.set_counter("general", "current_win_streak", 0)
	if _is_initialized():
		_save_current_state()
	SceneTransition.navigate(SCENE_MENU)


# ---------------------------------------------------------------------------
# Win handling
# ---------------------------------------------------------------------------

func _handle_win() -> void:
	GameEvents.game_ended.emit("eclipse_grid", "win", elapsed_time)
	if grid_size in [4, 6, 8, 10]:
		GameEvents.leaderboard_score_ready.emit("eclipse_grid", str(grid_size), elapsed_time)
	_recorder.record_input(elapsed_time, "game_completed", {"size": grid_size})
	var completed: Dictionary = _recorder.finish_session("win", logic.hints_used, elapsed_time, {
		"size": grid_size,
		"hints_used": logic.hints_used,
	})
	_storage.save_replay(completed)
	var is_new_best := _is_new_best_time()
	_record_completion(grid_size, elapsed_time)
	_stats.increment_counter("general", "games_won")
	_stats.increment_counter("general", "current_win_streak")
	_stats.increment_counter("eclipse_grid", "games_won")
	_achievements.check_stats()
	_analytics.log_event("game_over", {
		"game": "eclipse_grid",
		"won": true,
		"size": grid_size,
		"elapsed_time": elapsed_time,
		"hints_used": logic.hints_used,
	})
	clear_save()
	if _sound.has_method("play_win"):
		_sound.play_win()
	_haptic.vibrate_success()
	if is_new_best:
		_show_new_best()
	if AppTheme.is_neon:
		var cs := board._get_cell_size()
		var orig := board._get_grid_origin()
		var center := orig + Vector2(cs * grid_size * 0.5, cs * grid_size * 0.5)
		EffectFactory.neon_ring(board, center, Color(0.0, 2.0, 1.5), cs * 6.0, 0.5, 1.2)
		AppTheme.screen_shake(6.0, 0.2)
	board.flash_all(Color(1.2, 1.1, 0.8), 0.4)
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(_show_win_dialog)


func _is_new_best_time() -> bool:
	var best_ms: int = _stats.get_counter("eclipse_grid", "best_s%d" % grid_size)
	return best_ms == 0 or elapsed_time < (float(best_ms) / 1000.0)


func _show_new_best() -> void:
	var cs := board._get_cell_size()
	var orig := board._get_grid_origin()
	var center := orig + Vector2(cs * grid_size * 0.5, cs * grid_size * 0.5)
	var color := Color(0.0, 2.0, 1.5) if AppTheme.is_neon else Color(0.2, 0.75, 1.0)
	ComboLabel.create(board, center, "NEW BEST!", color)


func _show_win_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Puzzle Solved!"
	dialog.dialog_text = "You solved the %s puzzle\nin %s!" % [
		SIZE_LABELS.get(grid_size, ""), TimeFormat.format_time(elapsed_time, true)]
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
			SceneTransition.navigate(SCENE_MENU)
		elif action == "bookmark":
			var ok: bool = _storage.bookmark_latest_replay()
			dialog.dialog_text += "\n\n%s" % ("✓ Replay bookmarked!" if ok else "✗ No replay to bookmark")
	)


func _restart_same_game() -> void:
	var sz := grid_size
	SceneTransition.navigate(SCENE_GAME, func(scene: Node) -> void:
		var p := LaunchParams.new()
		p.option_value = sz
		scene.launch(p)
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _refresh_board() -> void:
	if grid_size <= 0 or logic.size == 0:
		return
	board.update_cells(logic.cells)
	if logic.assistance_mode == EclipseGridLogic.ASSIST_FREE:
		board.update_errors(logic.get_error_cells())
		board.update_error_relations(logic.get_broken_relations())
	else:
		board.update_errors([])
		board.update_error_relations([])


func _update_button_states() -> void:
	undo_button.disabled = not logic.can_undo()
	redo_button.disabled = not logic.can_redo()
	hint_button.disabled = logic.is_completed
	var assist_labels := ["Assist: Off", "Assist: Free", "Assist: Strict"]
	assist_button.text = assist_labels[logic.assistance_mode]


func _record_completion(size: int, t: float) -> void:
	_stats.record("eclipse_grid", {"type": "completion", "size": size, "time": t})
	_stats.increment_counter("eclipse_grid", "completed_s%d" % size)
	var best_ms: int = _stats.get_counter("eclipse_grid", "best_s%d" % size)
	var t_ms := int(t * 1000)
	if best_ms == 0 or t_ms < best_ms:
		_stats.set_counter("eclipse_grid", "best_s%d" % size, t_ms)
	var streak: int = _stats.get_counter("eclipse_grid", "current_streak") + 1
	_stats.set_counter("eclipse_grid", "current_streak", streak)
	var best_streak: int = _stats.get_counter("eclipse_grid", "best_streak")
	if streak > best_streak:
		_stats.set_counter("eclipse_grid", "best_streak", streak)
