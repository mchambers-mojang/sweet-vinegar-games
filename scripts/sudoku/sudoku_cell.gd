class_name SudokuCell
extends Control

## A single cell in the Sudoku grid

signal cell_pressed(index: int)

var index: int = 0
var row: int = 0
var col: int = 0
var box: int = 0

var value: int = 0          # Current displayed number (0 = empty)
var is_given: bool = false   # Whether this was part of the original puzzle
var is_error: bool = false   # Whether this cell has a conflict
var is_selected: bool = false
var is_highlighted: bool = false       # Same row/col/box as selected
var is_same_number: bool = false       # Same number as selected cell
var is_same_color: bool = false        # Same user-applied color as selected cell
var is_multi_selected: bool = false    # Part of a multi-selection group
var pencil_marks: Array[int] = []
var cell_color: Color = Color.TRANSPARENT  # User-applied color coding

var _bounce_tween: Tween
var _flash_tween: Tween
var _flash_base_color: Color = Color.TRANSPARENT
var _flash_alpha: float = 0.0  # 0 = no flash, 1 = full flash


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	gui_input.connect(_on_gui_input)


func setup(cell_index: int) -> void:
	index = cell_index
	row = index / 9
	col = index % 9
	box = (row / 3) * 3 + col / 3


func set_value(val: int, given: bool = false) -> void:
	value = val
	is_given = given
	is_error = false
	if val != 0:
		pencil_marks.clear()
	_play_bounce()
	queue_redraw()


func set_pencil_mark(val: int, active: bool) -> void:
	if active and val not in pencil_marks:
		pencil_marks.append(val)
		pencil_marks.sort()
	elif not active and val in pencil_marks:
		pencil_marks.erase(val)
	queue_redraw()


func toggle_pencil_mark(val: int) -> void:
	if val in pencil_marks:
		pencil_marks.erase(val)
	else:
		pencil_marks.append(val)
		pencil_marks.sort()
	queue_redraw()


func clear_cell() -> void:
	if is_given:
		return
	value = 0
	is_error = false
	pencil_marks.clear()
	queue_redraw()


func set_cell_color(color: Color) -> void:
	cell_color = color
	queue_redraw()


func set_selected(selected: bool) -> void:
	is_selected = selected
	queue_redraw()


func set_highlighted(highlighted: bool) -> void:
	is_highlighted = highlighted
	queue_redraw()


func set_same_number(same: bool) -> void:
	is_same_number = same
	queue_redraw()


func set_same_color(same: bool) -> void:
	is_same_color = same
	queue_redraw()


func set_multi_selected(selected: bool) -> void:
	is_multi_selected = selected
	queue_redraw()


func set_error(error: bool) -> void:
	is_error = error
	queue_redraw()


func _play_bounce() -> void:
	if _bounce_tween and _bounce_tween.is_running():
		_bounce_tween.kill()
	_bounce_tween = create_tween()
	pivot_offset = size / 2.0
	_bounce_tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.05)
	_bounce_tween.tween_property(self, "scale", Vector2.ONE, 0.1)


func flash(color: Color, duration: float) -> void:
	_flash_base_color = color
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()
	_flash_tween = create_tween()
	var fade_in := duration * 0.15
	var hold := duration * 0.35
	var fade_out := duration * 0.5
	_flash_tween.tween_method(_set_flash_alpha, 0.0, 1.0, fade_in)
	_flash_tween.tween_interval(hold)
	_flash_tween.tween_method(_set_flash_alpha, 1.0, 0.0, fade_out)


func _set_flash_alpha(val: float) -> void:
	_flash_alpha = val
	queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	# On touch devices, Godot emits both ScreenTouch and MouseButton for a single tap.
	# Only handle ScreenTouch on mobile and MouseButton on desktop to prevent double-fire.
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			cell_pressed.emit(index)
			accept_event()
	elif event is InputEventMouseButton and not DisplayServer.is_touchscreen_available():
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			cell_pressed.emit(index)
			accept_event()


func _draw() -> void:
	var tm := ThemeManager
	var cell_size := size

	# Background
	var bg_color: Color
	if is_multi_selected:
		if cell_color != Color.TRANSPARENT:
			bg_color = cell_color.lerp(tm.get_color("cell_selected"), 0.5)
		else:
			bg_color = tm.get_color("cell_selected")
	elif cell_color != Color.TRANSPARENT:
		bg_color = cell_color
		if is_selected:
			bg_color = bg_color.lerp(tm.get_color("cell_selected"), 0.5)
		elif is_same_color:
			bg_color = bg_color.lightened(0.15)
	elif is_selected:
		bg_color = tm.get_color("cell_selected")
	elif is_same_number and value != 0:
		bg_color = tm.get_color("cell_same_number")
	elif is_highlighted:
		bg_color = tm.get_color("cell_highlighted")
	elif is_given:
		bg_color = tm.get_color("cell_given")
	else:
		bg_color = tm.get_color("cell_background")

	if is_error:
		bg_color = bg_color.lerp(tm.get_color("cell_error"), 0.6)

	# Apply flash overlay if active
	if _flash_alpha > 0.0:
		bg_color = bg_color.lerp(_flash_base_color, _flash_alpha)

	draw_rect(Rect2(Vector2.ZERO, cell_size), bg_color)

	# Determine if we need contrasting text (when cell has a user-applied color)
	var has_custom_color := cell_color != Color.TRANSPARENT

	# Draw number or pencil marks
	if value != 0:
		var text_color: Color
		if is_error:
			text_color = tm.get_color("text_error")
		elif has_custom_color:
			# Use dark text on light colored backgrounds for contrast
			text_color = Color(0.1, 0.1, 0.1) if bg_color.get_luminance() > 0.5 else Color(0.95, 0.95, 0.95)
		elif is_given:
			text_color = tm.get_color("text_given")
		else:
			text_color = tm.get_color("text_placed")

		var font := ThemeDB.fallback_font
		var font_size := int(cell_size.y * 0.6)
		var text := str(value)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pos := (cell_size - text_size) / 2.0
		pos.y += text_size.y * 0.85
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	elif pencil_marks.size() > 0:
		var font := ThemeDB.fallback_font
		var pencil_size := int(cell_size.y * 0.28)
		var pencil_color: Color
		if has_custom_color:
			pencil_color = Color(0.2, 0.2, 0.2) if bg_color.get_luminance() > 0.5 else Color(0.85, 0.85, 0.85)
		else:
			pencil_color = tm.get_color("text_pencil")
		var cell_w := cell_size.x / 3.0
		var cell_h := cell_size.y / 3.0
		for mark in pencil_marks:
			var pm_col := (mark - 1) % 3
			var pm_row := (mark - 1) / 3
			var text := str(mark)
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, pencil_size)
			var px := pm_col * cell_w + (cell_w - text_size.x) / 2.0
			var py := pm_row * cell_h + (cell_h + text_size.y * 0.7) / 2.0
			draw_string(font, Vector2(px, py), text, HORIZONTAL_ALIGNMENT_LEFT, -1, pencil_size, pencil_color)
