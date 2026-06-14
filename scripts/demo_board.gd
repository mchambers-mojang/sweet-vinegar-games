extends Control

## Live-preview demo board for the custom theme editor.
## Draws a static 3×3 Sudoku-style grid showing all major color roles.
## Call set_palette() to update colors and trigger a redraw.

var _bg := Color(0.04, 0.04, 0.1)
var _cell_bg := Color(0.06, 0.06, 0.14)
var _cell_given := Color(0.08, 0.08, 0.18)
var _cell_selected := Color(0.12, 0.14, 0.3)
var _cell_highlighted := Color(0.1, 0.08, 0.22)
var _cell_same := Color(0.15, 0.05, 0.35)
var _cell_error := Color(0.5, 0.0, 0.1)
var _accent := Color(0.0, 1.5, 1.5)
var _secondary := Color(2.0, 0.3, 1.8)
var _error_col := Color(2.0, 0.0, 0.2)
var _text_pencil := Color(0.2, 0.15, 0.5)
var _grid_thin := Color(0.15, 0.1, 0.35)
var _grid_thick := Color(0.0, 1.5, 1.5)


func set_palette(bg: Color, accent: Color, secondary: Color, error: Color) -> void:
	_bg = bg
	_accent = accent
	_secondary = secondary
	_error_col = error

	_cell_bg = Color(bg.r + 0.02, bg.g + 0.02, bg.b + 0.04)
	_cell_given = Color(bg.r + 0.04, bg.g + 0.04, bg.b + 0.08)
	_cell_selected = Color(bg.r + accent.r * 0.08, bg.g + accent.g * 0.08, bg.b + accent.b * 0.08)
	_cell_highlighted = Color(bg.r + secondary.r * 0.05, bg.g + secondary.g * 0.05, bg.b + secondary.b * 0.05)
	_cell_same = Color(bg.r + accent.r * 0.05, bg.g + accent.g * 0.05, bg.b + accent.b * 0.05)
	_cell_error = Color(bg.r + error.r * 0.15, bg.g + error.g * 0.02, bg.b + error.b * 0.02)
	_text_pencil = Color(secondary.r * 0.15, secondary.g * 0.15, secondary.b * 0.15)
	_grid_thin = Color(accent.r * 0.15, accent.g * 0.15, accent.b * 0.15)
	_grid_thick = accent

	queue_redraw()


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	if font == null:
		font = ThemeDB.fallback_font

	const COLS := 3
	const ROWS := 3

	var board_size := min(size.x, size.y)
	var cell_size := board_size / float(COLS)
	var offset := Vector2((size.x - board_size) / 2.0, (size.y - board_size) / 2.0)

	# Fill background
	draw_rect(Rect2(Vector2.ZERO, size), _bg)

	# Cell layout (row-major, COLS=3):
	# [0] given "5"   [1] placed "3"   [2] error "8"
	# [3] selected "1"[4] highlighted  [5] same-# "7"
	# [6] normal      [7] pencil "5"   [8] normal
	var cell_bgs := [
		_cell_given, _cell_bg, _cell_error,
		_cell_selected, _cell_highlighted, _cell_same,
		_cell_bg, _cell_bg, _cell_bg,
	]
	var cell_texts := ["5", "3", "8", "1", "", "7", "", "5", ""]
	var cell_colors := [
		_accent, _secondary, _error_col,
		_accent, Color.TRANSPARENT, _secondary,
		Color.TRANSPARENT, _text_pencil, Color.TRANSPARENT,
	]
	# Row 2, col 1 (index 7) is a pencil mark — use smaller font
	var is_pencil := [false, false, false, false, false, false, false, true, false]

	var normal_fs := int(cell_size * 0.42)
	var pencil_fs := int(cell_size * 0.22)

	for i in range(COLS * ROWS):
		var row: int = i / COLS
		var col: int = i % COLS
		var rect := Rect2(
			offset.x + col * cell_size,
			offset.y + row * cell_size,
			cell_size,
			cell_size
		)

		draw_rect(rect, cell_bgs[i])

		var text: String = cell_texts[i]
		if not text.is_empty() and cell_colors[i] != Color.TRANSPARENT:
			var fs := pencil_fs if is_pencil[i] else normal_fs
			var ascent := font.get_ascent(fs)
			var string_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tx := rect.position.x + (cell_size - string_w) / 2.0
			var ty := rect.position.y + (cell_size + ascent) / 2.0
			draw_string(font, Vector2(tx, ty), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cell_colors[i])

	# Grid lines — thin inner lines, thick outer border
	var thick := maxf(1.5, board_size * 0.007)
	var thin := maxf(0.5, board_size * 0.003)

	# Outer border (thick)
	draw_rect(Rect2(offset, Vector2(board_size, board_size)), _grid_thick, false, thick)

	# Inner horizontal lines (thin)
	for r in range(1, ROWS):
		var y := offset.y + r * cell_size
		draw_line(Vector2(offset.x, y), Vector2(offset.x + board_size, y), _grid_thin, thin)

	# Inner vertical lines (thin)
	for c in range(1, COLS):
		var x := offset.x + c * cell_size
		draw_line(Vector2(x, offset.y), Vector2(x, offset.y + board_size), _grid_thin, thin)
