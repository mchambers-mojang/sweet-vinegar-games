extends Control

## Shikaku game screen — board, timer, controls

const SIZE_NAMES := {5: "5×5", 7: "7×7", 8: "8×8", 10: "10×10", 12: "12×12", 15: "15×15"}

# Game state
var puzzle_data: Dictionary = {}  # width, height, numbers, solution
var grid_width: int = 10
var grid_height: int = 10
var elapsed_time: float = 0.0
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
@onready var timer_label: Label = %TimerLabel
@onready var size_label: Label = %SizeLabel
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var hint_button: Button = %HintButton
@onready var pause_button: Button = %PauseButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	board.rectangle_placed.connect(_on_rectangle_placed)
	board.rectangle_tapped.connect(_on_rectangle_tapped)
	undo_button.pressed.connect(_on_undo)
	redo_button.pressed.connect(_on_redo)
	hint_button.pressed.connect(_on_hint)
	pause_button.pressed.connect(_on_pause)
	back_button.pressed.connect(_on_back)
	_update_button_states()
	_apply_theme()
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


func start_new_game(w: int, h: int) -> void:
	grid_width = w
	grid_height = h
	puzzle_data = ShikakuGenerator.generate(w, h)
	board.setup(w, h, puzzle_data["numbers"])
	size_label.text = SIZE_NAMES.get(w, "%dx%d" % [w, h])
	elapsed_time = 0.0
	is_completed = false
	hints_used = 0
	undo_stack.clear()
	redo_stack.clear()
	ShikakuStatsManager.record_game_started(w)
	_update_button_states()
	_save_current_state()


func resume_game(data: Dictionary) -> void:
	grid_width = data.get("width", 10)
	grid_height = data.get("height", 10)
	puzzle_data = {
		"width": grid_width,
		"height": grid_height,
		"numbers": _deserialize_numbers(data.get("numbers", {})),
		"solution": _deserialize_rects(data.get("solution", [])),
	}
	board.setup(grid_width, grid_height, puzzle_data["numbers"])

	# Restore placed rectangles
	var saved_rects := _deserialize_rects(data.get("placed_rects", []))
	for rect in saved_rects:
		board.add_rect(rect)

	elapsed_time = data.get("elapsed_time", 0.0)
	hints_used = data.get("hints_used", 0)
	is_completed = false
	size_label.text = SIZE_NAMES.get(grid_width, "%dx%d" % [grid_width, grid_height])
	_update_button_states()


func _process(delta: float) -> void:
	if not is_completed and not is_paused:
		elapsed_time += delta
		if SettingsManager.show_timer:
			timer_label.text = _format_time(elapsed_time)
			timer_label.visible = true
		else:
			timer_label.visible = false

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
	# Push current state for undo
	undo_stack.append({"action": "place", "rect": rect})
	redo_stack.clear()
	board.add_rect(rect)
	SoundManager.play_place()
	HapticManager.vibrate_light()
	_update_button_states()
	_check_completion()
	_save_current_state()


func _on_rectangle_tapped(index: int) -> void:
	if is_completed:
		return
	var rect := board.placed_rects[index]
	undo_stack.append({"action": "remove", "rect": rect, "color_idx": index})
	redo_stack.clear()
	board.remove_rect(index)
	SoundManager.play_erase()
	HapticManager.vibrate_light()
	_update_button_states()
	_save_current_state()


func _on_undo() -> void:
	if undo_stack.is_empty():
		return
	var entry: Dictionary = undo_stack.pop_back()
	if entry["action"] == "place":
		# Undo a placement = remove the last rect
		var rect: Rect2i = entry["rect"]
		# Find and remove it
		for i in range(board.placed_rects.size() - 1, -1, -1):
			if board.placed_rects[i] == rect:
				board.remove_rect(i)
				break
		redo_stack.append(entry)
	elif entry["action"] == "remove":
		# Undo a removal = re-add the rect
		var rect: Rect2i = entry["rect"]
		board.add_rect(rect)
		redo_stack.append(entry)
	_update_button_states()
	_save_current_state()


func _on_redo() -> void:
	if redo_stack.is_empty():
		return
	var entry: Dictionary = redo_stack.pop_back()
	if entry["action"] == "place":
		var rect: Rect2i = entry["rect"]
		board.add_rect(rect)
		undo_stack.append(entry)
	elif entry["action"] == "remove":
		var rect: Rect2i = entry["rect"]
		for i in range(board.placed_rects.size() - 1, -1, -1):
			if board.placed_rects[i] == rect:
				board.remove_rect(i)
				break
		undo_stack.append(entry)
	_update_button_states()
	_save_current_state()


func _on_hint() -> void:
	if is_completed or hints_used >= 1:
		return
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


func _on_back() -> void:
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
	ShikakuStatsManager.record_game_completed(grid_width, elapsed_time)
	ShikakuSaveManager.clear_save()
	SoundManager.play_win()
	HapticManager.vibrate_success()
	board.flash_all(Color(1.2, 1.1, 0.8), 0.4)
	var timer := get_tree().create_timer(0.5)
	timer.timeout.connect(_show_win_dialog)


func _show_win_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Congratulations!"
	dialog.dialog_text = "You solved the %s puzzle\nin %s!" % [SIZE_NAMES.get(grid_width, ""), _format_time(elapsed_time)]
	if hints_used > 0:
		dialog.dialog_text += "\nHints used: %d" % hints_used
	dialog.ok_button_text = "Back to Menu"
	dialog.min_size = Vector2i(300, 0)
	add_child(dialog)
	dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		SceneTransition.transition_to("res://scenes/shikaku_menu.tscn")
	)


func _update_button_states() -> void:
	undo_button.disabled = undo_stack.is_empty()
	redo_button.disabled = redo_stack.is_empty()
	hint_button.disabled = hints_used >= 1


func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%d:%02d" % [mins, secs]


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


func _save_current_state() -> void:
	if is_completed:
		return
	ShikakuSaveManager.save_game({
		"width": grid_width,
		"height": grid_height,
		"numbers": _serialize_numbers(puzzle_data["numbers"]),
		"solution": _serialize_rects(puzzle_data["solution"]),
		"placed_rects": _serialize_rects(board.placed_rects),
		"elapsed_time": elapsed_time,
		"hints_used": hints_used,
	})


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
