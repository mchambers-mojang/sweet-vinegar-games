extends Node

## Persistent settings with defaults

signal settings_changed

const SAVE_PATH := "user://settings.cfg"

## Input
var input_mode: String = "cell_first" # "cell_first" or "number_first"

## Error checking
var error_mode: String = "strict" # "strict" or "free"

## Display
var show_timer: bool = true
var highlight_row_col_box: bool = true
var auto_remove_pencil_marks: bool = true
var dark_mode: String = "neon" # "system", "light", "dark", "neon"

## Feedback
var sound_enabled: bool = true
var haptic_enabled: bool = true

## Effects
var screen_shake_enabled: bool = true
var shockwave_enabled: bool = true
var particle_effects_enabled: bool = true

## Blockudoku shape families
var blockudoku_pentominoes: bool = true
var blockudoku_p_pentomino: bool = false
var blockudoku_w_pentomino: bool = false
var blockudoku_y_pentomino: bool = false
var blockudoku_f_pentomino: bool = false
var blockudoku_n_pentomino: bool = false
var blockudoku_hexominoes: bool = false
var blockudoku_diagonals: bool = false
var blockudoku_drag_offset: int = 1  # 0=None, 1=Small, 2=Medium, 3=Large
var blockudoku_rotation_mode: bool = false


func _ready() -> void:
	load_settings()
	# Ensure window is resizable on desktop
	if not OS.has_feature("mobile"):
		get_window().unresizable = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		# Ctrl+Shift+R: reload current scene (note: script changes require F5 restart)
		if key.keycode == KEY_R and key.ctrl_pressed and key.shift_pressed:
			print("Reloading current scene...")
			get_tree().reload_current_scene()
			get_viewport().set_input_as_handled()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("input", "mode", input_mode)
	config.set_value("error", "mode", error_mode)
	config.set_value("display", "show_timer", show_timer)
	config.set_value("display", "highlight_row_col_box", highlight_row_col_box)
	config.set_value("display", "auto_remove_pencil_marks", auto_remove_pencil_marks)
	config.set_value("display", "dark_mode", dark_mode)
	config.set_value("feedback", "sound_enabled", sound_enabled)
	config.set_value("feedback", "haptic_enabled", haptic_enabled)
	config.set_value("effects", "screen_shake", screen_shake_enabled)
	config.set_value("effects", "shockwave", shockwave_enabled)
	config.set_value("effects", "particles", particle_effects_enabled)
	config.set_value("blockudoku", "pentominoes", blockudoku_pentominoes)
	config.set_value("blockudoku", "p_pentomino", blockudoku_p_pentomino)
	config.set_value("blockudoku", "w_pentomino", blockudoku_w_pentomino)
	config.set_value("blockudoku", "y_pentomino", blockudoku_y_pentomino)
	config.set_value("blockudoku", "f_pentomino", blockudoku_f_pentomino)
	config.set_value("blockudoku", "n_pentomino", blockudoku_n_pentomino)
	config.set_value("blockudoku", "hexominoes", blockudoku_hexominoes)
	config.set_value("blockudoku", "diagonals", blockudoku_diagonals)
	config.set_value("blockudoku", "drag_offset", blockudoku_drag_offset)
	config.set_value("blockudoku", "rotation_mode", blockudoku_rotation_mode)
	config.save(SAVE_PATH)
	settings_changed.emit()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	input_mode = config.get_value("input", "mode", input_mode)
	error_mode = config.get_value("error", "mode", error_mode)
	show_timer = config.get_value("display", "show_timer", show_timer)
	highlight_row_col_box = config.get_value("display", "highlight_row_col_box", highlight_row_col_box)
	auto_remove_pencil_marks = config.get_value("display", "auto_remove_pencil_marks", auto_remove_pencil_marks)
	dark_mode = config.get_value("display", "dark_mode", dark_mode)
	sound_enabled = config.get_value("feedback", "sound_enabled", sound_enabled)
	haptic_enabled = config.get_value("feedback", "haptic_enabled", haptic_enabled)
	screen_shake_enabled = config.get_value("effects", "screen_shake", screen_shake_enabled)
	shockwave_enabled = config.get_value("effects", "shockwave", shockwave_enabled)
	particle_effects_enabled = config.get_value("effects", "particles", particle_effects_enabled)
	blockudoku_pentominoes = config.get_value("blockudoku", "pentominoes", blockudoku_pentominoes)
	blockudoku_p_pentomino = config.get_value("blockudoku", "p_pentomino", blockudoku_p_pentomino)
	blockudoku_w_pentomino = config.get_value("blockudoku", "w_pentomino", blockudoku_w_pentomino)
	blockudoku_y_pentomino = config.get_value("blockudoku", "y_pentomino", blockudoku_y_pentomino)
	blockudoku_f_pentomino = config.get_value("blockudoku", "f_pentomino", blockudoku_f_pentomino)
	blockudoku_n_pentomino = config.get_value("blockudoku", "n_pentomino", blockudoku_n_pentomino)
	blockudoku_hexominoes = config.get_value("blockudoku", "hexominoes", blockudoku_hexominoes)
	blockudoku_diagonals = config.get_value("blockudoku", "diagonals", blockudoku_diagonals)
	blockudoku_drag_offset = config.get_value("blockudoku", "drag_offset", blockudoku_drag_offset)
	blockudoku_rotation_mode = config.get_value("blockudoku", "rotation_mode", blockudoku_rotation_mode)
