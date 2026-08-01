class_name EclipseGridBoard
extends Control

## Eclipse Grid board UI — draws the grid, cells, and relation clues; handles tap input.
##
## Accessibility: an invisible Button child is maintained for every cell so that
## screen readers can announce the cell state and relation clues.  These buttons
## have MOUSE_FILTER_IGNORE so they never intercept pointer events; focus handling
## and tap routing are done by the board's own _gui_input.

signal cell_tapped(index: int)

var grid_size: int = 0
var givens: Array[int] = []
var cells: Array[int] = []
var h_relations: Dictionary = {}
var v_relations: Dictionary = {}
var error_cells: Array[int] = []

## Invisible accessibility buttons — one per cell, rebuilt on setup().
var _cell_buttons: Array[Button] = []

const EMPTY := EclipseGridSolver.EMPTY
const PLUS  := EclipseGridSolver.PLUS
const MINUS := EclipseGridSolver.MINUS
const EQ    := EclipseGridSolver.EQ
const NEQ   := EclipseGridSolver.NEQ

const BORDER_WIDTH := 2.0
const CELL_PAD_FRAC := 0.08   ## Fraction of cell size used as padding around glyph


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(sz: int, gv: Array[int], cr: Array[int], hr: Dictionary, vr: Dictionary) -> void:
	grid_size = sz
	givens = gv.duplicate()
	cells = cr.duplicate()
	h_relations = hr
	v_relations = vr
	error_cells.clear()
	_rebuild_cell_buttons()
	queue_redraw()


func update_cells(cr: Array[int]) -> void:
	cells = cr.duplicate()
	_update_cell_button_texts()
	queue_redraw()


func update_errors(errs: Array[int]) -> void:
	error_cells = errs.duplicate()
	queue_redraw()


# ---------------------------------------------------------------------------
# Accessibility
# ---------------------------------------------------------------------------

## Rebuild invisible Button children used by screen readers.
func _rebuild_cell_buttons() -> void:
	for btn in _cell_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_cell_buttons.clear()
	for idx in grid_size * grid_size:
		var btn := Button.new()
		btn.flat = true
		# Invisible to pointer; keyboard / AT navigation still works.
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.focus_mode = Control.FOCUS_NONE
		btn.self_modulate = Color(0.0, 0.0, 0.0, 0.0)
		btn.text = _cell_accessible_text(idx)
		add_child(btn)
		_cell_buttons.append(btn)


## Update accessible text for each cell without rebuilding the node tree.
func _update_cell_button_texts() -> void:
	for i in mini(cells.size(), _cell_buttons.size()):
		if is_instance_valid(_cell_buttons[i]):
			_cell_buttons[i].text = _cell_accessible_text(i)


## Return a human-readable description of the cell at flat index `idx`.
func _cell_accessible_text(idx: int) -> String:
	if grid_size <= 0:
		return ""
	var row := idx / grid_size
	var col := idx % grid_size
	var val: int = cells[idx] if idx < cells.size() else EMPTY
	var is_given: bool = idx < givens.size() and givens[idx] != EMPTY

	var glyph: String
	match val:
		PLUS:  glyph = "plus"
		MINUS: glyph = "minus"
		_:     glyph = "empty"

	var parts: Array[String] = [glyph]
	if is_given:
		parts.append("given")

	var pos := Vector2i(col, row)
	# Horizontal clues
	if h_relations.has(pos):
		parts.append("right neighbor %s" % ("equals" if h_relations[pos] == EQ else "not-equals"))
	if col > 0 and h_relations.has(Vector2i(col - 1, row)):
		parts.append("left neighbor %s" % ("equals" if h_relations[Vector2i(col - 1, row)] == EQ else "not-equals"))
	# Vertical clues
	if v_relations.has(pos):
		parts.append("below neighbor %s" % ("equals" if v_relations[pos] == EQ else "not-equals"))
	if row > 0 and v_relations.has(Vector2i(col, row - 1)):
		parts.append("above neighbor %s" % ("equals" if v_relations[Vector2i(col, row - 1)] == EQ else "not-equals"))

	return "Row %d col %d: %s" % [row + 1, col + 1, ", ".join(parts)]


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _get_cell_size() -> float:
	if grid_size <= 0:
		return 0.0
	var avail_w := size.x - BORDER_WIDTH * 2
	var avail_h := size.y - BORDER_WIDTH * 2
	return minf(avail_w / grid_size, avail_h / grid_size)


func _get_grid_origin() -> Vector2:
	var cs := _get_cell_size()
	if cs <= 0:
		return Vector2.ZERO
	var gw := cs * grid_size
	var gh := cs * grid_size
	return Vector2((size.x - gw) / 2.0, (size.y - gh) / 2.0)


func get_cell_rect(col: int, row: int) -> Rect2:
	var cs := _get_cell_size()
	var origin := _get_grid_origin()
	return Rect2(origin + Vector2(col * cs, row * cs), Vector2(cs, cs))


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var fired := false

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			pos = st.position
			fired = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			pos = mb.position
			fired = true

	if not fired or grid_size <= 0:
		return

	var cs := _get_cell_size()
	var origin := _get_grid_origin()
	var col := int((pos.x - origin.x) / cs)
	var row := int((pos.y - origin.y) / cs)
	if col < 0 or col >= grid_size or row < 0 or row >= grid_size:
		return

	cell_tapped.emit(row * grid_size + col)
	accept_event()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if grid_size <= 0:
		return

	var cs := _get_cell_size()
	var origin := _get_grid_origin()
	var tm := AppTheme
	var bg := tm.get_color("cell_background")
	var grid_rect := Rect2(origin, Vector2(cs * grid_size, cs * grid_size))
	var neon := tm.is_neon

	# Background
	draw_rect(grid_rect, bg)

	# Cells
	for r in grid_size:
		for c in grid_size:
			var idx: int = r * grid_size + c
			var v: int = cells[idx] if idx < cells.size() else EMPTY
			var is_given: bool = idx < givens.size() and givens[idx] != EMPTY
			var is_error: bool = error_cells.has(idx)
			_draw_cell(origin, cs, r, c, v, is_given, is_error, neon)

	# Relation clues (drawn on top of cells)
	_draw_relations(origin, cs, neon)

	# Grid lines
	_draw_grid_lines(origin, cs, neon)


func _draw_cell(
		origin: Vector2,
		cs: float,
		row: int,
		col: int,
		value: int,
		is_given: bool,
		is_error: bool,
		neon: bool) -> void:
	var cell_pos := origin + Vector2(col * cs, row * cs)
	var cell_rect := Rect2(cell_pos, Vector2(cs, cs))
	var tm := AppTheme

	# Error highlight
	if is_error and value != EMPTY:
		var err_color := Color(1.0, 0.3, 0.3, 0.35) if not neon else Color(1.5, 0.2, 0.2, 0.3)
		draw_rect(cell_rect, err_color)

	# Given highlight
	if is_given and value != EMPTY:
		var given_bg := tm.get_color("cell_given_bg") if tm.has_color("cell_given_bg") else Color(0.85, 0.85, 0.85, 0.3)
		if neon:
			given_bg = Color(0.1, 0.1, 0.3, 0.4)
		draw_rect(cell_rect, given_bg)

	if value == EMPTY:
		return

	var pad := cs * CELL_PAD_FRAC
	var inner := Rect2(cell_pos + Vector2(pad, pad), Vector2(cs - pad * 2, cs - pad * 2))

	if value == PLUS:
		_draw_plus(inner, is_given, neon)
	else:
		_draw_minus(inner, is_given, neon)


func _draw_plus(rect: Rect2, is_given: bool, neon: bool) -> void:
	var tm := AppTheme
	var color := tm.get_color("primary") if tm.has_color("primary") else tm.get_color("text_given")
	if neon:
		color = Color(0.0, 1.5, 1.5)
	if is_given:
		color = color.lightened(0.1)

	var cx := rect.position.x + rect.size.x * 0.5
	var cy := rect.position.y + rect.size.y * 0.5
	var arm := rect.size.x * 0.35
	var thick := maxf(rect.size.x * 0.18, 2.0)

	# Horizontal bar
	draw_rect(Rect2(cx - arm, cy - thick * 0.5, arm * 2, thick), color)
	# Vertical bar
	draw_rect(Rect2(cx - thick * 0.5, cy - arm, thick, arm * 2), color)

	if neon:
		var glow := Color(color.r * 0.4, color.g * 0.4, color.b * 0.4, 0.25)
		draw_rect(Rect2(cx - arm - 2, cy - thick - 1, arm * 2 + 4, thick * 2 + 2), glow)
		draw_rect(Rect2(cx - thick - 1, cy - arm - 2, thick * 2 + 2, arm * 2 + 4), glow)


func _draw_minus(rect: Rect2, is_given: bool, neon: bool) -> void:
	var tm := AppTheme
	var color := tm.get_color("secondary") if tm.has_color("secondary") else tm.get_color("text_player")
	if neon:
		color = Color(1.5, 0.3, 1.5)
	if is_given:
		color = color.lightened(0.1)

	var cx := rect.position.x + rect.size.x * 0.5
	var cy := rect.position.y + rect.size.y * 0.5
	var arm := rect.size.x * 0.35
	var thick := maxf(rect.size.x * 0.18, 2.0)

	# Horizontal bar only
	draw_rect(Rect2(cx - arm, cy - thick * 0.5, arm * 2, thick), color)

	if neon:
		var glow := Color(color.r * 0.4, color.g * 0.4, color.b * 0.4, 0.25)
		draw_rect(Rect2(cx - arm - 2, cy - thick - 1, arm * 2 + 4, thick * 2 + 2), glow)


func _draw_relations(origin: Vector2, cs: float, neon: bool) -> void:
	var rel_size := maxf(cs * 0.18, 8.0)
	var font := ThemeDB.fallback_font
	var font_sz := int(rel_size * 1.4)
	var tm := AppTheme
	var rel_color := tm.get_color("text_given")
	if neon:
		rel_color = Color(1.0, 1.0, 0.5)

	# Horizontal relations: drawn between cells in the same row
	for pos in h_relations.keys():
		var cell: Vector2i = pos
		var rel: int = h_relations[pos]
		var left_cx := origin.x + (cell.x + 1) * cs
		var cy := origin.y + (cell.y + 0.5) * cs
		var text := "=" if rel == EQ else "≠"
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_sz)
		var text_pos := Vector2(left_cx - text_size.x * 0.5, cy + text_size.y * 0.35)
		# Small background
		var bg_rect := Rect2(left_cx - rel_size * 0.7, cy - rel_size * 0.7, rel_size * 1.4, rel_size * 1.4)
		var bg_color := tm.get_color("cell_background")
		bg_color.a = 0.85
		draw_rect(bg_rect, bg_color)
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, rel_color)

	# Vertical relations: drawn between cells in the same column
	for pos in v_relations.keys():
		var cell: Vector2i = pos
		var rel: int = v_relations[pos]
		var cx := origin.x + (cell.x + 0.5) * cs
		var top_cy := origin.y + (cell.y + 1) * cs
		var text := "=" if rel == EQ else "≠"
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_sz)
		var text_pos := Vector2(cx - text_size.x * 0.5, top_cy + text_size.y * 0.35)
		var bg_rect := Rect2(cx - rel_size * 0.7, top_cy - rel_size * 0.7, rel_size * 1.4, rel_size * 1.4)
		var bg_color := tm.get_color("cell_background")
		bg_color.a = 0.85
		draw_rect(bg_rect, bg_color)
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, rel_color)


func _draw_grid_lines(origin: Vector2, cs: float, neon: bool) -> void:
	var tm := AppTheme
	var line_color := tm.get_color("text_given").darkened(0.5)
	var border_color := tm.get_color("text_given")
	if neon:
		line_color = Color(0.15, 0.1, 0.35)
		border_color = Color(0.0, 1.5, 1.5)

	for i in range(grid_size + 1):
		var x := origin.x + i * cs
		var y := origin.y + i * cs
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + grid_size * cs), line_color, 1.0)
		draw_line(Vector2(origin.x, y), Vector2(origin.x + grid_size * cs, y), line_color, 1.0)

	var grid_rect := Rect2(origin, Vector2(cs * grid_size, cs * grid_size))
	draw_rect(grid_rect, border_color, false, BORDER_WIDTH)

	if neon:
		var glow := Color(0.0, 0.6, 0.6, 0.25)
		draw_rect(Rect2(origin - Vector2(3, 3), Vector2(cs * grid_size + 6, cs * grid_size + 6)), glow, false, 5.0)


## Flash all cells for the win celebration.
func flash_all(_color: Color, duration: float) -> void:
	var original := modulate
	modulate = Color(1.2, 1.1, 0.8)
	if AppTheme.is_neon:
		var cs := _get_cell_size()
		var orig := _get_grid_origin()
		EffectFactory.neon_burst(self, orig + Vector2(cs * grid_size * 0.5, cs * grid_size * 0.5),
				Color(0.0, 1.5, 1.5), 16, 1.4)
		AppTheme.screen_shake(8.0, 0.25)
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_callback(func() -> void: modulate = original)
