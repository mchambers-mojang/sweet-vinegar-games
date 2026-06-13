extends GameScreen

## Shikaku game screen — board, timer, controls

const SIZE_NAMES := {5: "5×5", 7: "7×7", 8: "8×8", 10: "10×10", 12: "12×12", 15: "15×15"}
const LEGACY_SEED_HASH_INITIAL := 23
const LEGACY_SEED_HASH_MULTIPLIER := 31
const LEGACY_SEED_HASH_X_FACTOR := 7
const LEGACY_SEED_HASH_Y_FACTOR := 13

# Game state
var puzzle_data: Dictionary = {}  # width, height, numbers, solution
var grid_width: int = 10
var grid_height: int = 10
var is_completed: bool = false
var is_paused: bool = false
var hints_used: int = 0

# Undo/redo
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []

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
	return "res://scenes/shikaku_game.tscn"


func _is_initialized() -> bool:
	return not puzzle_data.is_empty()


func _is_completed() -> bool:
	return is_completed


func _serialize_state() -> Dictionary:
	return {
		"width": grid_width,
		"height": grid_height,
		"numbers": _serialize_numbers(puzzle_data["numbers"]),
		"solution": _serialize_rects(puzzle_data["solution"]),
		"placed_rects": _serialize_rects(board.placed_rects),
		"elapsed_time": elapsed_time,
		"hints_used": hints_used,
		"random_seed": random_seed,
		"replay_id": replay_id,
	}


func _deserialize_state(data: Dictionary) -> void:
	resume_game(data)


func _get_crash_state() -> Dictionary:
	return {
		"game": "shikaku",
		"width": grid_width,
		"height": grid_height,
		"elapsed_time": elapsed_time,
		"is_completed": is_completed,
		"is_paused": is_paused,
		"hints_used": hints_used,
		"placed_rects": board.placed_rects.size() if board else 0,
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
	is_completed = false
	hints_used = 0
	undo_stack.clear()
	redo_stack.clear()
	begin_session()


func resume_game(data: Dictionary) -> void:
	grid_width = data.get("width", 10)
	grid_height = data.get("height", 10)
	hints_used = data.get("hints_used", 0)
	is_completed = false
	begin_session(data)


# --- Session ceremony hooks ---

func _should_tick_timer() -> bool:
	return not is_completed and not is_paused


func _get_start_crash_params() -> Dictionary:
	return {"width": grid_width, "height": grid_height}


func _get_resume_crash_params(saved_data: Dictionary) -> Dictionary:
	return {"width": saved_data.get("width", 10), "height": saved_data.get("height", 10)}


func _get_initial_state() -> Dictionary:
	return {
		"width": grid_width,
		"height": grid_height,
		"numbers": _serialize_numbers(puzzle_data["numbers"]),
	}


func _get_settings_snapshot() -> Dictionary:
	return {"show_timer": SettingsManager.show_timer}


func _setup_game(saved_data: Dictionary) -> void:
	if saved_data.is_empty():
		puzzle_data = ShikakuGenerator.generate(grid_width, grid_height, random_seed)
		board.setup(grid_width, grid_height, puzzle_data["numbers"])
		size_label.text = SIZE_NAMES.get(grid_width, "%dx%d" % [grid_width, grid_height])
		_update_button_states()
	else:
		puzzle_data = {
			"width": grid_width,
			"height": grid_height,
			"numbers": _deserialize_numbers(saved_data.get("numbers", {})),
			"solution": _deserialize_rects(saved_data.get("solution", [])),
		}
		board.setup(grid_width, grid_height, puzzle_data["numbers"])
		var saved_rects := _deserialize_rects(saved_data.get("placed_rects", []))
		for rect in saved_rects:
			board.add_rect(rect)
		# Legacy fallback: old saves had no random_seed field. Derive one deterministically
		# so replay/crash metadata is consistent. begin_session() calls ReplayManager AFTER
		# _setup_game(), so this updated value is used by the replay session start.
		if random_seed == 0:
			random_seed = _derive_seed_from_numbers(puzzle_data["numbers"])
		size_label.text = SIZE_NAMES.get(grid_width, "%dx%d" % [grid_width, grid_height])
		_update_button_states()


func _increment_stats() -> void:
	GameStatsManager.increment_counter("shikaku", "games_started")
	GameStatsManager.increment_counter("shikaku", "started_s%d" % grid_width)


func _get_analytics_params() -> Dictionary:
	return {"game": "shikaku", "width": grid_width, "height": grid_height}


func _process(delta: float) -> void:
	super._process(delta)
	if not is_completed and not is_paused:
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
			print("Shikaku cheat auto-solve: %s" % ("ON" if _cheat_active else "OFF"))
			get_viewport().set_input_as_handled()


func _on_rectangle_placed(rect: Rect2i) -> void:
	if is_completed:
		return
	ReplayManager.record_input(elapsed_time, "rectangle_placed", {
		"x": rect.position.x,
		"y": rect.position.y,
		"w": rect.size.x,
		"h": rect.size.y,
	})
	# Push current state for undo
	undo_stack.append({"action": "place", "rect": rect})
	redo_stack.clear()
	board.add_rect(rect)
	SoundManager.play_place()
	HapticManager.vibrate_light()
	# Neon shockwave on rect placement
	if ThemeManager.is_neon:
		var cell_size := board._get_cell_size()
		var origin := board._get_grid_origin()
		var center := origin + Vector2(
			(rect.position.x + rect.size.x / 2.0) * cell_size,
			(rect.position.y + rect.size.y / 2.0) * cell_size
		)
		NeonRing.create(board, center, Color(0.0, 1.5, 1.5), cell_size * 2.5, 0.25, 0.3)
	_update_button_states()
	_check_completion()
	_save_current_state()


func _on_rectangle_tapped(index: int) -> void:
	if is_completed:
		return
	ReplayManager.record_input(elapsed_time, "rectangle_removed", {"index": index})
	var rect := board.placed_rects[index]
	undo_stack.append({"action": "remove", "rect": rect, "color_idx": index})
	redo_stack.clear()
	board.remove_rect(index)
	SoundManager.play_erase()
	HapticManager.vibrate_light()
	_update_button_states()
	_save_current_state()


func _on_undo() -> void:
	if is_completed:
		return
	if undo_stack.is_empty():
		return
	var entry: Dictionary = undo_stack.pop_back()
	if entry["action"] == "place":
		# Undo a placement = remove the last rect
		var placed_rect: Rect2i = entry["rect"]
		# Find and remove it
		for i in range(board.placed_rects.size() - 1, -1, -1):
			if board.placed_rects[i] == placed_rect:
				ReplayManager.record_input(elapsed_time, "rectangle_removed", {"index": i})
				board.remove_rect(i)
				break
		redo_stack.append(entry)
	elif entry["action"] == "remove":
		# Undo a removal = re-add the rect
		var removed_rect: Rect2i = entry["rect"]
		ReplayManager.record_input(elapsed_time, "rectangle_placed", {
			"x": removed_rect.position.x,
			"y": removed_rect.position.y,
			"w": removed_rect.size.x,
			"h": removed_rect.size.y,
		})
		board.add_rect(removed_rect)
		redo_stack.append(entry)
	_update_button_states()
	_save_current_state()


func _on_redo() -> void:
	if is_completed:
		return
	if redo_stack.is_empty():
		return
	var entry: Dictionary = redo_stack.pop_back()
	if entry["action"] == "place":
		var redo_rect: Rect2i = entry["rect"]
		ReplayManager.record_input(elapsed_time, "rectangle_placed", {
			"x": redo_rect.position.x,
			"y": redo_rect.position.y,
			"w": redo_rect.size.x,
			"h": redo_rect.size.y,
		})
		board.add_rect(redo_rect)
		undo_stack.append(entry)
	elif entry["action"] == "remove":
		var removed_rect: Rect2i = entry["rect"]
		for i in range(board.placed_rects.size() - 1, -1, -1):
			if board.placed_rects[i] == removed_rect:
				ReplayManager.record_input(elapsed_time, "rectangle_removed", {"index": i})
				board.remove_rect(i)
				break
		undo_stack.append(entry)
	_update_button_states()
	_save_current_state()


func _on_hint() -> void:
	if is_completed or hints_used >= 1:
		return
	CrashReporter.register_user_action("shikaku_hint_used")
	var sol: Array[Rect2i] = puzzle_data.get("solution", [] as Array[Rect2i])
	if sol.is_empty():
		return
	# Find a solution rect that isn't already placed
	var candidates: Array[Rect2i] = []
	for rect in sol:
		var already_placed := false
		for pr in board.placed_rects:
			if pr == rect:
				already_placed = true
				break
		if not already_placed:
			candidates.append(rect)
	if candidates.is_empty():
		return
	candidates.shuffle()
	var hint_rect := candidates[0]
	ReplayManager.record_input(elapsed_time, "rectangle_placed", {
		"x": hint_rect.position.x,
		"y": hint_rect.position.y,
		"w": hint_rect.size.x,
		"h": hint_rect.size.y,
	})
	undo_stack.append({"action": "place", "rect": hint_rect})
	redo_stack.clear()
	board.add_rect(hint_rect)
	hints_used += 1
	hint_button.disabled = true
	SoundManager.play_place()
	HapticManager.vibrate_medium()
	_update_button_states()
	_check_completion()
	_save_current_state()


func _on_pause() -> void:
	is_paused = not is_paused
	pause_button.text = "Resume" if is_paused else "Pause"
	board.visible = not is_paused
	CrashReporter.register_user_action("shikaku_pause_toggled", {"is_paused": is_paused})


func _on_back() -> void:
	ReplayManager.finish_session("abandoned", board.placed_rects.size(), elapsed_time, {
		"width": grid_width,
		"height": grid_height,
	})
	CrashReporter.register_user_action("shikaku_back_to_menu")
	if not is_completed:
		AchievementManager.track_streak_broken()
	_save_current_state()
	SceneTransition.transition_to("res://scenes/shikaku_menu.tscn")


func _check_completion() -> void:
	if not board.is_fully_covered():
		return
	# Validate the solution
	var player_rects: Array[Rect2i] = board.placed_rects.duplicate()
	if ShikakuSolver.validate(grid_width, grid_height, puzzle_data["numbers"], player_rects):
		_handle_win()


func _handle_win() -> void:
	is_completed = true
	ReplayManager.finish_session("win", board.placed_rects.size(), elapsed_time, {
		"width": grid_width,
		"height": grid_height,
		"hints_used": hints_used,
	})
	var is_new_best := _is_new_best_time()
	_record_shikaku_completion(grid_width, elapsed_time)
	AchievementManager.track_game_won("shikaku")
	AchievementManager.track_shikaku_won(grid_width, elapsed_time)
	AnalyticsManager.log_event("game_over", {
		"game": "shikaku",
		"won": true,
		"width": grid_width,
		"height": grid_height,
		"elapsed_time": elapsed_time,
		"hints_used": hints_used,
	})
	clear_save()
	SoundManager.play_win()
	HapticManager.vibrate_success()
	if is_new_best:
		_show_new_best_indicator()
	# Neon win shockwave
	if ThemeManager.is_neon:
		var cell_size := board._get_cell_size()
		var origin := board._get_grid_origin()
		var center := origin + Vector2(
			(board.grid_width / 2.0) * cell_size,
			(board.grid_height / 2.0) * cell_size
		)
		NeonRing.create(board, center, Color(0.0, 2.0, 1.5), cell_size * 6.0, 0.5, 1.2)
		NeonFxManager.screen_shake(6.0, 0.2)
	board.flash_all(Color(1.2, 1.1, 0.8), 0.4)
	var timer := get_tree().create_timer(0.5)
	timer.timeout.connect(_show_win_dialog)


func _is_new_best_time() -> bool:
	var best_ms: int = GameStatsManager.get_counter("shikaku", "best_s%d" % grid_width)
	return best_ms == 0 or elapsed_time < (float(best_ms) / 1000.0)


func _show_new_best_indicator() -> void:
	var cell_size := board._get_cell_size()
	var origin := board._get_grid_origin()
	var center := origin + Vector2(
		(board.grid_width / 2.0) * cell_size,
		(board.grid_height / 2.0) * cell_size
	)
	var color := Color(0.0, 2.0, 1.5) if ThemeManager.is_neon else Color(0.2, 0.75, 1.0)
	ComboLabel.create(board, center, "NEW BEST!", color)
	HapticManager.vibrate_medium()


func _show_win_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Congratulations!"
	dialog.dialog_text = "You solved the %s puzzle\nin %s!" % [SIZE_NAMES.get(grid_width, ""), _format_time(elapsed_time)]
	if hints_used > 0:
		dialog.dialog_text += "\nHints used: %d" % hints_used
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
			SceneTransition.transition_to("res://scenes/shikaku_menu.tscn")
		elif action == "bookmark":
			var success := ReplayManager.bookmark_latest_replay()
			if success:
				dialog.dialog_text += "\n\n✓ Replay bookmarked!"
			else:
				dialog.dialog_text += "\n\n✗ No replay to bookmark"
	)


func _restart_same_game() -> void:
	var w := grid_width
	var h := grid_height
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load("res://scenes/shikaku_game.tscn").instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.start_new_game(w, h)
		queue_free()
	)


func _update_button_states() -> void:
	undo_button.disabled = is_completed or undo_stack.is_empty()
	redo_button.disabled = is_completed or redo_stack.is_empty()
	hint_button.disabled = is_completed or hints_used >= 1


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("background")
	add_theme_stylebox_override("panel", style)


func _cheat_place_one() -> void:
	var sol: Array[Rect2i] = puzzle_data.get("solution", [] as Array[Rect2i])
	if sol.is_empty():
		_cheat_active = false
		return
	# Find a solution rect not already placed
	for rect in sol:
		var found := false
		for pr in board.placed_rects:
			if pr == rect:
				found = true
				break
		if not found:
			board.add_rect(rect)
			SoundManager.play_place()
			_check_completion()
			_save_current_state()
			return
	_cheat_active = false


func _serialize_numbers(nums: Dictionary) -> Dictionary:
	var result := {}
	for pos in nums.keys():
		result["%d,%d" % [pos.x, pos.y]] = nums[pos]
	return result


func _deserialize_numbers(data: Dictionary) -> Dictionary:
	var result := {}
	for key in data.keys():
		var parts := str(key).split(",")
		if parts.size() == 2:
			result[Vector2i(int(parts[0]), int(parts[1]))] = int(data[key])
	return result


func _serialize_rects(rects: Array[Rect2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rect in rects:
		result.append({"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y})
	return result


func _deserialize_rects(data) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				result.append(Rect2i(int(entry.get("x", 0)), int(entry.get("y", 0)), int(entry.get("w", 1)), int(entry.get("h", 1))))
	return result


func _derive_seed_from_numbers(nums: Dictionary) -> int:
	# Legacy fallback for saves created before explicit replay seeds existed.
	# Multipliers keep the fold deterministic while distributing coordinate/value changes.
	var keys: Array = nums.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y
	)
	var seed := LEGACY_SEED_HASH_INITIAL
	for key in keys:
		var pos: Vector2i = key
		seed = int((seed * LEGACY_SEED_HASH_MULTIPLIER + pos.x * LEGACY_SEED_HASH_X_FACTOR + pos.y * LEGACY_SEED_HASH_Y_FACTOR + int(nums[pos])) & 0x7fffffff)
	return seed


func _record_shikaku_completion(grid_size: int, time: float) -> void:
	GameStatsManager.record("shikaku", {
		"type": "completion",
		"grid_size": grid_size,
		"time": time,
	})
	GameStatsManager.increment_counter("shikaku", "completed_s%d" % grid_size)
	# Best time (stored as ms int)
	var best_ms: int = GameStatsManager.get_counter("shikaku", "best_s%d" % grid_size)
	var time_ms := int(time * 1000)
	if best_ms == 0 or time_ms < best_ms:
		GameStatsManager.set_counter("shikaku", "best_s%d" % grid_size, time_ms)
	# Streak
	var streak: int = GameStatsManager.get_counter("shikaku", "current_streak") + 1
	GameStatsManager.set_counter("shikaku", "current_streak", streak)
	var best_streak: int = GameStatsManager.get_counter("shikaku", "best_streak")
	if streak > best_streak:
		GameStatsManager.set_counter("shikaku", "best_streak", streak)
