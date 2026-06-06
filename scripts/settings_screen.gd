extends Control

## Settings screen

static var return_scene: String = "res://scenes/main_menu.tscn"

@onready var back_button: Button = %BackButton
@onready var settings_list: VBoxContainer = %SettingsList


func _ready() -> void:
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(return_scene)
	)
	_build_settings_ui()
	_apply_theme()
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_theme())

	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)


func _build_settings_ui() -> void:
	for child in settings_list.get_children():
		child.queue_free()

	var is_sudoku := return_scene == "res://scenes/main_menu.tscn"

	# --- Sudoku-specific settings ---
	if is_sudoku:
		_add_header("Sudoku")

		# Input mode
		_add_option_button("Input Mode", ["Cell First", "Number First"],
			0 if SettingsManager.input_mode == "cell_first" else 1,
			func(idx: int) -> void:
				SettingsManager.input_mode = "cell_first" if idx == 0 else "number_first"
				SettingsManager.save_settings()
		)

		# Error mode
		_add_option_button("Error Mode", ["Strict (3 Strikes)", "Free"],
			0 if SettingsManager.error_mode == "strict" else 1,
			func(idx: int) -> void:
				SettingsManager.error_mode = "strict" if idx == 0 else "free"
				SettingsManager.save_settings()
		)

		# Highlight row/col/box
		_add_toggle("Highlight Row/Column/Box", SettingsManager.highlight_row_col_box,
			func(value: bool) -> void:
				SettingsManager.highlight_row_col_box = value
				SettingsManager.save_settings()
		)

		# Auto-remove pencil marks
		_add_toggle("Auto-Remove Pencil Marks", SettingsManager.auto_remove_pencil_marks,
			func(value: bool) -> void:
				SettingsManager.auto_remove_pencil_marks = value
				SettingsManager.save_settings()
		)

		_add_separator()

	var is_blockudoku := return_scene == "res://scenes/blockudoku_menu.tscn"

	# --- Blockudoku-specific settings ---
	if is_blockudoku:
		_add_header("Blockudoku Shapes")

		_add_toggle("Pentominoes (5-cell standard)", SettingsManager.blockudoku_pentominoes,
			func(value: bool) -> void:
				SettingsManager.blockudoku_pentominoes = value
				SettingsManager.save_settings()
		)

		_add_toggle("P-Pentomino (2×2 + tail)", SettingsManager.blockudoku_p_pentomino,
			func(value: bool) -> void:
				SettingsManager.blockudoku_p_pentomino = value
				SettingsManager.save_settings()
		)

		_add_toggle("W-Pentomino (stair-step)", SettingsManager.blockudoku_w_pentomino,
			func(value: bool) -> void:
				SettingsManager.blockudoku_w_pentomino = value
				SettingsManager.save_settings()
		)

		_add_toggle("Y-Pentomino (4-long + branch)", SettingsManager.blockudoku_y_pentomino,
			func(value: bool) -> void:
				SettingsManager.blockudoku_y_pentomino = value
				SettingsManager.save_settings()
		)

		_add_toggle("F-Pentomino (asymmetric)", SettingsManager.blockudoku_f_pentomino,
			func(value: bool) -> void:
				SettingsManager.blockudoku_f_pentomino = value
				SettingsManager.save_settings()
		)

		_add_toggle("N-Pentomino (zigzag)", SettingsManager.blockudoku_n_pentomino,
			func(value: bool) -> void:
				SettingsManager.blockudoku_n_pentomino = value
				SettingsManager.save_settings()
		)

		_add_toggle("Hexominoes (6-cell)", SettingsManager.blockudoku_hexominoes,
			func(value: bool) -> void:
				SettingsManager.blockudoku_hexominoes = value
				SettingsManager.save_settings()
		)

		_add_toggle("Diagonals", SettingsManager.blockudoku_diagonals,
			func(value: bool) -> void:
				SettingsManager.blockudoku_diagonals = value
				SettingsManager.save_settings()
		)

		_add_option_button("Drag Offset", ["None", "Small", "Medium", "Large"], SettingsManager.blockudoku_drag_offset,
			func(idx: int) -> void:
				SettingsManager.blockudoku_drag_offset = idx
				SettingsManager.save_settings()
		)

		_add_toggle("Rotation Mode (tap to rotate)", SettingsManager.blockudoku_rotation_mode,
			func(value: bool) -> void:
				SettingsManager.blockudoku_rotation_mode = value
				SettingsManager.save_settings()
		)

		_add_separator()

	# --- General settings ---
	_add_header("General")

	# Dark mode
	var dark_idx := 0
	match SettingsManager.dark_mode:
		"system": dark_idx = 0
		"light": dark_idx = 1
		"dark": dark_idx = 2
		"neon": dark_idx = 3
	_add_option_button("Theme", ["System", "Light", "Dark", "Neon"], dark_idx,
		func(idx: int) -> void:
			match idx:
				0: SettingsManager.dark_mode = "system"
				1: SettingsManager.dark_mode = "light"
				2: SettingsManager.dark_mode = "dark"
				3: SettingsManager.dark_mode = "neon"
			SettingsManager.save_settings()
	)

	# Timer
	_add_toggle("Show Timer", SettingsManager.show_timer,
		func(value: bool) -> void:
			SettingsManager.show_timer = value
			SettingsManager.save_settings()
	)

	# Sound
	_add_toggle("Sound Effects", SettingsManager.sound_enabled,
		func(value: bool) -> void:
			SettingsManager.sound_enabled = value
			SettingsManager.save_settings()
	)

	# Haptic
	_add_toggle("Haptic Feedback", SettingsManager.haptic_enabled,
		func(value: bool) -> void:
			SettingsManager.haptic_enabled = value
			SettingsManager.save_settings()
	)

	_add_separator()
	_add_header("Effects")

	# Screen shake
	_add_toggle("Screen Shake", SettingsManager.screen_shake_enabled,
		func(value: bool) -> void:
			SettingsManager.screen_shake_enabled = value
			SettingsManager.save_settings()
	)

	# Shockwave distortion
	_add_toggle("Shockwave Distortion", SettingsManager.shockwave_enabled,
		func(value: bool) -> void:
			SettingsManager.shockwave_enabled = value
			SettingsManager.save_settings()
	)

	# Particle effects
	_add_toggle("Particle Effects", SettingsManager.particle_effects_enabled,
		func(value: bool) -> void:
			SettingsManager.particle_effects_enabled = value
			SettingsManager.save_settings()
	)


func _add_toggle(label_text: String, initial: bool, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var toggle := CheckButton.new()
	toggle.button_pressed = initial
	toggle.toggled.connect(callback)
	row.add_child(toggle)

	settings_list.add_child(row)


func _add_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	settings_list.add_child(label)


func _add_separator() -> void:
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 10)
	settings_list.add_child(sep)


func _add_option_button(label_text: String, options: Array, selected: int, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var option_btn := OptionButton.new()
	for opt in options:
		option_btn.add_item(opt)
	option_btn.selected = selected
	option_btn.item_selected.connect(callback)
	row.add_child(option_btn)

	settings_list.add_child(row)


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("background")
	add_theme_stylebox_override("panel", style)
