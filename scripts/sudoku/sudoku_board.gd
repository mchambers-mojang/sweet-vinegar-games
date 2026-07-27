class_name SudokuBoard
extends Control

## The 9x9 Sudoku grid UI

signal cell_selected(index: int)

var cells: Array[SudokuCell] = []
var selected_index: int = -1
var show_row_col_box: bool = false
var filter_number: int = 0
var filter_color: Color = Color.TRANSPARENT

## Killer Sudoku cage data.  Array of { "cells": Array[int], "sum": int }.
## Empty when not in killer mode.
var cage_data: Array = []

## Lookup: cell_index → cage_index (-1 when not in killer mode).
var _cell_cage_map: Array[int] = []

const GRID_PADDING := 2.0
const THIN_LINE := 1.0
const THICK_LINE := 3.0
const CAGE_LINE := 1.5
const CAGE_DASH := 4.0
const CAGE_GAP := 3.0


func _ready() -> void:
	add_to_group("debug_grid_source")
	_create_cells()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: queue_redraw(); _redraw_cells())


func _create_cells() -> void:
	for i in 81:
		var cell := SudokuCell.new()
		cell.setup(i)
		cell.cell_pressed.connect(_on_cell_pressed)
		add_child(cell)
		cells.append(cell)


func _on_cell_pressed(index: int) -> void:
	selected_index = index
	cell_selected.emit(index)


func select_cell(index: int) -> void:
	selected_index = index
	_update_highlighting()


func _update_highlighting() -> void:
	var sel_row := selected_index / 9 if selected_index >= 0 else -1
	var sel_col := selected_index % 9 if selected_index >= 0 else -1
	var sel_box := (sel_row / 3) * 3 + sel_col / 3 if selected_index >= 0 else -1
	var sel_value := cells[selected_index].value if selected_index >= 0 else 0
	var sel_color: Color = cells[selected_index].cell_color if selected_index >= 0 else Color.TRANSPARENT

	for cell in cells:
		cell.set_selected(cell.index == selected_index)
		cell.set_highlighted(
			selected_index >= 0 and cell.index != selected_index and (
				cell.row == sel_row or cell.col == sel_col or cell.box == sel_box
			) and show_row_col_box
		)
		# Same-number: from selected cell or filter
		var show_same_num := false
		if filter_number != 0:
			show_same_num = cell.value == filter_number or filter_number in cell.pencil_marks
		elif selected_index >= 0 and sel_value != 0 and cell.value == sel_value and cell.index != selected_index:
			show_same_num = true
		cell.set_same_number(show_same_num)
		# Same-color: from selected cell or filter
		var show_same_col := false
		if filter_color != Color.TRANSPARENT:
			show_same_col = cell.cell_color == filter_color
		elif selected_index >= 0 and sel_color != Color.TRANSPARENT and cell.cell_color == sel_color and cell.index != selected_index:
			show_same_col = true
		cell.set_same_color(show_same_col)


func load_puzzle(puzzle: Array[int]) -> void:
	for i in 81:
		cells[i].pencil_marks.clear()
		cells[i].cell_color = Color.TRANSPARENT
		cells[i].is_error = false
		if puzzle[i] != 0:
			cells[i].set_value(puzzle[i], true)
		else:
			cells[i].value = 0
			cells[i].is_given = false
			cells[i].queue_redraw()
	selected_index = -1
	_update_highlighting()


func load_state(current_grid: Array[int], puzzle: Array[int], pencil_marks: Dictionary, cell_colors: Dictionary) -> void:
	for i in 81:
		var is_given := puzzle[i] != 0
		cells[i].is_given = is_given
		cells[i].value = current_grid[i]
		cells[i].pencil_marks.clear()
		cells[i].cell_color = Color.TRANSPARENT

		var key := str(i)
		if pencil_marks.has(key):
			var marks = pencil_marks[key]
			if marks is Array:
				for m in marks:
					cells[i].pencil_marks.append(int(m))
		if cell_colors.has(key):
			cells[i].cell_color = Color.from_string(str(cell_colors[key]), Color.TRANSPARENT)
		cells[i].queue_redraw()
	_update_highlighting()


func get_current_grid() -> Array[int]:
	var grid: Array[int] = []
	grid.resize(81)
	for i in 81:
		grid[i] = cells[i].value
	return grid


func get_pencil_marks_dict() -> Dictionary:
	var result := {}
	for i in 81:
		if cells[i].pencil_marks.size() > 0:
			result[str(i)] = cells[i].pencil_marks.duplicate()
	return result


func get_cell_colors_dict() -> Dictionary:
	var result := {}
	for i in 81:
		if cells[i].cell_color != Color.TRANSPARENT:
			result[str(i)] = cells[i].cell_color.to_html()
	return result


## Apply killer cage data.  Clears cage visuals when called with an empty array.
## cage_dicts: Array of { "cells": Array[int], "sum": int } or with optional "anchor": int.
## When "anchor" is absent it is computed as the minimum cell index in the cage.
func set_cages(cage_dicts: Array) -> void:
	cage_data = cage_dicts.duplicate(true)

	# Reset all anchor sums
	for cell in cells:
		cell.cage_anchor_sum = 0

	# Build cell → cage lookup and set anchor sum labels
	_cell_cage_map.resize(81)
	_cell_cage_map.fill(-1)
	for i in cage_data.size():
		var d: Dictionary = cage_data[i]
		var cage_cells = d.get("cells", [])
		var cage_sum: int = int(d.get("sum", 0))
		# Compute anchor as minimum cell index when not explicitly provided
		var anchor: int = -1
		if d.has("anchor"):
			anchor = int(d.get("anchor", -1))
		else:
			for c in cage_cells:
				var ci := int(c)
				if anchor < 0 or ci < anchor:
					anchor = ci
		for c in cage_cells:
			_cell_cage_map[c] = i
		if anchor >= 0 and anchor < cells.size():
			cells[anchor].cage_anchor_sum = cage_sum
			cells[anchor].queue_redraw()

	queue_redraw()


func _redraw_cells() -> void:
	for cell in cells:
		cell.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_cells()


## Precomputed pixel-snapped positions for each row and column
var _col_positions: Array[float] = []
var _row_positions: Array[float] = []
var _cell_w: float = 0.0
var _cell_h: float = 0.0
var _grid_rect: Rect2 = Rect2()


func _calc_and_cache_layout() -> void:
	var available := size
	var grid_px := floori(minf(available.x, available.y))

	# Integer line widths
	var thick := int(THICK_LINE)
	var thin := int(THIN_LINE)

	# Total line pixels: 4 thick + 6 thin
	var total_lines := 4 * thick + 6 * thin
	var cell_px := (grid_px - total_lines) / 9  # integer cell size
	var actual_grid := cell_px * 9 + total_lines

	var ox := floori((available.x - actual_grid) / 2.0)
	var oy := floori((available.y - actual_grid) / 2.0)

	_cell_w = float(cell_px)
	_cell_h = float(cell_px)
	_grid_rect = Rect2(Vector2(ox, oy), Vector2(actual_grid, actual_grid))

	# Build position arrays — each entry is the pixel X or Y where that cell starts
	_col_positions.clear()
	_row_positions.clear()

	var x := ox + thick  # Start after left border
	for c in 9:
		_col_positions.append(float(x))
		x += cell_px
		if (c + 1) % 3 == 0:
			x += thick  # Thick line after every 3rd cell
		else:
			x += thin

	var y := oy + thick  # Start after top border
	for r in 9:
		_row_positions.append(float(y))
		y += cell_px
		if (r + 1) % 3 == 0:
			y += thick
		else:
			y += thin


func _layout_cells() -> void:
	if cells.is_empty():
		return
	_calc_and_cache_layout()

	for i in 81:
		var r := i / 9
		var c := i % 9
		cells[i].position = Vector2(_col_positions[c], _row_positions[r])
		cells[i].size = Vector2(_cell_w, _cell_h)

	queue_redraw()


func get_cell_rect(index: int) -> Rect2:
	var r := index / 9
	var c := index % 9
	if c < _col_positions.size() and r < _row_positions.size():
		return Rect2(Vector2(_col_positions[c], _row_positions[r]), Vector2(_cell_w, _cell_h))
	return Rect2()


func debug_screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var local_pos := screen_pos - global_position
	if not _grid_rect.has_point(local_pos):
		return Vector2i(-1, -1)

	var col := -1
	var row := -1
	for i in _col_positions.size():
		if local_pos.x >= _col_positions[i] and local_pos.x < _col_positions[i] + _cell_w:
			col = i
			break
	for i in _row_positions.size():
		if local_pos.y >= _row_positions[i] and local_pos.y < _row_positions[i] + _cell_h:
			row = i
			break

	if col < 0 or row < 0:
		return Vector2i(-1, -1)
	return Vector2i(col, row)


func _draw() -> void:
	if cells.is_empty() or _col_positions.is_empty():
		return

	var tm := AppTheme
	var thin_color := tm.get_color("grid_line_thin")
	var thick_color := tm.get_color("grid_line_thick")
	var neon_mode := tm.is_neon

	var ox := _grid_rect.position.x
	var oy := _grid_rect.position.y
	var gw := _grid_rect.size.x
	var gh := _grid_rect.size.y
	var thick := THICK_LINE
	var thin := THIN_LINE

	# Fill entire grid rect with thick color (outer border + box dividers show through)
	draw_rect(_grid_rect, thick_color)

	# Draw thin lines between cells within each box
	for r in range(1, 9):
		if r % 3 == 0:
			continue
		var y := _row_positions[r] - thin
		draw_rect(Rect2(Vector2(ox, y), Vector2(gw, thin)), thin_color)

	for c in range(1, 9):
		if c % 3 == 0:
			continue
		var x := _col_positions[c] - thin
		draw_rect(Rect2(Vector2(x, oy), Vector2(thin, gh)), thin_color)

	# Killer Sudoku: dashed cage outlines drawn on top of cell backgrounds
	if not cage_data.is_empty() and not _cell_cage_map.is_empty():
		_draw_cage_outlines(neon_mode)

	# Neon outer glow
	if neon_mode:
		var glow := Color(thick_color.r * 0.4, thick_color.g * 0.4, thick_color.b * 0.4, 0.25)
		draw_rect(Rect2(Vector2(ox - 3, oy - 3), Vector2(gw + 6, gh + 6)), glow, false, 6.0)


## Draw dashed outlines along cage boundaries.
## An edge is drawn where adjacent cells belong to different cages (or at board edge).
func _draw_cage_outlines(neon_mode: bool) -> void:
	var tm := AppTheme
	var cage_color: Color
	if neon_mode:
		cage_color = Color(0.0, 1.2, 1.0, 0.85)
	else:
		var thick_color := tm.get_color("grid_line_thick")
		# Blend between thick grid color and a warm tint for visibility
		cage_color = thick_color.lerp(Color(0.35, 0.45, 0.75), 0.45)
		cage_color.a = 0.90

	var margin := 2.0  # inset from cell edge so cage lines don't overlap grid lines

	for i in 81:
		var ci: int = _cell_cage_map[i]
		var r := i / 9
		var c := i % 9

		var cx := _col_positions[c]
		var cy := _row_positions[r]
		var cw := _cell_w
		var ch := _cell_h

		# Check each of the 4 edges: top, bottom, left, right
		# Top edge (between row r-1 and row r)
		var top_nb := (r - 1) * 9 + c
		if r == 0 or _cell_cage_map[top_nb] != ci:
			draw_dashed_line(
				Vector2(cx + margin, cy),
				Vector2(cx + cw - margin, cy),
				cage_color, CAGE_LINE, CAGE_DASH)

		# Bottom edge (between row r and row r+1)
		var bot_nb := (r + 1) * 9 + c
		if r == 8 or _cell_cage_map[bot_nb] != ci:
			draw_dashed_line(
				Vector2(cx + margin, cy + ch),
				Vector2(cx + cw - margin, cy + ch),
				cage_color, CAGE_LINE, CAGE_DASH)

		# Left edge (between col c-1 and col c)
		var left_nb := r * 9 + (c - 1)
		if c == 0 or _cell_cage_map[left_nb] != ci:
			draw_dashed_line(
				Vector2(cx, cy + margin),
				Vector2(cx, cy + ch - margin),
				cage_color, CAGE_LINE, CAGE_DASH)

		# Right edge (between col c and col c+1)
		var right_nb := r * 9 + (c + 1)
		if c == 8 or _cell_cage_map[right_nb] != ci:
			draw_dashed_line(
				Vector2(cx + cw, cy + margin),
				Vector2(cx + cw, cy + ch - margin),
				cage_color, CAGE_LINE, CAGE_DASH)
