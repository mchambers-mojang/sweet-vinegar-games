class_name ShikakuBoard
extends Control

## The Shikaku grid UI — draws grid lines, numbers, and placed rectangles

signal rectangle_placed(rect: Rect2i)
signal rectangle_tapped(index: int)

var grid_width: int = 10
var grid_height: int = 10
var numbers: Dictionary = {}  # Vector2i -> int
var placed_rects: Array[Rect2i] = []
var rect_colors: Array[Color] = []

# Drag state
var _dragging: bool = false
var _drag_start: Vector2i = Vector2i(-1, -1)
var _drag_end: Vector2i = Vector2i(-1, -1)
var _drag_preview: Rect2i = Rect2i()

# Drawing constants
const LINE_WIDTH := 1.0
const BORDER_WIDTH := 2.0
const RECT_BORDER := 2.0

# Color palette for auto-coloring rectangles
const PALETTE: Array[Color] = [
	Color(0.6, 0.8, 1.0, 0.35),    # Light blue
	Color(1.0, 0.85, 0.6, 0.35),   # Light orange
	Color(0.7, 1.0, 0.7, 0.35),    # Light green
	Color(1.0, 0.7, 0.7, 0.35),    # Light red
	Color(0.85, 0.7, 1.0, 0.35),   # Light purple
	Color(1.0, 1.0, 0.65, 0.35),   # Light yellow
	Color(0.65, 1.0, 0.9, 0.35),   # Light teal
	Color(1.0, 0.75, 0.85, 0.35),  # Light pink
]

var _color_index: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(w: int, h: int, nums: Dictionary) -> void:
	grid_width = w
	grid_height = h
	numbers = nums
	placed_rects.clear()
	rect_colors.clear()
	_color_index = 0
	queue_redraw()


func _get_cell_size() -> float:
	var available_w := size.x - BORDER_WIDTH * 2
	var available_h := size.y - BORDER_WIDTH * 2
	return minf(available_w / grid_width, available_h / grid_height)


func _get_grid_origin() -> Vector2:
	var cell_size := _get_cell_size()
	var grid_w := cell_size * grid_width
	var grid_h := cell_size * grid_height
	return Vector2((size.x - grid_w) / 2.0, (size.y - grid_h) / 2.0)


func _pos_to_cell(pos: Vector2) -> Vector2i:
	var origin := _get_grid_origin()
	var cell_size := _get_cell_size()
	var col := int((pos.x - origin.x) / cell_size)
	var row := int((pos.y - origin.y) / cell_size)
	col = clampi(col, 0, grid_width - 1)
	row = clampi(row, 0, grid_height - 1)
	return Vector2i(col, row)


func _gui_input(event: InputEvent) -> void:
	var touch_event: bool = false
	var pressed: bool = false
	var released: bool = false
	var pos := Vector2.ZERO

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			touch_event = true
			pressed = mb.pressed
			released = not mb.pressed
			pos = mb.position
	elif event is InputEventMouseMotion:
		if _dragging:
			var mm := event as InputEventMouseMotion
			_drag_end = _pos_to_cell(mm.position)
			_update_drag_preview()
			queue_redraw()
			accept_event()
		return
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		touch_event = true
		pressed = st.pressed
		released = not st.pressed
		pos = st.position
	elif event is InputEventScreenDrag:
		if _dragging:
			var sd := event as InputEventScreenDrag
			_drag_end = _pos_to_cell(sd.position)
			_update_drag_preview()
			queue_redraw()
			accept_event()
		return

	if not touch_event:
		return

	if pressed:
		var cell := _pos_to_cell(pos)
		# Check if tapping an existing rectangle
		var tapped_idx := _find_rect_at(cell)
		if tapped_idx >= 0:
			rectangle_tapped.emit(tapped_idx)
			accept_event()
			return
		_dragging = true
		_drag_start = cell
		_drag_end = cell
		_update_drag_preview()
		queue_redraw()
		accept_event()
	elif released and _dragging:
		_dragging = false
		_drag_end = _pos_to_cell(pos)
		_update_drag_preview()
		if _drag_preview.size.x > 0 and _drag_preview.size.y > 0:
			rectangle_placed.emit(_drag_preview)
		_drag_preview = Rect2i()
		queue_redraw()
		accept_event()


func _find_rect_at(cell: Vector2i) -> int:
	# Search in reverse order (last placed = on top)
	for i in range(placed_rects.size() - 1, -1, -1):
		if placed_rects[i].has_point(cell):
			return i
	return -1


func _update_drag_preview() -> void:
	var min_c := mini(_drag_start.x, _drag_end.x)
	var max_c := maxi(_drag_start.x, _drag_end.x)
	var min_r := mini(_drag_start.y, _drag_end.y)
	var max_r := maxi(_drag_start.y, _drag_end.y)
	_drag_preview = Rect2i(min_c, min_r, max_c - min_c + 1, max_r - min_r + 1)


func add_rect(rect: Rect2i) -> void:
	placed_rects.append(rect)
	rect_colors.append(PALETTE[_color_index % PALETTE.size()])
	_color_index += 1
	queue_redraw()


func remove_rect(index: int) -> void:
	if index >= 0 and index < placed_rects.size():
		placed_rects.remove_at(index)
		rect_colors.remove_at(index)
		queue_redraw()


func is_fully_covered() -> bool:
	var covered := PackedByteArray()
	covered.resize(grid_width * grid_height)
	covered.fill(0)
	for rect in placed_rects:
		for r in range(rect.position.y, rect.position.y + rect.size.y):
			for c in range(rect.position.x, rect.position.x + rect.size.x):
				covered[r * grid_width + c] = 1
	for i in covered.size():
		if covered[i] == 0:
			return false
	return true


func _draw() -> void:
	var cell_size := _get_cell_size()
	var origin := _get_grid_origin()
	var tm := ThemeManager
	var bg_color := tm.get_color("cell_background")
	var line_color := tm.get_color("text_given")
	var grid_rect := Rect2(origin, Vector2(cell_size * grid_width, cell_size * grid_height))

	# Background
	draw_rect(grid_rect, bg_color)

	# Placed rectangles (fill)
	for i in range(placed_rects.size()):
		var rect := placed_rects[i]
		var color := rect_colors[i]
		var draw_rect_pos := origin + Vector2(rect.position.x * cell_size, rect.position.y * cell_size)
		var draw_rect_size := Vector2(rect.size.x * cell_size, rect.size.y * cell_size)
		draw_rect(Rect2(draw_rect_pos, draw_rect_size), color)

	# Placed rectangles (border)
	for i in range(placed_rects.size()):
		var rect := placed_rects[i]
		var border_color := rect_colors[i]
		border_color.a = 0.9
		var draw_rect_pos := origin + Vector2(rect.position.x * cell_size, rect.position.y * cell_size)
		var draw_rect_size := Vector2(rect.size.x * cell_size, rect.size.y * cell_size)
		# Top
		draw_rect(Rect2(draw_rect_pos, Vector2(draw_rect_size.x, RECT_BORDER)), border_color)
		# Bottom
		draw_rect(Rect2(draw_rect_pos + Vector2(0, draw_rect_size.y - RECT_BORDER), Vector2(draw_rect_size.x, RECT_BORDER)), border_color)
		# Left
		draw_rect(Rect2(draw_rect_pos, Vector2(RECT_BORDER, draw_rect_size.y)), border_color)
		# Right
		draw_rect(Rect2(draw_rect_pos + Vector2(draw_rect_size.x - RECT_BORDER, 0), Vector2(RECT_BORDER, draw_rect_size.y)), border_color)

	# Drag preview
	if _dragging and _drag_preview.size.x > 0:
		var preview_pos := origin + Vector2(_drag_preview.position.x * cell_size, _drag_preview.position.y * cell_size)
		var preview_size := Vector2(_drag_preview.size.x * cell_size, _drag_preview.size.y * cell_size)
		var preview_color := Color(0.5, 0.8, 1.0, 0.25)
		draw_rect(Rect2(preview_pos, preview_size), preview_color)
		# Preview border
		var pb := Color(0.5, 0.8, 1.0, 0.7)
		draw_rect(Rect2(preview_pos, Vector2(preview_size.x, 2)), pb)
		draw_rect(Rect2(preview_pos + Vector2(0, preview_size.y - 2), Vector2(preview_size.x, 2)), pb)
		draw_rect(Rect2(preview_pos, Vector2(2, preview_size.y)), pb)
		draw_rect(Rect2(preview_pos + Vector2(preview_size.x - 2, 0), Vector2(2, preview_size.y)), pb)

	# Grid lines
	for c in range(grid_width + 1):
		var x := origin.x + c * cell_size
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + grid_height * cell_size), line_color.darkened(0.5), LINE_WIDTH)
	for r in range(grid_height + 1):
		var y := origin.y + r * cell_size
		draw_line(Vector2(origin.x, y), Vector2(origin.x + grid_width * cell_size, y), line_color.darkened(0.5), LINE_WIDTH)

	# Border
	draw_rect(grid_rect, line_color, false, BORDER_WIDTH)

	# Numbers
	var font := ThemeDB.fallback_font
	var font_size := int(cell_size * 0.55)
	var text_color := tm.get_color("text_given")
	for pos in numbers.keys():
		var val: int = numbers[pos]
		var text := str(val)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var cell_origin := origin + Vector2(pos.x * cell_size, pos.y * cell_size)
		var text_pos := cell_origin + (Vector2(cell_size, cell_size) - text_size) / 2.0
		text_pos.y += text_size.y * 0.85
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


## Flash all cells for win celebration
func flash_all(color: Color, duration: float) -> void:
	# Simple: temporarily tint the whole grid
	var original_modulate := modulate
	modulate = Color(1.2, 1.1, 0.8)
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_callback(func() -> void: modulate = original_modulate)
