extends GameScreen
class_name CrownGridGameScreen

## Crown Grid game screen — board, timer, controls, tier-based difficulty.

const TIER_NAMES := {
	CrownGridGenerator.TIER_EASY: "Easy",
	CrownGridGenerator.TIER_MEDIUM: "Medium",
	CrownGridGenerator.TIER_HARD: "Hard",
	CrownGridGenerator.TIER_EXPERT: "Expert",
}

const CROWN_GRID_MENU_SCENE := "res://scenes/crown_grid_menu.tscn"
const CROWN_GRID_GAME_SCENE := "res://scenes/crown_grid_game.tscn"

# Launch params
var _tier: int = CrownGridGenerator.TIER_EASY
var _tier_size: int = 6
var _is_paused: bool = false

# Logic
var logic: CrownGridLogic = CrownGridLogic.new()

# Generation thread
var _gen_thread: Thread = null
var _gen_pending_result: Dictionary = {}
var _gen_mutex: Mutex = Mutex.new()
var _gen_cancelled: bool = false
## Seed created just before launching the generation thread; forwarded to
## begin_session() via _setup_game() so replay headers record the correct seed.
var _pending_gen_seed: int = 0

# Node refs
@onready var board: CrownGridBoard = %CrownGridBoard
@onready var tier_label: Label = %TierLabel
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var hint_button: Button = %HintButton
@onready var pause_button: Button = %PauseButton
@onready var back_button: Button = %BackButton
@onready var settings_button: Button = %SettingsButton
@onready var spinner: Control = %Spinner


# ---------------------------------------------------------------------------
# GameScreen overrides
# ---------------------------------------------------------------------------

func _get_game_id() -> String:
	return "crown_grid"


func _get_scene_path() -> String:
	return CROWN_GRID_GAME_SCENE


func _get_save_adapter() -> GameSaveAdapter:
	return CrownGridSaveAdapter.new()


func _is_initialized() -> bool:
	return logic.size > 0 and not logic.regions.is_empty()


func _is_completed() -> bool:
	return logic.is_completed


func _serialize_state() -> Dictionary:
	var data := logic.serialize()
	data["elapsed_time"] = elapsed_time
	data["tier"] = _tier
	data["replay_id"] = replay_id
	data["random_seed"] = random_seed
	return data


func _deserialize_state(data: Dictionary) -> void:
	resume_game(data)


func _get_crash_state() -> Dictionary:
	return {
		"game": "crown_grid",
		"tier": _tier,
		"size": _tier_size,
		"elapsed_time": elapsed_time,
		"is_completed": logic.is_completed,
		"is_paused": _is_paused,
		"hints_used": logic.hints_used,
	}


func _apply_game_theme() -> void:
	_apply_panel_theme()


func _on_game_screen_ready() -> void:
	board.cell_tapped.connect(_on_cell_tapped)
	board.cells_dragged.connect(_on_cells_dragged)
	undo_button.pressed.connect(_on_undo)
	redo_button.pressed.connect(_on_redo)
	hint_button.pressed.connect(_on_hint)
	pause_button.pressed.connect(_on_pause)
	back_button.pressed.connect(_on_back)
	_update_button_states()


func start_new_game(tier: int) -> void:
	_suppress_auto_resume = true  # prevent deferred auto-resume while generating
	_tier = tier
	_tier_size = CrownGridGenerator.TIER_SIZES.get(tier, 6)
	_start_generation()  # begin_session() is deferred to _on_generation_done()


func launch(params: LaunchParams) -> void:
	start_new_game(params.option_value)


func resume_game(data: Dictionary) -> void:
	_tier = int(data.get("tier", CrownGridGenerator.TIER_EASY))
	_tier_size = CrownGridGenerator.TIER_SIZES.get(_tier, 6)
	begin_session(data)


# ---------------------------------------------------------------------------
# Session ceremony hooks
# ---------------------------------------------------------------------------

func _should_tick_timer() -> bool:
	return not logic.is_completed and not _is_paused and _is_initialized()


func _get_start_crash_params() -> Dictionary:
	return {"tier": _tier, "size": _tier_size}


func _get_resume_crash_params(saved_data: Dictionary) -> Dictionary:
	var t := int(saved_data.get("tier", CrownGridGenerator.TIER_EASY))
	return {"tier": t, "size": CrownGridGenerator.TIER_SIZES.get(t, 6)}


func _get_initial_state() -> Dictionary:
	return {
		"tier": _tier,
		"size": logic.size,
		"regions": Array(logic.regions),
		"solution": logic.solution.duplicate(),
	}


func _get_settings_snapshot() -> Dictionary:
	return {"show_timer": PlatformSettings.show_timer}


func _setup_game(saved_data: Dictionary) -> void:
	if saved_data.is_empty():
		# Logic was already initialised by _on_generation_done() before begin_session() was
		# called. Overwrite the throwaway seed that begin_session() created with the real
		# generation seed so replay headers record the correct value.
		random_seed = _pending_gen_seed
		_apply_board_from_logic()
	else:
		_load_from_save(saved_data)


func _increment_stats() -> void:
	_stats.increment_counter("crown_grid", "games_started")
	_stats.increment_counter("crown_grid", "started_t%d" % _tier)


func _get_analytics_params() -> Dictionary:
	return {"game": "crown_grid", "tier": _tier, "size": _tier_size}


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

func _start_generation() -> void:
	if spinner:
		spinner.visible = true
	board.visible = false
	_update_button_states()

	_set_gen_cancelled(false)
	_gen_pending_result = {}

	_pending_gen_seed = _create_session_seed()
	_gen_thread = Thread.new()
	_gen_thread.start(_run_generation.bind(_tier, _pending_gen_seed))


func _run_generation(tier: int, seed: int) -> void:
	var result := CrownGridGenerator.generate(tier, seed, func() -> bool: return _get_gen_cancelled())
	_gen_pending_result = result
	if not _get_gen_cancelled():
		call_deferred("_on_generation_done")


func _on_generation_done() -> void:
	if _gen_thread and _gen_thread.is_started():
		_gen_thread.wait_to_finish()
	_gen_thread = null

	if _get_gen_cancelled():
		return

	if spinner:
		spinner.visible = false

	var result := _gen_pending_result
	_gen_pending_result = {}

	if result.is_empty():
		_suppress_auto_resume = true
		push_warning("CrownGridGameScreen: generation failed for tier %d seed %d" % [_tier, _pending_gen_seed])
		_show_generation_failed_dialog()
		return

	var p_size: int = result["size"]
	var p_regions: PackedInt32Array = result["regions"]
	var p_solution: Array[int] = result["solution"]
	var p_auto_mark: bool = GameRulesRegistry.get_rule("crown_grid", "auto_mark", false)
	var p_assistance: int = CrownGridLogic.ASSISTANCE_FREE
	if GameRulesRegistry.get_rule("crown_grid", "strict_assistance", false):
		p_assistance = CrownGridLogic.ASSISTANCE_STRICT

	logic.init_new_game(p_size, p_regions, p_solution, p_auto_mark, p_assistance)
	_tier_size = p_size

	# Now run the full session ceremony: replay setup, stats, achievements, initial save.
	begin_session()


func _load_from_save(data: Dictionary) -> void:
	if spinner:
		spinner.visible = false
	logic.init_from_save(data)
	_tier = int(data.get("tier", _tier))
	_tier_size = logic.size
	_apply_board_from_logic()


func _apply_board_from_logic() -> void:
	board.setup(logic.size, logic.regions)
	board.set_cells(logic.cells)
	board.visible = true
	tier_label.text = TIER_NAMES.get(_tier, "")
	_update_button_states()
	# _save_current_state() is not called here — begin_session() / callers handle it.


func _show_generation_failed_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Generation Failed"
	dialog.dialog_text = "Could not generate a puzzle.\nPlease try again."
	dialog.ok_button_text = "Back to Menu"
	dialog.min_size = Vector2i(280, 0)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		SceneTransition.navigate(CROWN_GRID_MENU_SCENE)
	)


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------

func _on_cell_tapped(cell: Vector2i) -> void:
	if not _is_initialized() or logic.is_completed:
		return

	var result := logic.tap_cell(cell.x, cell.y)
	if not result.changed:
		if result.rejected:
			_sound.play_error()
			_haptic.vibrate_light()
		return

	board.set_cells(logic.cells)
	if logic.assistance_mode == CrownGridLogic.ASSISTANCE_FREE:
		board.set_violations(logic.get_violations())

	_recorder.record_input(elapsed_time, "cell_state_changed", {
		"col": cell.x,
		"row": cell.y,
		"new_state": result.new_state,
	})

	if result.new_state == CrownGridLogic.CELL_CROWN and not result.auto_marked.is_empty():
		var auto_cols: Array = []
		var auto_rows: Array = []
		for ac in result.auto_marked:
			auto_cols.append(ac.x)
			auto_rows.append(ac.y)
		_recorder.record_input(elapsed_time, "exclusions_painted", {"cols": auto_cols, "rows": auto_rows})

	if result.new_state == CrownGridLogic.CELL_CROWN:
		_sound.play_place()
		_haptic.vibrate_light()
		if AppTheme.is_neon:
			EffectFactory.neon_ring(board, board.get_cell_center(cell.x, cell.y),
					Color(1.5, 1.2, 0.0), board._get_cell_size() * 2.0, 0.2, 0.3)
	else:
		_haptic.vibrate_light()

	_update_button_states()
	if result.game_won:
		_handle_win()
	else:
		_save_current_state()


func _on_cells_dragged(paint_cells: Array) -> void:
	if not _is_initialized() or logic.is_completed:
		return

	var typed: Array[Vector2i] = []
	for c in paint_cells:
		typed.append(c as Vector2i)

	var result := logic.paint_excluded(typed)
	if result.changed_cells.is_empty():
		return

	board.set_cells(logic.cells)
	if logic.assistance_mode == CrownGridLogic.ASSISTANCE_FREE:
		board.set_violations(logic.get_violations())

	var cols: Array = []
	var rows: Array = []
	for c in result.changed_cells:
		cols.append(c.x)
		rows.append(c.y)
	_recorder.record_input(elapsed_time, "exclusions_painted", {"cols": cols, "rows": rows})
	_haptic.vibrate_light()
	_update_button_states()
	_save_current_state()


func _on_undo() -> void:
	if not logic.can_undo():
		return
	logic.undo()
	board.set_cells(logic.cells)
	if logic.assistance_mode == CrownGridLogic.ASSISTANCE_FREE:
		board.set_violations(logic.get_violations())
	_recorder.record_input(elapsed_time, "board_state_snapshot", {"cells": Array(logic.cells)})
	_update_button_states()
	_save_current_state()


func _on_redo() -> void:
	if not logic.can_redo():
		return
	logic.redo()
	board.set_cells(logic.cells)
	if logic.assistance_mode == CrownGridLogic.ASSISTANCE_FREE:
		board.set_violations(logic.get_violations())
	_recorder.record_input(elapsed_time, "board_state_snapshot", {"cells": Array(logic.cells)})
	_update_button_states()
	_save_current_state()


func _on_hint() -> void:
	var result := logic.use_hint()
	if not result.applied:
		return

	if board:
		board.set_cells(logic.cells)
		if logic.assistance_mode == CrownGridLogic.ASSISTANCE_FREE:
			board.set_violations(logic.get_violations())

	_crash.register_user_action("crown_grid_hint_used")

	if result.new_state == CrownGridLogic.CELL_CROWN and result.cell.x >= 0:
		_recorder.record_input(elapsed_time, "hint_applied", {
			"col": result.cell.x,
			"row": result.cell.y,
			"new_state": result.new_state,
		})
		if not result.auto_marked.is_empty():
			var auto_cols: Array = []
			var auto_rows: Array = []
			for ac in result.auto_marked:
				auto_cols.append(ac.x)
				auto_rows.append(ac.y)
			_recorder.record_input(elapsed_time, "exclusions_painted", {"cols": auto_cols, "rows": auto_rows})
		_sound.play_place()
		_haptic.vibrate_medium()
	else:
		var hint_cols: Array = []
		var hint_rows: Array = []
		for hc in result.changed_cells:
			hint_cols.append(hc.x)
			hint_rows.append(hc.y)
		_recorder.record_input(elapsed_time, "hint_applied", {
			"type": "exclusions",
			"cols": hint_cols,
			"rows": hint_rows,
		})

	_update_button_states()
	if result.game_won:
		_handle_win()
	else:
		_save_current_state()


func _on_pause() -> void:
	_is_paused = not _is_paused
	pause_button.text = "Resume" if _is_paused else "Pause"
	board.visible = not _is_paused
	_crash.register_user_action("crown_grid_pause_toggled", {"is_paused": _is_paused})


func _on_back() -> void:
	_cancel_generation()
	var completed: Dictionary = _recorder.finish_session("abandoned", 0, elapsed_time, {
		"tier": _tier,
		"size": _tier_size,
	})
	_storage.save_replay(completed)
	_crash.register_user_action("crown_grid_back_to_menu")
	if not logic.is_completed:
		_stats.set_counter("general", "current_win_streak", 0)
		_achievements.check_stats()
	_save_current_state()
	SceneTransition.navigate(CROWN_GRID_MENU_SCENE)


# ---------------------------------------------------------------------------
# Win handling
# ---------------------------------------------------------------------------

func _handle_win() -> void:
	GameEvents.game_ended.emit("crown_grid", "win", elapsed_time)

	_recorder.record_input(elapsed_time, "game_completed", {"tier": _tier})

	var completed: Dictionary = _recorder.finish_session("win", logic.hints_used, elapsed_time, {
		"tier": _tier,
		"size": _tier_size,
		"hints_used": logic.hints_used,
	})
	_storage.save_replay(completed)

	var is_new_best := _is_new_best_time()
	_record_crown_grid_completion(_tier, elapsed_time)
	_stats.increment_counter("general", "games_won")
	_stats.increment_counter("general", "current_win_streak")
	_stats.increment_counter("crown_grid", "games_won")
	_achievements.check_stats()
	_analytics.log_event("game_over", {
		"game": "crown_grid",
		"won": true,
		"tier": _tier,
		"size": _tier_size,
		"elapsed_time": elapsed_time,
		"hints_used": logic.hints_used,
	})

	clear_save()
	_sound.play_win()
	_haptic.vibrate_success()

	if is_new_best:
		_show_new_best_indicator()

	if AppTheme.is_neon:
		var cs := board._get_cell_size()
		var origin := board._get_grid_origin()
		var center := origin + Vector2(cs * logic.size * 0.5, cs * logic.size * 0.5)
		EffectFactory.neon_ring(board, center, Color(1.5, 1.2, 0.0), cs * 7.0, 0.5, 1.2)
		AppTheme.screen_shake(6.0, 0.2)

	board.flash_all(Color(1.2, 1.1, 0.8), 0.4)
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(_show_win_dialog)


func _is_new_best_time() -> bool:
	var best_ms: int = _stats.get_counter("crown_grid", "best_t%d" % _tier)
	return best_ms == 0 or elapsed_time < (float(best_ms) / 1000.0)


func _show_new_best_indicator() -> void:
	var cs := board._get_cell_size()
	var origin := board._get_grid_origin()
	var center := origin + Vector2(cs * logic.size * 0.5, cs * logic.size * 0.5)
	var color := Color(0.0, 2.0, 1.5) if AppTheme.is_neon else Color(0.2, 0.75, 1.0)
	ComboLabel.create(board, center, "NEW BEST!", color)
	_haptic.vibrate_medium()


func _show_win_dialog() -> void:
	var tier_name: String = TIER_NAMES.get(_tier, "")
	var dialog := AcceptDialog.new()
	dialog.title = "Crown Grid Complete!"
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
		_restart_same_tier()
	)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "menu":
			dialog.queue_free()
			SceneTransition.navigate(CROWN_GRID_MENU_SCENE)
		elif action == "bookmark":
			var ok: bool = _storage.bookmark_latest_replay()
			dialog.dialog_text += "\n\n" + ("✓ Replay bookmarked!" if ok else "✗ No replay to bookmark")
	)


func _restart_same_tier() -> void:
	var t := _tier
	SceneTransition.navigate(CROWN_GRID_GAME_SCENE, func(scene: Node) -> void:
		scene.start_new_game(t)
	)


# ---------------------------------------------------------------------------
# Stats recording
# ---------------------------------------------------------------------------

func _record_crown_grid_completion(tier: int, time: float) -> void:
	_stats.record("crown_grid", {
		"type": "completion",
		"tier": tier,
		"time": time,
	})
	_stats.increment_counter("crown_grid", "completed_t%d" % tier)
	var best_ms: int = _stats.get_counter("crown_grid", "best_t%d" % tier)
	var time_ms := int(time * 1000)
	if best_ms == 0 or time_ms < best_ms:
		_stats.set_counter("crown_grid", "best_t%d" % tier, time_ms)
	var streak: int = _stats.get_counter("crown_grid", "current_streak") + 1
	_stats.set_counter("crown_grid", "current_streak", streak)
	var best_streak: int = _stats.get_counter("crown_grid", "best_streak")
	if streak > best_streak:
		_stats.set_counter("crown_grid", "best_streak", streak)


# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func _update_button_states() -> void:
	undo_button.disabled = not logic.can_undo()
	redo_button.disabled = not logic.can_redo()
	hint_button.disabled = logic.is_completed


func _apply_panel_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)


# ---------------------------------------------------------------------------
# Teardown / cancellation
# ---------------------------------------------------------------------------

func _cancel_generation() -> void:
	_set_gen_cancelled(true)
	if _gen_thread and _gen_thread.is_started():
		_gen_thread.wait_to_finish()
	_gen_thread = null


func _exit_tree() -> void:
	_cancel_generation()
	super._exit_tree()


func _set_gen_cancelled(value: bool) -> void:
	_gen_mutex.lock()
	_gen_cancelled = value
	_gen_mutex.unlock()


func _get_gen_cancelled() -> bool:
	_gen_mutex.lock()
	var val := _gen_cancelled
	_gen_mutex.unlock()
	return val
