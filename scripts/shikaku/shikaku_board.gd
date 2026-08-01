class_name ShikakuBoard
extends Control

## The Shikaku grid UI — draws grid lines, anchors (area/shape clues), and placed rectangles.
## Accepts generalized anchor dictionaries { Vector2i -> {area: int, shape: int} }
## as well as legacy numbers dictionaries { Vector2i -> int } (auto-converted).

signal rectangle_placed(rect: Rect2i)
signal rectangle_tapped(index: int)

var grid_width: int = 10
var grid_height: int = 10
## Primary anchor storage: { Vector2i -> {area: int, shape: int} }
var anchors: Dictionary = {}
var placed_rects: Array[Rect2i] = []
var rect_colors: Array[Color] = []
## Parallel flag array: true when the rect at the same index is a wrong placement.
var rect_is_wrong: Array[bool] = []

## Backward-compat computed property: { Vector2i -> int } for area-carrying anchors.
var numbers: Dictionary:
	get:
		var nums: Dictionary = {}
		for pos in anchors:
			var a: Dictionary = anchors[pos]
			var area: int = int(a.get("area", 0))
			if area > 0:
				nums[pos] = area
		return nums

# Drag state
var _dragging: bool = false
var _drag_start: Vector2i = Vector2i(-1, -1)
var _drag_end: Vector2i = Vector2i(-1, -1)
var _drag_preview: Rect2i = Rect2i()

# Drawing constants
const LINE_WIDTH := 1.0
const BORDER_WIDTH := 2.0
const RECT_BORDER := 2.0
## Highlight color for wrong (contradiction) placements.
const ERROR_COLOR := Color(1.0, 0.35, 0.35, 0.45)

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
## Static tooltip text describing all anchors, set at setup time for screen readers.
var _full_anchor_description: String = ""


func _ready() -> void:
	add_to_group("debug_grid_source")
	mouse_filter = Control.MOUSE_FILTER_STOP


## Set up the board with generalized anchors or a legacy numbers dict.
## a: { Vector2i -> {area, shape} }  OR  { Vector2i -> int }  (auto-detected)
func setup(w: int, h: int, a: Dictionary) -> void:
	grid_width = w
	grid_height = h
	anchors = _normalize_anchors(a)
	placed_rects.clear()
	rect_colors.clear()
	rect_is_wrong.clear()
	_color_index = 0
	# Build a static description of all anchor clues and set it as tooltip_text
	# so screen readers can access the full clue set without requiring mouse hover.
	_full_anchor_description = _build_anchor_description()
	tooltip_text = _full_anchor_description
	queue_redraw()


## Convert legacy { Vector2i -> int } or mixed dicts to { Vector2i -> {area, shape} }.
func _normalize_anchors(a: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for pos in a.keys():
		var val = a[pos]
		if val is Dictionary:
			result[pos] = val
		elif val is int or val is float:
			result[pos] = {"area": int(val), "shape": ShikakuLogic.SHAPE_ABSENT}
	return result


## Build a human-readable description of all anchor clues for screen-reader accessibility.
func _build_anchor_description() -> String:
	var parts: PackedStringArray = []
	for pos in anchors.keys():
		var anchor: Dictionary = anchors[pos]
		var area: int = int(anchor.get("area", 0))
		var shape: int = int(anchor.get("shape", ShikakuLogic.SHAPE_ABSENT))
		var shape_name: String = str(ShikakuLogic.SHAPE_NAMES.get(shape, ""))
		var desc: String
		if area > 0 and shape != ShikakuLogic.SHAPE_ABSENT:
			desc = "%s, %d cells at (%d,%d)" % [shape_name, area, pos.x, pos.y]
		elif area > 0:
			desc = "%d cells at (%d,%d)" % [area, pos.x, pos.y]
		elif shape != ShikakuLogic.SHAPE_ABSENT:
			desc = "%s at (%d,%d)" % [shape_name, pos.x, pos.y]
		else:
			continue
		parts.append(desc)
	return "; ".join(parts)


## Mark which placed rects are wrong (not in the solution).
## Call this after any board state change to refresh the contradiction display.
func refresh_error_state(wrong_rects: Array[Rect2i]) -> void:
	rect_is_wrong.resize(placed_rects.size())
	for i in placed_rects.size():
		rect_is_wrong[i] = wrong_rects.has(placed_rects[i])
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


func get_cell_screen_rect(col: int, row: int) -> Rect2:
	var cell_size := _get_cell_size()
	var origin := _get_grid_origin()
	return Rect2(origin + Vector2(col * cell_size, row * cell_size), Vector2(cell_size, cell_size))


func get_cell_center(col: int, row: int) -> Vector2:
	return get_cell_screen_rect(col, row).get_center()


func screen_to_grid(local_pos: Vector2) -> Vector2i:
	return _pos_to_cell(local_pos)


func _pos_to_cell(pos: Vector2) -> Vector2i:
	var origin := _get_grid_origin()
	var cell_size := _get_cell_size()
	var col := int((pos.x - origin.x) / cell_size)
	var row := int((pos.y - origin.y) / cell_size)
	col = clampi(col, 0, grid_width - 1)
	row = clampi(row, 0, grid_height - 1)
	return Vector2i(col, row)


func debug_screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var local_pos := screen_pos - global_position
	var origin := _get_grid_origin()
	var cell_size := _get_cell_size()
	var bounds := Rect2(origin, Vector2(cell_size * grid_width, cell_size * grid_height))
	if not bounds.has_point(local_pos):
		return Vector2i(-1, -1)
	return _pos_to_cell(local_pos)


func _gui_input(event: InputEvent) -> void:
	var touch_event: bool = false
	var pressed: bool = false
	var released: bool = false
	var pos := Vector2.ZERO
	var is_touch := DisplayServer.is_touchscreen_available()

	if event is InputEventScreenTouch:
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
	elif event is InputEventMouseButton and not is_touch:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			touch_event = true
			pressed = mb.pressed
			released = not mb.pressed
			pos = mb.position
	elif event is InputEventMouseMotion and not is_touch:
		var mm := event as InputEventMouseMotion
		_update_anchor_tooltip(mm.position)
		if _dragging:
			_drag_end = _pos_to_cell(mm.position)
			_update_drag_preview()
			queue_redraw()
			accept_event()
		return

	if not touch_event:
		return

	if pressed:
		var cell := _pos_to_cell(pos)
		var tapped_idx := _find_rect_at(cell)
		if tapped_idx >= 0:
			rectangle_tapped.emit(tapped_idx)
			accept_event()
			return
		_dragging = true
		_drag_start = cell
		_drag_end = cell
		DragEffect.suppress()
		_update_drag_preview()
		queue_redraw()
		accept_event()
	elif released and _dragging:
		_dragging = false
		DragEffect.unsuppress()
		_drag_end = _pos_to_cell(pos)
		_update_drag_preview()
		if _drag_preview.size.x > 0 and _drag_preview.size.y > 0:
			if _drag_preview.size.x > 1 or _drag_preview.size.y > 1 or not is_touch:
				rectangle_placed.emit(_drag_preview)
		_drag_preview = Rect2i()
		queue_redraw()
		accept_event()


func _find_rect_at(cell: Vector2i) -> int:
	for i in range(placed_rects.size() - 1, -1, -1):
		if placed_rects[i].has_point(cell):
			return i
	return -1


## Update tooltip_text to describe the anchor clue (if any) under [param screen_pos].
## Falls back to the full board description when not hovering over a clue cell,
## so screen readers always have an accessible representation of all anchors.
func _update_anchor_tooltip(screen_pos: Vector2) -> void:
	var cell := _pos_to_cell(screen_pos)
	var anchor = anchors.get(cell, null)
	if anchor == null:
		tooltip_text = _full_anchor_description
		return
	var area: int = int((anchor as Dictionary).get("area", 0))
	var shape: int = int((anchor as Dictionary).get("shape", ShikakuLogic.SHAPE_ABSENT))
	var shape_name: String = str(ShikakuLogic.SHAPE_NAMES.get(shape, ""))
	if area > 0 and shape != ShikakuLogic.SHAPE_ABSENT:
		tooltip_text = "%s, %d cells" % [shape_name, area]
	elif area > 0:
		tooltip_text = "%d cells" % area
	elif shape != ShikakuLogic.SHAPE_ABSENT:
		tooltip_text = shape_name
	else:
		tooltip_text = _full_anchor_description


func _update_drag_preview() -> void:
	var min_c := mini(_drag_start.x, _drag_end.x)
	var max_c := maxi(_drag_start.x, _drag_end.x)
	var min_r := mini(_drag_start.y, _drag_end.y)
	var max_r := maxi(_drag_start.y, _drag_end.y)
	_drag_preview = Rect2i(min_c, min_r, max_c - min_c + 1, max_r - min_r + 1)


func add_rect(rect: Rect2i) -> void:
	placed_rects.append(rect)
	rect_colors.append(PALETTE[_color_index % PALETTE.size()])
	rect_is_wrong.append(false)
	_color_index += 1
	queue_redraw()


func remove_rect(index: int) -> void:
	if index >= 0 and index < placed_rects.size():
		placed_rects.remove_at(index)
		rect_colors.remove_at(index)
		if index < rect_is_wrong.size():
			rect_is_wrong.remove_at(index)
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
	var tm := AppTheme
	var bg_color := tm.get_color("cell_background")
	var line_color := tm.get_color("text_given")
	var grid_rect := Rect2(origin, Vector2(cell_size * grid_width, cell_size * grid_height))

	# Background
	draw_rect(grid_rect, bg_color)

	# Placed rectangles (fill)
	for i in range(placed_rects.size()):
		var rect := placed_rects[i]
		var color: Color
		if i < rect_is_wrong.size() and rect_is_wrong[i]:
			color = ERROR_COLOR
		else:
			color = rect_colors[i]
		var draw_rect_pos := origin + Vector2(rect.position.x * cell_size, rect.position.y * cell_size)
		var draw_rect_size := Vector2(rect.size.x * cell_size, rect.size.y * cell_size)
		draw_rect(Rect2(draw_rect_pos, draw_rect_size), color)

	# Placed rectangles (border)
	var neon_mode := tm.is_neon
	for i in range(placed_rects.size()):
		var border_rect := placed_rects[i]
		var border_color := rect_colors[i]
		border_color.a = 0.9
		if neon_mode:
			border_color = Color(border_color.r * 3.0, border_color.g * 3.0, border_color.b * 3.0, 0.9)
		var border_rect_pos := origin + Vector2(border_rect.position.x * cell_size, border_rect.position.y * cell_size)
		var border_rect_size := Vector2(border_rect.size.x * cell_size, border_rect.size.y * cell_size)
		var bw := RECT_BORDER if not neon_mode else 1.5
		draw_rect(Rect2(border_rect_pos, Vector2(border_rect_size.x, bw)), border_color)
		draw_rect(Rect2(border_rect_pos + Vector2(0, border_rect_size.y - bw), Vector2(border_rect_size.x, bw)), border_color)
		draw_rect(Rect2(border_rect_pos, Vector2(bw, border_rect_size.y)), border_color)
		draw_rect(Rect2(border_rect_pos + Vector2(border_rect_size.x - bw, 0), Vector2(bw, border_rect_size.y)), border_color)
		if neon_mode:
			var border_glow := Color(border_color.r * 0.3, border_color.g * 0.3, border_color.b * 0.3, 0.25)
			draw_rect(Rect2(border_rect_pos - Vector2(2, 2), border_rect_size + Vector2(4, 4)), border_glow, false, 3.0)

	# Drag preview
	if _dragging and _drag_preview.size.x > 0:
		var preview_pos := origin + Vector2(_drag_preview.position.x * cell_size, _drag_preview.position.y * cell_size)
		var preview_size := Vector2(_drag_preview.size.x * cell_size, _drag_preview.size.y * cell_size)
		var preview_color := Color(0.5, 0.8, 1.0, 0.25)
		draw_rect(Rect2(preview_pos, preview_size), preview_color)
		var pb := Color(0.5, 0.8, 1.0, 0.7)
		draw_rect(Rect2(preview_pos, Vector2(preview_size.x, 2)), pb)
		draw_rect(Rect2(preview_pos + Vector2(0, preview_size.y - 2), Vector2(preview_size.x, 2)), pb)
		draw_rect(Rect2(preview_pos, Vector2(2, preview_size.y)), pb)
		draw_rect(Rect2(preview_pos + Vector2(preview_size.x - 2, 0), Vector2(2, preview_size.y)), pb)

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

	# Border
	var border_col := line_color
	if neon_mode:
		border_col = Color(0.0, 1.5, 1.5)
	draw_rect(grid_rect, border_col, false, BORDER_WIDTH)
	if neon_mode:
		var outline_glow := Color(0.0, 0.6, 0.6, 0.25)
		draw_rect(Rect2(origin - Vector2(3, 3), Vector2(cell_size * grid_width + 6, cell_size * grid_height + 6)), outline_glow, false, 5.0)

	# Anchor clues (area numbers and/or shape icons)
	var font := ThemeDB.fallback_font
	var text_color := tm.get_color("text_given")
	for pos in anchors.keys():
		var anchor: Dictionary = anchors[pos]
		var anchor_area: int = int(anchor.get("area", 0))
		var anchor_shape: int = int(anchor.get("shape", ShikakuLogic.SHAPE_ABSENT))
		var has_area := anchor_area > 0
		var has_shape := anchor_shape != ShikakuLogic.SHAPE_ABSENT
		var cell_origin := origin + Vector2(pos.x * cell_size, pos.y * cell_size)

		if has_area and not has_shape:
			# Area only: full-size number centered in cell.
			var font_size := int(cell_size * 0.55)
			var text := str(anchor_area)
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos := cell_origin + (Vector2(cell_size, cell_size) - text_size) / 2.0
			text_pos.y += text_size.y * 0.85
			draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
		elif has_shape and not has_area:
			# Shape only: large shape icon centered in cell.
			var font_size := int(cell_size * 0.55)
			var icon := str(ShikakuLogic.SHAPE_ICONS.get(anchor_shape, "?"))
			var text_size := font.get_string_size(icon, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos := cell_origin + (Vector2(cell_size, cell_size) - text_size) / 2.0
			text_pos.y += text_size.y * 0.85
			draw_string(font, text_pos, icon, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
		elif has_area and has_shape:
			# Both: area number in top half, shape icon in bottom half (smaller font).
			var font_size := int(cell_size * 0.38)
			var area_text := str(anchor_area)
			var shape_icon := str(ShikakuLogic.SHAPE_ICONS.get(anchor_shape, "?"))
			# Area number (upper portion of cell)
			var area_size := font.get_string_size(area_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var area_pos := cell_origin + Vector2((cell_size - area_size.x) / 2.0, cell_size * 0.05)
			area_pos.y += area_size.y
			draw_string(font, area_pos, area_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
			# Shape icon (lower portion of cell)
			var icon_size := font.get_string_size(shape_icon, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var icon_pos := cell_origin + Vector2((cell_size - icon_size.x) / 2.0, cell_size * 0.52)
			icon_pos.y += icon_size.y
			draw_string(font, icon_pos, shape_icon, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


## Flash all cells for win celebration
func flash_all(color: Color, duration: float) -> void:
	var original_modulate := modulate
	modulate = Color(1.2, 1.1, 0.8)

	if AppTheme.is_neon:
		var cell_size := _get_cell_size()
		var origin := _get_grid_origin()
		for i in range(placed_rects.size()):
			var rect := placed_rects[i]
			var center := origin + Vector2(
				(rect.position.x + rect.size.x / 2.0) * cell_size,
				(rect.position.y + rect.size.y / 2.0) * cell_size
			)
			var rc: Color = rect_colors[i] if i < rect_colors.size() else Color(0.0, 1.5, 1.5)
			EffectFactory.neon_burst(self, center, rc, 12, 1.2)
		AppTheme.screen_shake(8.0, 0.25)

	var t := create_tween()
	t.tween_interval(duration)
	t.tween_callback(func() -> void: modulate = original_modulate)
