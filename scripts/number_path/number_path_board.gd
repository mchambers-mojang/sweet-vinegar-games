class_name NumberPathBoard
extends Control

## Number Path grid UI.
## Draws the grid, checkpoints, barriers, current path, and handles drag input.
## Emits signals for cell transitions; all rule validation stays in NumberPathLogic.

signal path_cell_entered(cell: Vector2i)
signal path_drag_released()
signal path_drag_started(cell: Vector2i)

var grid_width: int = 5
var grid_height: int = 5
var checkpoints: Array[Dictionary] = []   # [{x, y, n}]
var barriers: Array[Dictionary] = []      # [{r, c, dir}]

## The current path cells (display only — set from outside via set_path).
var _path: Array[Vector2i] = []

## Drag state
var _dragging: bool = false
var _last_drag_cell: Vector2i = Vector2i(-1, -1)

# Highlights
var _contradiction_cells: Array[Vector2i] = []
var _hint_cell: Vector2i = Vector2i(-1, -1)

# Drawing constants
const LINE_WIDTH := 1.0
const BORDER_WIDTH := 2.5
const BARRIER_WIDTH := 4.0
const PATH_WIDTH_RATIO := 0.38
const CHECKPOINT_RADIUS_RATIO := 0.3


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(w: int, h: int, cps: Array[Dictionary], bs: Array[Dictionary]) -> void:
	grid_width = w
	grid_height = h
	checkpoints = cps
	barriers = bs
	_path = []
	_contradiction_cells = []
	_hint_cell = Vector2i(-1, -1)
	queue_redraw()


func set_path(path: Array[Vector2i]) -> void:
	_path = path.duplicate()
	queue_redraw()


func extend_path(cell: Vector2i) -> void:
	_path.append(cell)
	queue_redraw()


func truncate_path(length: int) -> void:
	while _path.size() > length:
		_path.pop_back()
	queue_redraw()


func flash_contradiction(cells: Array[Vector2i]) -> void:
	_contradiction_cells = cells.duplicate()
	_hint_cell = Vector2i(-1, -1)
	queue_redraw()
	# Auto-clear after 1.5 s
	var t := create_tween()
	t.tween_interval(1.5)
	t.tween_callback(func() -> void:
		_contradiction_cells = []
		queue_redraw()
	)


func flash_hint(cell: Vector2i) -> void:
	_hint_cell = cell
	queue_redraw()
	var t := create_tween()
	t.tween_interval(0.8)
	t.tween_callback(func() -> void:
		_hint_cell = Vector2i(-1, -1)
		queue_redraw()
	)


func flash_all(_color: Color, _duration: float) -> void:
	var original_modulate := modulate
	modulate = Color(1.2, 1.1, 0.8)
	var t := create_tween()
	t.tween_interval(_duration)
	t.tween_callback(func() -> void: modulate = original_modulate)


# --- Input ---

func _gui_input(event: InputEvent) -> void:
	var is_touch := DisplayServer.is_touchscreen_available()

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_start_drag(st.position)
		else:
			_end_drag()
		accept_event()
		return

	if event is InputEventScreenDrag:
		if _dragging:
			_update_drag(event.position)
			accept_event()
		return

	if event is InputEventMouseButton and not is_touch:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_start_drag(mb.position)
			else:
				_end_drag()
			accept_event()
		return

	if event is InputEventMouseMotion and not is_touch:
		if _dragging:
			_update_drag(event.position)
			accept_event()
		return


func _start_drag(screen_pos: Vector2) -> void:
	var cell := _pos_to_cell(screen_pos)
	_dragging = true
	_last_drag_cell = cell
	DragEffect.suppress()
	path_drag_started.emit(cell)


func _update_drag(screen_pos: Vector2) -> void:
	var cell := _pos_to_cell(screen_pos)
	if cell == _last_drag_cell:
		return
	# Interpolate: if pointer skipped cells, walk each step
	var cells := _interpolate_cells(_last_drag_cell, cell)
	for c in cells:
		path_cell_entered.emit(c)
	_last_drag_cell = cell


func _end_drag() -> void:
	_dragging = false
	DragEffect.unsuppress()
	path_drag_released.emit()


## Walk from 'from' to 'to' one step at a time along the dominant axis.
## This handles sparse pointer events (touch interpolation).
func _interpolate_cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cur := from
	while cur != to:
		var dx := to.x - cur.x
		var dy := to.y - cur.y
		if abs(dx) >= abs(dy):
			cur.x += signi(dx)
		else:
			cur.y += signi(dy)
		result.append(cur)
	return result


# --- Coordinate helpers ---

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


func get_cell_center(col: int, row: int) -> Vector2:
	var cell_size := _get_cell_size()
	var origin := _get_grid_origin()
	return origin + Vector2((col + 0.5) * cell_size, (row + 0.5) * cell_size)


func screen_to_grid(local_pos: Vector2) -> Vector2i:
	return _pos_to_cell(local_pos)


# --- Drawing ---

func _draw() -> void:
	var cell_size := _get_cell_size()
	var origin := _get_grid_origin()
	var tm := AppTheme
	var bg_color := tm.get_color("cell_background")
	var line_color := tm.get_color("text_given")
	var neon_mode := tm.is_neon
	var grid_rect := Rect2(origin, Vector2(cell_size * grid_width, cell_size * grid_height))

	# Background
	draw_rect(grid_rect, bg_color)

	# Visited cell tint
	var visited_color := line_color
	visited_color.a = 0.12
	if neon_mode:
		visited_color = Color(0.0, 0.8, 0.8, 0.12)
	for cell in _path:
		var cell_rect := Rect2(
			origin + Vector2(cell.x * cell_size, cell.y * cell_size),
			Vector2(cell_size, cell_size)
		)
		draw_rect(cell_rect, visited_color)

	# Contradiction highlight
	for cell in _contradiction_cells:
		var cell_rect := Rect2(
			origin + Vector2(cell.x * cell_size, cell.y * cell_size),
			Vector2(cell_size, cell_size)
		)
		draw_rect(cell_rect, Color(1.0, 0.3, 0.3, 0.4))

	# Hint highlight
	if _hint_cell != Vector2i(-1, -1):
		var cell_rect := Rect2(
			origin + Vector2(_hint_cell.x * cell_size, _hint_cell.y * cell_size),
			Vector2(cell_size, cell_size)
		)
		var hint_color := Color(0.2, 0.9, 0.4, 0.45) if not neon_mode else Color(0.0, 2.0, 0.8, 0.45)
		draw_rect(cell_rect, hint_color)

	# Grid lines
	var grid_line_color := line_color.darkened(0.5)
	if neon_mode:
		grid_line_color = Color(0.15, 0.1, 0.35)
	for c in range(grid_width + 1):
		var x := origin.x + c * cell_size
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + grid_height * cell_size), grid_line_color, LINE_WIDTH)
	for r in range(grid_height + 1):
		var y := origin.y + r * cell_size
		draw_line(Vector2(origin.x, y), Vector2(origin.x + grid_width * cell_size, y), grid_line_color, LINE_WIDTH)

	# Barriers
	_draw_barriers(origin, cell_size, neon_mode)

	# Path line
	_draw_path(origin, cell_size, neon_mode)

	# Checkpoints
	_draw_checkpoints(origin, cell_size, neon_mode)

	# Border
	var border_col := line_color
	if neon_mode:
		border_col = Color(0.0, 1.5, 1.5)
	draw_rect(grid_rect, border_col, false, BORDER_WIDTH)
	if neon_mode:
		var outline_glow := Color(0.0, 0.6, 0.6, 0.25)
		draw_rect(Rect2(origin - Vector2(3, 3), Vector2(cell_size * grid_width + 6, cell_size * grid_height + 6)), outline_glow, false, 5.0)


func _draw_path(origin: Vector2, cell_size: float, neon_mode: bool) -> void:
	if _path.size() < 2:
		return
	var path_color := Color(0.2, 0.55, 1.0, 0.9)
	if neon_mode:
		path_color = Color(0.0, 1.5, 2.0, 0.95)
	var pw := cell_size * PATH_WIDTH_RATIO

	for i in range(_path.size() - 1):
		var a: Vector2i = _path[i]
		var b: Vector2i = _path[i + 1]
		var ca := origin + Vector2((a.x + 0.5) * cell_size, (a.y + 0.5) * cell_size)
		var cb := origin + Vector2((b.x + 0.5) * cell_size, (b.y + 0.5) * cell_size)
		draw_line(ca, cb, path_color, pw, true)
		if neon_mode:
			draw_line(ca, cb, Color(path_color.r * 0.3, path_color.g * 0.3, path_color.b * 0.3, 0.3), pw * 2.5, true)

	# Head dot
	if not _path.is_empty():
		var head: Vector2i = _path[_path.size() - 1]
		var center := origin + Vector2((head.x + 0.5) * cell_size, (head.y + 0.5) * cell_size)
		var head_color := Color(1.0, 0.9, 0.2, 1.0)
		if neon_mode:
			head_color = Color(2.0, 1.5, 0.0, 1.0)
		draw_circle(center, pw * 0.65, head_color)
		# Monochrome distinguishable ring
		draw_arc(center, pw * 0.65, 0, TAU, 16, Color(0, 0, 0, 0.5), 1.5)


func _draw_checkpoints(origin: Vector2, cell_size: float, neon_mode: bool) -> void:
	var font := ThemeDB.fallback_font
	var font_size := int(cell_size * 0.45)
	var radius := cell_size * CHECKPOINT_RADIUS_RATIO

	for cp in checkpoints:
		var cx := int(cp.get("x", 0))
		var cy := int(cp.get("y", 0))
		var cn := int(cp.get("n", 0))
		var center := origin + Vector2((cx + 0.5) * cell_size, (cy + 0.5) * cell_size)

		# Check if this checkpoint is already visited
		var visited := false
		for cell in _path:
			if cell.x == cx and cell.y == cy:
				visited = true
				break

		var fill_color := Color(0.25, 0.6, 1.0, 0.9) if not visited else Color(0.2, 0.8, 0.3, 0.9)
		if neon_mode:
			fill_color = Color(0.0, 1.5, 2.5, 0.9) if not visited else Color(0.0, 2.0, 0.5, 0.9)

		draw_circle(center, radius, fill_color)
		# Monochrome outline
		draw_arc(center, radius, 0, TAU, 24, Color(0, 0, 0, 0.7), 1.5)

		# Number label
		var text := str(cn)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := center - text_size / 2.0
		text_pos.y += text_size.y * 0.75
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _draw_barriers(origin: Vector2, cell_size: float, neon_mode: bool) -> void:
	var barrier_color := Color(0.9, 0.2, 0.2, 1.0)
	if neon_mode:
		barrier_color = Color(2.5, 0.2, 0.2, 1.0)
	var bw := BARRIER_WIDTH

	for barrier in barriers:
		var r := int(barrier.get("r", 0))
		var c := int(barrier.get("c", 0))
		var dir := int(barrier.get("dir", 0))

		if dir == NumberPathLogic.DIR_RIGHT:
			# Barrier on the right edge of cell (c, r)
			var x := origin.x + (c + 1) * cell_size
			var y0 := origin.y + r * cell_size + 2.0
			var y1 := origin.y + (r + 1) * cell_size - 2.0
			draw_line(Vector2(x, y0), Vector2(x, y1), barrier_color, bw)
		elif dir == NumberPathLogic.DIR_DOWN:
			# Barrier on the bottom edge of cell (c, r)
			var y := origin.y + (r + 1) * cell_size
			var x0 := origin.x + c * cell_size + 2.0
			var x1 := origin.x + (c + 1) * cell_size - 2.0
			draw_line(Vector2(x0, y), Vector2(x1, y), barrier_color, bw)
