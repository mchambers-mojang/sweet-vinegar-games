class_name BlockudokuBoard
extends Control

## 9x9 Blockudoku grid — draws cells, placed blocks, previews, and handles clears

signal cells_cleared(count: int, lines: int, boxes: int, is_combo: bool)
signal block_placed

const GRID_SIZE := 9
const BOX_SIZE := 3
const LINE_WIDTH := 1.0
const BORDER_WIDTH := 2.0
const BOX_LINE_WIDTH := 2.0

## Grid state: 0 = empty, 1 = filled
var grid: Array[int] = []

## Color for each filled cell (for visual variety)
var cell_colors: Array[Color] = []

## Preview state
var preview_cells: Array[Vector2i] = []
var preview_valid: bool = false

## Flash animation
var _flash_cells: Array[Vector2i] = []
var _flash_alpha: float = 0.0
var _clear_anim_cells: Array[Vector2i] = []
var _clear_anim_colors: Array[Color] = []
var _clear_anim_delays: Array[float] = []
var _clear_anim_elapsed: float = 0.0
var _clear_anim_tween: Tween = null
var is_clear_animating: bool = false

const CLEAR_FLASH_DURATION := 0.1
const CLEAR_SWEEP_DURATION := 0.26
const CLEAR_CELL_DELAY_MAX := 0.12
const MIN_SWEEP_DURATION := 0.001
const INVALID_CLEAR_DELAY := CLEAR_CELL_DELAY_MAX + 1.0

## Color palette for placed blocks
const PALETTE: Array[Color] = [
	Color(0.45, 0.7, 0.95),    # Blue
	Color(0.95, 0.6, 0.45),    # Orange
	Color(0.55, 0.85, 0.55),   # Green
	Color(0.9, 0.5, 0.5),      # Red
	Color(0.7, 0.55, 0.9),     # Purple
	Color(0.95, 0.85, 0.4),    # Yellow
	Color(0.45, 0.85, 0.8),    # Teal
	Color(0.9, 0.6, 0.75),     # Pink
]
var _color_index: int = 0


func _get_sweep_duration() -> float:
	return maxf(CLEAR_SWEEP_DURATION, MIN_SWEEP_DURATION)


func _ready() -> void:
	add_to_group("debug_grid_source")
	mouse_filter = Control.MOUSE_FILTER_STOP
	_init_grid()


func _init_grid() -> void:
	grid.resize(GRID_SIZE * GRID_SIZE)
	grid.fill(0)
	cell_colors.resize(GRID_SIZE * GRID_SIZE)
	for i in cell_colors.size():
		cell_colors[i] = Color.TRANSPARENT


func reset() -> void:
	_init_grid()
	_color_index = 0
	preview_cells.clear()
	_flash_cells.clear()
	if _clear_anim_tween and _clear_anim_tween.is_running():
		_clear_anim_tween.kill()
	_clear_anim_cells.clear()
	_clear_anim_colors.clear()
	_clear_anim_delays.clear()
	_clear_anim_elapsed = 0.0
	is_clear_animating = false
	queue_redraw()


func _get_cell_size() -> float:
	# Use the smaller dimension so the grid always fits, and leave room for siblings
	var available := minf(size.x, size.y) - BORDER_WIDTH * 2
	# Also cap to the viewport height minus space for top bar + tray (~200px)
	var viewport_h := get_viewport_rect().size.y
	var max_grid := viewport_h - 200.0
	available = minf(available, max_grid)
	return available / GRID_SIZE


func _get_grid_origin() -> Vector2:
	var cell_size := _get_cell_size()
	var grid_px := cell_size * GRID_SIZE
	return Vector2((size.x - grid_px) / 2.0, (size.y - grid_px) / 2.0)


func can_place(shape: Array, grid_col: int, grid_row: int) -> bool:
	for cell in shape:
		var c: Vector2i = cell
		var col := grid_col + c.x
		var row := grid_row + c.y
		if col < 0 or col >= GRID_SIZE or row < 0 or row >= GRID_SIZE:
			return false
		if grid[row * GRID_SIZE + col] != 0:
			return false
	return true


func place_block(shape: Array, grid_col: int, grid_row: int, color: Color = Color(-1, -1, -1)) -> void:
	if color.r < 0:
		color = PALETTE[_color_index % PALETTE.size()]
	_color_index += 1
	for cell in shape:
		var c: Vector2i = cell
		var col := grid_col + c.x
		var row := grid_row + c.y
		grid[row * GRID_SIZE + col] = 1
		cell_colors[row * GRID_SIZE + col] = color
	block_placed.emit()
	queue_redraw()


func check_and_clear() -> Dictionary:
	var rows_to_clear: Array[int] = []
	var cols_to_clear: Array[int] = []
	var boxes_to_clear: Array[Vector2i] = []  # top-left of each 3x3 box

	# Check rows
	for r in GRID_SIZE:
		var full := true
		for c in GRID_SIZE:
			if grid[r * GRID_SIZE + c] == 0:
				full = false
				break
		if full:
			rows_to_clear.append(r)

	# Check columns
	for c in GRID_SIZE:
		var full := true
		for r in GRID_SIZE:
			if grid[r * GRID_SIZE + c] == 0:
				full = false
				break
		if full:
			cols_to_clear.append(c)

	# Check 3x3 boxes
	for box_r in range(0, GRID_SIZE, BOX_SIZE):
		for box_c in range(0, GRID_SIZE, BOX_SIZE):
			var full := true
			for r in range(box_r, box_r + BOX_SIZE):
				for c in range(box_c, box_c + BOX_SIZE):
					if grid[r * GRID_SIZE + c] == 0:
						full = false
						break
				if not full:
					break
			if full:
				boxes_to_clear.append(Vector2i(box_c, box_r))

	if rows_to_clear.is_empty() and cols_to_clear.is_empty() and boxes_to_clear.is_empty():
		return {"cleared": 0, "lines": 0, "boxes": 0}

	# Collect all cells to clear (use a set to avoid duplicates)
	var clear_set := {}
	for r in rows_to_clear:
		for c in GRID_SIZE:
			clear_set[Vector2i(c, r)] = true
	for c in cols_to_clear:
		for r in GRID_SIZE:
			clear_set[Vector2i(c, r)] = true
	for box_pos in boxes_to_clear:
		for r in range(box_pos.y, box_pos.y + BOX_SIZE):
			for c in range(box_pos.x, box_pos.x + BOX_SIZE):
				clear_set[Vector2i(c, r)] = true

	# Flash then clear
	_flash_cells.clear()
	var _flash_saved_colors: Array[Color] = []
	for key in clear_set.keys():
		var p: Vector2i = key
		_flash_cells.append(p)
		_flash_saved_colors.append(cell_colors[p.y * GRID_SIZE + p.x])

	# Spawn neon effects before clearing
	if ThemeManager.is_neon and SettingsManager.particle_effects_enabled:
		var cell_size := _get_cell_size()
		var origin := _get_grid_origin()

		# Glass shatter on each cleared cell
		for i in _flash_cells.size():
			var p: Vector2i = _flash_cells[i]
			var cell_rect := Rect2(
				origin + Vector2(p.x * cell_size, p.y * cell_size),
				Vector2(cell_size, cell_size)
			)
			var shard_color := _flash_saved_colors[i] if i < _flash_saved_colors.size() else Color(0.0, 1.5, 1.5)
			GlassShatter.create(self, cell_rect, shard_color, 4)

		# Sweep effects on cleared rows
		for r in rows_to_clear:
			var sweep_rect := Rect2(
				origin + Vector2(0, r * cell_size),
				Vector2(GRID_SIZE * cell_size, cell_size)
			)
			NeonSweep.create(self, sweep_rect, true, Color(0.0, 2.0, 1.5))

		# Sweep effects on cleared columns
		for c in cols_to_clear:
			var sweep_rect := Rect2(
				origin + Vector2(c * cell_size, 0),
				Vector2(cell_size, GRID_SIZE * cell_size)
			)
			NeonSweep.create(self, sweep_rect, false, Color(2.0, 0.3, 1.8))

		# Burst on cleared boxes
		for box_pos in boxes_to_clear:
			var center := origin + Vector2(
				(box_pos.x + BOX_SIZE / 2.0) * cell_size,
				(box_pos.y + BOX_SIZE / 2.0) * cell_size
			)
			NeonBurst.create(self, center, Color(1.5, 0.2, 1.0), 24, 1.5)

		# Shockwave from center of cleared area
		var all_x := 0.0
		var all_y := 0.0
		for p in _flash_cells:
			all_x += p.x + 0.5
			all_y += p.y + 0.5
		var clear_center := origin + Vector2(
			(all_x / _flash_cells.size()) * cell_size,
			(all_y / _flash_cells.size()) * cell_size
		)
		NeonRing.create(self, clear_center, Color(0.0, 2.0, 1.5), cell_size * 5.0, 0.4)

		# Screen shake
		NeonFxManager.screen_shake(6.0, 0.2)

	# Clear grid state immediately so game-over checks see the updated board
	for p in _flash_cells:
		grid[p.y * GRID_SIZE + p.x] = 0
		cell_colors[p.y * GRID_SIZE + p.x] = Color.TRANSPARENT

	# Animate flash overlay
	_flash_alpha = 1.0
	_clear_anim_cells = _flash_cells.duplicate()
	_clear_anim_colors = _flash_saved_colors.duplicate()
	_clear_anim_delays.clear()
	for pos in _clear_anim_cells:
		_clear_anim_delays.append(_compute_clear_cell_delay(pos, rows_to_clear, cols_to_clear))
	_clear_anim_elapsed = 0.0
	is_clear_animating = true
	var sweep_duration := _get_sweep_duration()
	if _clear_anim_tween and _clear_anim_tween.is_running():
		_clear_anim_tween.kill()
	_clear_anim_tween = create_tween()
	_clear_anim_tween.tween_method(_set_flash_alpha, 1.0, 0.0, CLEAR_FLASH_DURATION)
	_clear_anim_tween.tween_method(_set_clear_anim_elapsed, 0.0, sweep_duration, sweep_duration)
	_clear_anim_tween.tween_callback(func() -> void:
		_flash_cells.clear()
		_clear_anim_cells.clear()
		_clear_anim_colors.clear()
		_clear_anim_delays.clear()
		_clear_anim_elapsed = 0.0
		is_clear_animating = false
		queue_redraw()
	)

	queue_redraw()

	var lines := rows_to_clear.size() + cols_to_clear.size()
	var boxes := boxes_to_clear.size()
	return {"cleared": clear_set.size(), "lines": lines, "boxes": boxes}


func _set_flash_alpha(alpha: float) -> void:
	_flash_alpha = alpha
	queue_redraw()


func _set_clear_anim_elapsed(elapsed: float) -> void:
	_clear_anim_elapsed = elapsed
	queue_redraw()


func _compute_clear_cell_delay(p: Vector2i, rows_to_clear: Array[int], cols_to_clear: Array[int]) -> float:
	var has_row := rows_to_clear.has(p.y)
	var has_col := cols_to_clear.has(p.x)

	var row_delay := INVALID_CLEAR_DELAY
	if has_row:
		row_delay = (float(p.x) / float(max(1, GRID_SIZE - 1))) * CLEAR_CELL_DELAY_MAX

	var col_delay := INVALID_CLEAR_DELAY
	if has_col:
		col_delay = (float(p.y) / float(max(1, GRID_SIZE - 1))) * CLEAR_CELL_DELAY_MAX

	if has_row or has_col:
		return minf(row_delay, col_delay)
	var diag_norm := float(p.x + p.y) / float(max(1, (GRID_SIZE - 1) * 2))
	return diag_norm * CLEAR_CELL_DELAY_MAX


func show_preview(shape: Array, grid_col: int, grid_row: int) -> void:
	preview_cells.clear()
	preview_valid = can_place(shape, grid_col, grid_row)
	for cell in shape:
		var c: Vector2i = cell
		preview_cells.append(Vector2i(grid_col + c.x, grid_row + c.y))
	queue_redraw()


func clear_preview() -> void:
	preview_cells.clear()
	queue_redraw()


## Check if any of the given shapes can be placed anywhere on the board
func has_valid_placement(shapes: Array) -> bool:
	for shape in shapes:
		for r in GRID_SIZE:
			for c in GRID_SIZE:
				if can_place(shape, c, r):
					return true
	return false


func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var origin := _get_grid_origin()
	var cell_size := _get_cell_size()
	var col := int((screen_pos.x - origin.x) / cell_size)
	var row := int((screen_pos.y - origin.y) / cell_size)
	return Vector2i(col, row)


func debug_screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var local_pos := to_local(screen_pos)
	var origin := _get_grid_origin()
	var cell_size := _get_cell_size()
	var grid_px := cell_size * GRID_SIZE
	var bounds := Rect2(origin, Vector2(grid_px, grid_px))
	if not bounds.has_point(local_pos):
		return Vector2i(-1, -1)
	var col := int((local_pos.x - origin.x) / cell_size)
	var row := int((local_pos.y - origin.y) / cell_size)
	return Vector2i(col, row)


func get_filled_count() -> int:
	var count := 0
	for cell in grid:
		if cell != 0:
			count += 1
	return count


func get_state() -> Dictionary:
	return {
		"grid": grid.duplicate(),
		"cell_colors": _serialize_colors(),
		"color_index": _color_index,
	}


func set_state(state: Dictionary) -> void:
	grid = state.get("grid", [])
	if grid.size() != GRID_SIZE * GRID_SIZE:
		_init_grid()
	else:
		_deserialize_colors(state.get("cell_colors", []))
	_color_index = state.get("color_index", 0)
	if _clear_anim_tween and _clear_anim_tween.is_running():
		_clear_anim_tween.kill()
	_flash_cells.clear()
	_clear_anim_cells.clear()
	_clear_anim_colors.clear()
	_clear_anim_delays.clear()
	_clear_anim_elapsed = 0.0
	is_clear_animating = false
	queue_redraw()


func _serialize_colors() -> Array[String]:
	var result: Array[String] = []
	for c in cell_colors:
		result.append(c.to_html())
	return result


func _deserialize_colors(data: Array) -> void:
	cell_colors.resize(GRID_SIZE * GRID_SIZE)
	for i in mini(data.size(), cell_colors.size()):
		cell_colors[i] = Color.from_string(str(data[i]), Color.TRANSPARENT)
	for i in range(data.size(), cell_colors.size()):
		cell_colors[i] = Color.TRANSPARENT


## Flash placed cells white-hot then settle to placed color
func flash_placed_cells(shape: Array, grid_col: int, grid_row: int, color: Color) -> void:
	var positions: Array[Vector2i] = []
	for cell in shape:
		var co: Vector2i = cell
		positions.append(Vector2i(grid_col + co.x, grid_row + co.y))
	_flash_cells = positions
	_flash_alpha = 1.0
	# Tween the flash down
	var t := create_tween()
	t.tween_method(func(a: float) -> void:
		_flash_alpha = a
		queue_redraw()
	, 1.0, 0.0, 0.3)
	t.tween_callback(func() -> void:
		_flash_cells.clear()
		queue_redraw()
	)


func _draw() -> void:
	var cell_size := _get_cell_size()
	var origin := _get_grid_origin()
	var tm := ThemeManager
	var bg_color := tm.get_color("cell_background")
	var grid_px := cell_size * GRID_SIZE
	var grid_rect := Rect2(origin, Vector2(grid_px, grid_px))

	# Background
	draw_rect(grid_rect, bg_color)

	# 3x3 box shading (alternating subtle tint for visual grouping)
	var box_tint := tm.get_color("cell_given")
	for box_r in range(0, GRID_SIZE, BOX_SIZE):
		for box_c in range(0, GRID_SIZE, BOX_SIZE):
			var box_idx := (box_r / BOX_SIZE) * 3 + (box_c / BOX_SIZE)
			if box_idx % 2 == 0:
				var box_origin := origin + Vector2(box_c * cell_size, box_r * cell_size)
				var box_size := Vector2(BOX_SIZE * cell_size, BOX_SIZE * cell_size)
				draw_rect(Rect2(box_origin, box_size), box_tint)

	# Filled cells
	for r in GRID_SIZE:
		for c in GRID_SIZE:
			if grid[r * GRID_SIZE + c] != 0:
				var cell_origin := origin + Vector2(c * cell_size, r * cell_size)
				var color := cell_colors[r * GRID_SIZE + c]
				draw_rect(Rect2(cell_origin + Vector2(0.5, 0.5), Vector2(cell_size - 1, cell_size - 1)), color)
				# Neon cell glow
				if tm.is_neon:
					var glow := Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, 0.3)
					draw_rect(Rect2(cell_origin - Vector2(1, 1), Vector2(cell_size + 2, cell_size + 2)), glow, false, 1.5)

	# Flash animation
	if not _flash_cells.is_empty():
		var flash_color := Color(1.0, 1.0, 0.7, _flash_alpha * 0.6)
		for pos in _flash_cells:
			var p: Vector2i = pos
			var cell_origin := origin + Vector2(p.x * cell_size, p.y * cell_size)
			draw_rect(Rect2(cell_origin, Vector2(cell_size, cell_size)), flash_color)

	# Clear dissolve animation
	if not _clear_anim_cells.is_empty():
		var sweep_duration := _get_sweep_duration()
		for i in _clear_anim_cells.size():
			var p: Vector2i = _clear_anim_cells[i]
			var delay := _clear_anim_delays[i] if i < _clear_anim_delays.size() else 0.0
			var t := clamp((_clear_anim_elapsed - delay) / sweep_duration, 0.0, 1.0)
			if t >= 1.0:
				continue
			var base_color := _clear_anim_colors[i] if i < _clear_anim_colors.size() else tm.get_color("cell_given")
			var alpha := (1.0 - t)
			var scale := lerpf(1.0, 0.6, t)
			var draw_size := Vector2(cell_size, cell_size) * scale
			var offset := (Vector2(cell_size, cell_size) - draw_size) * 0.5
			var cell_origin := origin + Vector2(p.x * cell_size, p.y * cell_size)
			var draw_color := Color(base_color.r, base_color.g, base_color.b, alpha)
			draw_rect(Rect2(cell_origin + offset, draw_size), draw_color)

	# Preview
	if not preview_cells.is_empty():
		var preview_color: Color
		if preview_valid:
			preview_color = Color(0.5, 0.8, 1.0, 0.35)
		else:
			preview_color = Color(1.0, 0.3, 0.3, 0.25)
		for pos in preview_cells:
			if pos.x >= 0 and pos.x < GRID_SIZE and pos.y >= 0 and pos.y < GRID_SIZE:
				var cell_origin := origin + Vector2(pos.x * cell_size, pos.y * cell_size)
				draw_rect(Rect2(cell_origin + Vector2(0.5, 0.5), Vector2(cell_size - 1, cell_size - 1)), preview_color)

	# Grid lines (thin)
	var thin_color := tm.get_color("grid_line_thin")
	var neon_mode := tm.is_neon
	for i in range(GRID_SIZE + 1):
		var x := origin.x + i * cell_size
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + grid_px), thin_color, LINE_WIDTH)
		var y := origin.y + i * cell_size
		draw_line(Vector2(origin.x, y), Vector2(origin.x + grid_px, y), thin_color, LINE_WIDTH)

	# Box lines (thick) — in neon mode these are HDR and will bloom
	var thick_color := tm.get_color("grid_line_thick")
	var box_line_w := BOX_LINE_WIDTH if not neon_mode else 1.5
	for i in range(0, GRID_SIZE + 1, BOX_SIZE):
		var x := origin.x + i * cell_size
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + grid_px), thick_color, box_line_w)
		var y := origin.y + i * cell_size
		draw_line(Vector2(origin.x, y), Vector2(origin.x + grid_px, y), thick_color, box_line_w)
		# Extra glow pass for neon
		if neon_mode:
			var glow := Color(thick_color.r * 0.5, thick_color.g * 0.5, thick_color.b * 0.5, 0.3)
			draw_line(Vector2(x, origin.y), Vector2(x, origin.y + grid_px), glow, 4.0)
			draw_line(Vector2(origin.x, y), Vector2(origin.x + grid_px, y), glow, 4.0)

	# Outer border
	draw_rect(grid_rect, thick_color, false, BORDER_WIDTH)
	if neon_mode:
		var border_glow := Color(thick_color.r * 0.4, thick_color.g * 0.4, thick_color.b * 0.4, 0.25)
		draw_rect(Rect2(origin - Vector2(3, 3), Vector2(grid_px + 6, grid_px + 6)), border_glow, false, 6.0)
