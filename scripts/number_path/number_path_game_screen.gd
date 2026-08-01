extends GameScreen

## Number Path game screen — board, timer, controls, generation background thread.

const TIER_NAMES := {
	NumberPathLogic.TIER_EASY: "Easy (5×5)",
	NumberPathLogic.TIER_MEDIUM: "Medium (6×6)",
	NumberPathLogic.TIER_HARD: "Hard (7×7)",
	NumberPathLogic.TIER_EXPERT: "Expert (8×8)",
}

const TIER_KEYS := {
	NumberPathLogic.TIER_EASY: "easy",
	NumberPathLogic.TIER_MEDIUM: "medium",
	NumberPathLogic.TIER_HARD: "hard",
	NumberPathLogic.TIER_EXPERT: "expert",
}

const _SCENE_MENU := "res://scenes/number_path_menu.tscn"
const _SCENE_GAME := "res://scenes/number_path_game.tscn"

# Game state
var _tier: int = NumberPathLogic.TIER_EASY
var is_paused: bool = false
var logic: NumberPathLogic = NumberPathLogic.new()

# Generation thread (new games only)
var _gen_thread: Thread = null
var _gen_mutex: Mutex = Mutex.new()
var _gen_cancelled: bool = false
var _pending_gen_data: Dictionary = {}

# Node refs
@onready var board: NumberPathBoard = %NumberPathBoard
@onready var tier_label: Label = %TierLabel
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var hint_button: Button = %HintButton
@onready var pause_button: Button = %PauseButton
@onready var back_button: Button = %BackButton
@onready var spinner: Control = %Spinner


# --- GameScreen overrides ---

func _get_game_id() -> String:
	return "number_path"


func _get_scene_path() -> String:
	return _SCENE_GAME


func _get_save_adapter() -> GameSaveAdapter:
	return NumberPathSaveAdapter.new()


func _is_initialized() -> bool:
	return not logic.checkpoints.is_empty()


func _is_completed() -> bool:
	return logic.is_completed


func _serialize_state() -> Dictionary:
	var data := logic.serialize()
	data["elapsed_time"] = elapsed_time
	data["replay_id"] = replay_id
	return data


func _deserialize_state(data: Dictionary) -> void:
	resume_game(data)


func _get_crash_state() -> Dictionary:
	return {
		"game": "number_path",
		"tier": _tier,
		"elapsed_time": elapsed_time,
		"is_completed": logic.is_completed,
		"is_paused": is_paused,
		"hints_used": logic.hints_used,
		"path_length": logic.current_path.size(),
	}


func _apply_game_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)


func _on_game_screen_ready() -> void:
	board.path_drag_started.connect(_on_drag_started)
	board.path_cell_entered.connect(_on_cell_entered)
	board.path_drag_released.connect(_on_drag_released)
	undo_button.pressed.connect(_on_undo)
	redo_button.pressed.connect(_on_redo)
	hint_button.pressed.connect(_on_hint)
	pause_button.pressed.connect(_on_pause)
	back_button.pressed.connect(_on_back)
	_update_button_states()
	_set_spinner_visible(false)


# --- Launch / Resume ---

func start_new_game(tier: int) -> void:
	_tier = tier
	# Generation runs in a background thread.
	# Show spinner and start thread; begin_session() is called from _on_generation_done().
	_set_gen_cancelled(false)
	_pending_gen_data = {}
	_set_spinner_visible(true)
	_gen_thread = Thread.new()
	_gen_thread.start(_run_generation)


func launch(params: LaunchParams) -> void:
	start_new_game(params.option_value)


func resume_game(data: Dictionary) -> void:
	_tier = int(data.get("tier", NumberPathLogic.TIER_EASY))
	begin_session(data)


# --- Generation thread ---

func _run_generation() -> void:
	var tier_val := _tier
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var seed_val := int(Time.get_ticks_usec()) ^ rng.randi()
	var result := NumberPathGenerator.generate(tier_val, seed_val,
			func() -> bool: return _get_gen_cancelled())
	if not result.is_empty():
		result["_used_seed"] = seed_val
	_pending_gen_data = result
	if not _get_gen_cancelled():
		call_deferred("_on_generation_done")


func _on_generation_done() -> void:
	if _get_gen_cancelled():
		return
	if _gen_thread:
		_gen_thread.wait_to_finish()
		_gen_thread = null
	_set_spinner_visible(false)
	if _pending_gen_data.is_empty() or not _pending_gen_data.has("width"):
		push_error("NumberPathGameScreen: generation failed")
		_suppress_auto_resume = true
		_pending_gen_data = {}
		return
	begin_session()


# --- Session ceremony hooks ---

func _setup_game(saved_data: Dictionary) -> void:
	if not saved_data.is_empty():
		# Resuming from save
		logic.init_from_save(saved_data)
		_tier = logic.tier
		if random_seed == 0:
			random_seed = logic.random_seed
	else:
		# New game from generation thread data
		var data := _pending_gen_data
		_pending_gen_data = {}
		if data.is_empty() or not data.has("width"):
			push_error("NumberPathGameScreen: _setup_game called without generation data")
			return
		var size: int = data.get("width", 5)
		var used_seed := int(data.get("_used_seed", random_seed))
		logic.init_new_game(size, size, _tier, used_seed, data)
		# Use the actual generation seed for the replay session
		random_seed = used_seed

	board.setup(logic.grid_width, logic.grid_height, logic.checkpoints, logic.barriers)
	board.set_path(logic.current_path)
	tier_label.text = TIER_NAMES.get(_tier, "")
	_update_button_states()


func _should_tick_timer() -> bool:
	return not logic.is_completed and not is_paused and not logic.checkpoints.is_empty()


func _get_start_crash_params() -> Dictionary:
	return {"tier": _tier}


func _get_resume_crash_params(saved_data: Dictionary) -> Dictionary:
	return {"tier": saved_data.get("tier", _tier)}


func _get_initial_state() -> Dictionary:
	var s := logic.serialize()
	return {
		"width": logic.grid_width,
		"height": logic.grid_height,
		"tier": logic.tier,
		"checkpoints": s.get("checkpoints", []),
		"barriers": s.get("barriers", []),
		"initial_path": s.get("current_path", []),
	}


func _get_settings_snapshot() -> Dictionary:
	return {"show_timer": PlatformSettings.show_timer}


func _increment_stats() -> void:
	_stats.increment_counter("number_path", "games_started")
	_stats.increment_counter("number_path", "started_%s" % TIER_KEYS.get(_tier, "easy"))


func _get_analytics_params() -> Dictionary:
	return {"game": "number_path", "tier": _tier}


func _get_difficulty() -> int:
	return _tier


# --- Input handlers ---

func _on_drag_started(_cell: Vector2i) -> void:
	pass


func _on_cell_entered(cell: Vector2i) -> void:
	if logic.is_completed or is_paused or logic.checkpoints.is_empty():
		return

	var head := logic.get_head()

	# Backward truncation: cell already in path (not head)
	var path_idx := logic.get_path_index(cell)
	if path_idx >= 0 and cell != head:
		var trunc := logic.try_truncate(cell)
		if trunc.truncated:
			board.set_path(logic.current_path)
			_recorder.record_input(elapsed_time, "path_truncated", {"length": trunc.new_length})
			_update_button_states()
			_save_current_state()
		return

	# Forward extension
	var extend := logic.try_extend(cell)
	if extend.accepted:
		board.set_path(logic.current_path)
		_recorder.record_input(elapsed_time, "path_extended", {"x": cell.x, "y": cell.y})
		_haptic.vibrate_light()
		_update_button_states()
		if extend.game_won:
			_handle_win()
		else:
			_save_current_state()
	elif extend.contradiction:
		board.flash_contradiction([cell])


func _on_drag_released() -> void:
	pass


# --- Controls ---

func _on_undo() -> void:
	if logic.is_completed:
		return
	var result := logic.undo()
	if not result.performed:
		return
	board.set_path(logic.current_path)
	var path_arr: Array[Dictionary] = []
	for cell in logic.current_path:
		path_arr.append({"x": cell.x, "y": cell.y})
	_recorder.record_input(elapsed_time, "undo_applied", {
		"length": logic.current_path.size(),
		"path": path_arr,
	})
	_update_button_states()
	_save_current_state()


func _on_redo() -> void:
	if logic.is_completed:
		return
	var result := logic.redo()
	if not result.performed:
		return
	board.set_path(logic.current_path)
	var path_arr: Array[Dictionary] = []
	for cell in logic.current_path:
		path_arr.append({"x": cell.x, "y": cell.y})
	_recorder.record_input(elapsed_time, "redo_applied", {
		"length": logic.current_path.size(),
		"path": path_arr,
	})
	_update_button_states()
	_save_current_state()


func _on_hint() -> void:
	if not logic.can_hint():
		return
	var result := logic.use_hint()
	if result.contradiction_highlighted:
		board.flash_contradiction(logic.current_path.duplicate())
		_recorder.record_input(elapsed_time, "hint_applied", {"contradiction": true})
		return
	if not result.valid:
		return
	board.set_path(logic.current_path)
	board.flash_hint(result.cell)
	_recorder.record_input(elapsed_time, "hint_applied", {
		"x": result.cell.x,
		"y": result.cell.y,
	})
	_crash.register_user_action("number_path_hint_used")
	_haptic.vibrate_medium()
	_update_button_states()
	if result.game_won:
		_handle_win()
	else:
		_save_current_state()


func _on_pause() -> void:
	is_paused = not is_paused
	pause_button.text = "Resume" if is_paused else "Pause"
	board.visible = not is_paused
	_crash.register_user_action("number_path_pause_toggled", {"is_paused": is_paused})


func _on_back() -> void:
	_cancel_generation()
	var completed := _recorder.finish_session("abandoned", logic.current_path.size(), elapsed_time, {
		"tier": _tier,
	})
	_storage.save_replay(completed)
	_crash.register_user_action("number_path_back_to_menu")
	if not logic.is_completed:
		_stats.set_counter("general", "current_win_streak", 0)
		_achievements.check_stats()
	_save_current_state()
	SceneTransition.navigate(_SCENE_MENU)


# --- Win ---

func _handle_win() -> void:
	GameEvents.game_ended.emit("number_path", "win", elapsed_time)
	var tier_key: String = TIER_KEYS.get(_tier, "easy")
	GameEvents.leaderboard_score_ready.emit("number_path", tier_key, elapsed_time)
	_recorder.record_input(elapsed_time, "game_completed", {})
	var completed := _recorder.finish_session("win", logic.current_path.size(), elapsed_time, {
		"tier": _tier,
		"hints_used": logic.hints_used,
	})
	_storage.save_replay(completed)
	var is_new_best := _is_new_best_time()
	_record_completion(_tier, elapsed_time)
	_stats.increment_counter("general", "games_won")
	_stats.increment_counter("general", "current_win_streak")
	_stats.increment_counter("number_path", "games_won")
	_achievements.check_stats()
	_analytics.log_event("game_over", {
		"game": "number_path",
		"won": true,
		"tier": _tier,
		"elapsed_time": elapsed_time,
		"hints_used": logic.hints_used,
	})
	clear_save()
	_sound.play_win()
	_haptic.vibrate_success()
	if is_new_best:
		_show_new_best_indicator()
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
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(_show_win_dialog)


func _is_new_best_time() -> bool:
	var tier_key: String = TIER_KEYS.get(_tier, "easy")
	var best_ms: int = _stats.get_counter("number_path", "best_%s" % tier_key)
	return best_ms == 0 or elapsed_time < float(best_ms) / 1000.0


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
	var tier_name: String = TIER_NAMES.get(_tier, "")
	var dialog := AcceptDialog.new()
	dialog.title = "Congratulations!"
	dialog.dialog_text = "You solved the %s puzzle\nin %s!" % [tier_name, TimeFormat.format_time(elapsed_time, true)]
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
			SceneTransition.navigate(_SCENE_MENU)
		elif action == "bookmark":
			var success := _storage.bookmark_latest_replay()
			dialog.dialog_text += "\n\n%s" % ("✓ Replay bookmarked!" if success else "✗ No replay to bookmark")
	)


func _restart_same_game() -> void:
	var t := _tier
	SceneTransition.navigate(_SCENE_GAME, func(scene: Node) -> void:
		scene.start_new_game(t)
	)


# --- Helpers ---

func _update_button_states() -> void:
	undo_button.disabled = not logic.can_undo()
	redo_button.disabled = not logic.can_redo()
	hint_button.disabled = not logic.can_hint()


func _set_spinner_visible(vis: bool) -> void:
	if spinner:
		spinner.visible = vis


func _record_completion(t: int, time: float) -> void:
	var tier_key: String = TIER_KEYS.get(t, "easy")
	_stats.record("number_path", {
		"type": "completion",
		"tier": t,
		"time": time,
	})
	_stats.increment_counter("number_path", "completed_%s" % tier_key)
	var best_ms: int = _stats.get_counter("number_path", "best_%s" % tier_key)
	var time_ms := int(time * 1000)
	if best_ms == 0 or time_ms < best_ms:
		_stats.set_counter("number_path", "best_%s" % tier_key, time_ms)
	var streak: int = _stats.get_counter("number_path", "current_streak") + 1
	_stats.set_counter("number_path", "current_streak", streak)
	var best_streak: int = _stats.get_counter("number_path", "best_streak")
	if streak > best_streak:
		_stats.set_counter("number_path", "best_streak", streak)


func _cancel_generation() -> void:
	_set_gen_cancelled(true)
	if _gen_thread:
		_gen_thread.wait_to_finish()
		_gen_thread = null


func _set_gen_cancelled(val: bool) -> void:
	_gen_mutex.lock()
	_gen_cancelled = val
	_gen_mutex.unlock()


func _get_gen_cancelled() -> bool:
	_gen_mutex.lock()
	var val := _gen_cancelled
	_gen_mutex.unlock()
	return val


func _exit_tree() -> void:
	_cancel_generation()
	super._exit_tree()
