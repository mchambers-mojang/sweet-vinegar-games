class_name CrownGridBoard
extends Control

## Crown Grid board UI — draws grid, regions, crowns, excluded marks, and
## handles tap and drag input.

signal cell_tapped(cell: Vector2i)
signal cells_dragged(cells: Array)  # Array[Vector2i] — drag paint path

# Board data (set via setup())
var grid_size: int = 6
var region_map: PackedInt32Array = PackedInt32Array()
var cell_states: PackedByteArray = PackedByteArray()
var violation_cells: Dictionary = {}  # Vector2i -> bool

# Drag state
var _dragging: bool = false
var _drag_cells: Array[Vector2i] = []
var _last_drag_cell: Vector2i = Vector2i(-1, -1)

# Drawing constants
const BORDER_WIDTH := 3.0
const REGION_BORDER_WIDTH := 2.5
const INNER_LINE_WIDTH := 0.5
const MIN_CELL_TARGET := 44.0  # accessibility minimum

# Region colour palette (light fills — region identity for monochrome uses borders)
const REGION_PALETTE: Array[Color] = [
	Color(0.75, 0.88, 1.00, 0.30),
	Color(1.00, 0.88, 0.72, 0.30),
	Color(0.78, 1.00, 0.78, 0.30),
	Color(1.00, 0.78, 0.78, 0.30),
	Color(0.88, 0.78, 1.00, 0.30),
	Color(1.00, 1.00, 0.72, 0.30),
	Color(0.72, 1.00, 0.92, 0.30),
	Color(1.00, 0.80, 0.90, 0.30),
	Color(0.85, 0.95, 0.75, 0.30),
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("debug_grid_source")


func setup(p_size: int, p_regions: PackedInt32Array) -> void:
	grid_size = p_size
	region_map = p_regions.duplicate()
	cell_states = PackedByteArray()
	cell_states.resize(p_size * p_size)
	cell_states.fill(0)
	violation_cells.clear()
	queue_redraw()


func set_cells(states: PackedByteArray) -> void:
	cell_states = states.duplicate()
	queue_redraw()


func set_violations(viols: Array[Vector2i]) -> void:
	violation_cells.clear()
	for v in viols:
		violation_cells[v] = true
	queue_redraw()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _get_cell_size() -> float:
	var available_w := size.x - BORDER_WIDTH * 2.0
	var available_h := size.y - BORDER_WIDTH * 2.0
	return minf(available_w / grid_size, available_h / grid_size)


func _get_grid_origin() -> Vector2:
	var cs := _get_cell_size()
	var gw := cs * grid_size
	var gh := cs * grid_size
	return Vector2((size.x - gw) / 2.0, (size.y - gh) / 2.0)


func get_cell_screen_rect(col: int, row: int) -> Rect2:
	var cs := _get_cell_size()
	var origin := _get_grid_origin()
	return Rect2(origin + Vector2(col * cs, row * cs), Vector2(cs, cs))


func get_cell_center(col: int, row: int) -> Vector2:
	return get_cell_screen_rect(col, row).get_center()


func screen_to_grid(local_pos: Vector2) -> Vector2i:
	return _pos_to_cell(local_pos)


func _pos_to_cell(pos: Vector2) -> Vector2i:
	var origin := _get_grid_origin()
	var cs := _get_cell_size()
	var col := int((pos.x - origin.x) / cs)
	var row := int((pos.y - origin.y) / cs)
	return Vector2i(clampi(col, 0, grid_size - 1), clampi(row, 0, grid_size - 1))


func _draw() -> void:
	if grid_size <= 0 or region_map.is_empty():
		return

	var cs := _get_cell_size()
	var origin := _get_grid_origin()
	var tm := AppTheme
	var bg := tm.get_color("cell_background")
	var text_col := tm.get_color("text_given")
	var is_neon := tm.is_neon

	# Background
	var grid_rect := Rect2(origin, Vector2(cs * grid_size, cs * grid_size))
	draw_rect(grid_rect, bg)

	# Region fills
	for r in range(grid_size):
		for c in range(grid_size):
			var reg := region_map[r * grid_size + c]
			if reg >= 0:
				var pal_col := REGION_PALETTE[reg % REGION_PALETTE.size()]
				if is_neon:
					pal_col = Color(pal_col.r * 0.5, pal_col.g * 0.5, pal_col.b * 0.5, 0.20)
				draw_rect(Rect2(origin + Vector2(c * cs, r * cs), Vector2(cs, cs)), pal_col)

	# Cell states (excluded and crown glyphs)
	var font := ThemeDB.fallback_font
	var crown_size := int(cs * 0.60)
	var excl_size := int(cs * 0.45)

	for r in range(grid_size):
		for c in range(grid_size):
			var st := int(cell_states[r * grid_size + c])
			var cell_origin := origin + Vector2(c * cs, r * cs)
			var center := cell_origin + Vector2(cs * 0.5, cs * 0.5)

			if st == 1:  # EXCLUDED
				var excl_col := text_col.darkened(0.3) if not is_neon else Color(0.6, 0.6, 0.6, 0.6)
				_draw_x(center, cs * 0.22, excl_col)
			elif st == 2:  # CROWN
				var is_violation := violation_cells.has(Vector2i(c, r))
				var crown_col := Color(1.0, 0.75, 0.1) if not is_neon else Color(1.5, 1.3, 0.0)
				if is_violation:
					crown_col = Color(1.0, 0.25, 0.2) if not is_neon else Color(2.0, 0.3, 0.2)
				_draw_crown(center, cs * 0.38, crown_col, font, crown_size)

	# Inner grid lines
	var inner_col := text_col.darkened(0.6)
	if is_neon:
		inner_col = Color(0.15, 0.10, 0.35, 0.8)
	for col in range(1, grid_size):
		var x := origin.x + col * cs
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + grid_size * cs), inner_col, INNER_LINE_WIDTH)
	for row in range(1, grid_size):
		var y := origin.y + row * cs
		draw_line(Vector2(origin.x, y), Vector2(origin.x + grid_size * cs, y), inner_col, INNER_LINE_WIDTH)

	# Region borders (thick lines on region boundaries — visible in monochrome)
	var reg_border_col := text_col if not is_neon else Color(0.0, 1.5, 1.5)
	for r in range(grid_size):
		for c in range(grid_size):
			var reg := region_map[r * grid_size + c]
			var cell_orig := origin + Vector2(c * cs, r * cs)
			# Top edge
			if r == 0 or region_map[(r - 1) * grid_size + c] != reg:
				draw_line(cell_orig, cell_orig + Vector2(cs, 0), reg_border_col, REGION_BORDER_WIDTH)
			# Bottom edge
			if r == grid_size - 1 or region_map[(r + 1) * grid_size + c] != reg:
				draw_line(cell_orig + Vector2(0, cs), cell_orig + Vector2(cs, cs), reg_border_col, REGION_BORDER_WIDTH)
			# Left edge
			if c == 0 or region_map[r * grid_size + (c - 1)] != reg:
				draw_line(cell_orig, cell_orig + Vector2(0, cs), reg_border_col, REGION_BORDER_WIDTH)
			# Right edge
			if c == grid_size - 1 or region_map[r * grid_size + (c + 1)] != reg:
				draw_line(cell_orig + Vector2(cs, 0), cell_orig + Vector2(cs, cs), reg_border_col, REGION_BORDER_WIDTH)

	# Outer border
	var border_col := text_col if not is_neon else Color(0.0, 1.5, 1.5)
	draw_rect(grid_rect, border_col, false, BORDER_WIDTH)
	if is_neon:
		draw_rect(Rect2(origin - Vector2(3, 3), Vector2(cs * grid_size + 6, cs * grid_size + 6)),
				Color(0.0, 0.6, 0.6, 0.2), false, 5.0)


func _draw_crown(center: Vector2, radius: float, color: Color, font: Font, font_size: int) -> void:
	# Draw a crown symbol using a Unicode character
	var crown_char := "♛"
	var ts := font.get_string_size(crown_char, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := center - ts * 0.5
	pos.y += ts.y * 0.85
	draw_string(font, pos, crown_char, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_x(center: Vector2, half: float, color: Color) -> void:
	draw_line(center + Vector2(-half, -half), center + Vector2(half, half), color, 1.5)
	draw_line(center + Vector2(half, -half), center + Vector2(-half, half), color, 1.5)


## Flash all cells for win celebration
func flash_all(color: Color, duration: float) -> void:
	var original_modulate := modulate
	modulate = color
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_callback(func() -> void: modulate = original_modulate)

	if AppTheme.is_neon:
		var cs := _get_cell_size()
		var origin := _get_grid_origin()
		var center := origin + Vector2(cs * grid_size * 0.5, cs * grid_size * 0.5)
		EffectFactory.neon_burst(self, center, Color(1.5, 1.2, 0.0), 16, 1.5)
		AppTheme.screen_shake(8.0, 0.25)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var is_touch := DisplayServer.is_touchscreen_available()
	var pressed := false
	var released := false
	var pos := Vector2.ZERO
	var is_motion := false
	var motion_pos := Vector2.ZERO

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		pressed = st.pressed
		released = not st.pressed
		pos = st.position
	elif event is InputEventScreenDrag:
		is_motion = true
		motion_pos = (event as InputEventScreenDrag).position
	elif event is InputEventMouseButton and not is_touch:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pressed = mb.pressed
			released = not mb.pressed
			pos = mb.position
	elif event is InputEventMouseMotion and not is_touch:
		if _dragging:
			is_motion = true
			motion_pos = (event as InputEventMouseMotion).position

	if is_motion and _dragging:
		var cell := _pos_to_cell(motion_pos)
		if cell != _last_drag_cell:
			_last_drag_cell = cell
			if not _drag_cells.has(cell):
				_drag_cells.append(cell)
			queue_redraw()
		accept_event()
		return

	if pressed:
		var cell := _pos_to_cell(pos)
		if not _in_bounds(pos):
			return
		_dragging = true
		_drag_cells = [cell]
		_last_drag_cell = cell
		DragEffect.suppress()
		accept_event()

	elif released and _dragging:
		_dragging = false
		DragEffect.unsuppress()
		var final_cell := _pos_to_cell(pos)
		if not _drag_cells.has(final_cell):
			_drag_cells.append(final_cell)

		if _drag_cells.size() == 1:
			# Single tap
			cell_tapped.emit(_drag_cells[0])
		else:
			# Drag paint
			cells_dragged.emit(_drag_cells.duplicate())

		_drag_cells.clear()
		queue_redraw()
		accept_event()


func _in_bounds(local_pos: Vector2) -> bool:
	var origin := _get_grid_origin()
	var cs := _get_cell_size()
	var bounds := Rect2(origin, Vector2(cs * grid_size, cs * grid_size))
	return bounds.has_point(local_pos)
