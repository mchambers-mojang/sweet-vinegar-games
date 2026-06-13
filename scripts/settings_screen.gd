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
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())

	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)


func _build_settings_ui() -> void:
	for child in settings_list.get_children():
		child.queue_free()

	var is_sudoku := return_scene in ["res://scenes/main_menu.tscn", "res://scenes/game.tscn"]

	# --- Sudoku-specific settings ---
	if is_sudoku:
		_add_header("Sudoku")

		# Input mode
		_add_option_button("Input Mode", ["Cell First", "Number First"],
			0 if GameRulesRegistry.get_rule("sudoku", "input_mode") == "cell_first" else 1,
			func(idx: int) -> void:
				GameRulesRegistry.set_rule("sudoku", "input_mode", "cell_first" if idx == 0 else "number_first")
				GameRulesRegistry.save()
		)

		# Error mode
		_add_option_button("Error Mode", ["Strict (3 Strikes)", "Free"],
			0 if GameRulesRegistry.get_rule("sudoku", "error_mode") == "strict" else 1,
			func(idx: int) -> void:
				GameRulesRegistry.set_rule("sudoku", "error_mode", "strict" if idx == 0 else "free")
				GameRulesRegistry.save()
		)

		# Highlight row/col/box
		_add_toggle("Highlight Row/Column/Box", GameRulesRegistry.get_rule("sudoku", "highlight_row_col_box"),
			func(value: bool) -> void:
				GameRulesRegistry.set_rule("sudoku", "highlight_row_col_box", value)
				GameRulesRegistry.save()
		)

		# Auto-remove pencil marks
		_add_toggle("Auto-Remove Pencil Marks", GameRulesRegistry.get_rule("sudoku", "auto_remove_pencil_marks"),
			func(value: bool) -> void:
				GameRulesRegistry.set_rule("sudoku", "auto_remove_pencil_marks", value)
				GameRulesRegistry.save()
		)

		_add_separator()

	var is_blockudoku := return_scene in ["res://scenes/blockudoku_menu.tscn", "res://scenes/blockudoku_game.tscn"]

	# --- Blockudoku-specific settings ---
	if is_blockudoku:
		_add_header("Blockudoku Shapes")

		_add_toggle("Pentominoes (5-cell standard)", GameRulesRegistry.get_rule("blockudoku", "pentominoes"),
			func(value: bool) -> void:
				GameRulesRegistry.set_rule("blockudoku", "pentominoes", value)
				GameRulesRegistry.save()
		)

		_add_toggle("P-Pentomino (2×2 + tail)", GameRulesRegistry.get_rule("blockudoku", "p_pentomino"),
			func(value: bool) -> void:
				GameRulesRegistry.set_rule("blockudoku", "p_pentomino", value)
				GameRulesRegistry.save()
		)

		_add_toggle("W-Pentomino (stair-step)", GameRulesRegistry.get_rule("blockudoku", "w_pentomino"),
			func(value: bool) -> void:
				GameRulesRegistry.set_rule("blockudoku", "w_pentomino", value)
				GameRulesRegistry.save()
		)

		_add_toggle("Y-Pentomino (4-long + branch)", GameRulesRegistry.get_rule("blockudoku", "y_pentomino"),
			func(value: bool) -> void:
				GameRulesRegistry.set_rule("blockudoku", "y_pentomino", value)
				GameRulesRegistry.save()
		)

		_add_toggle("F-Pentomino (asymmetric)", GameRulesRegistry.get_rule("blockudoku", "f_pentomino"),
			func(value: bool) -> void:
				GameRulesRegistry.set_rule("blockudoku", "f_pentomino", value)
				GameRulesRegistry.save()
		)

		_add_toggle("N-Pentomino (zigzag)", GameRulesRegistry.get_rule("blockudoku", "n_pentomino"),
			func(value: bool) -> void:
				GameRulesRegistry.set_rule("blockudoku", "n_pentomino", value)
				GameRulesRegistry.save()
		)

		_add_toggle("Hexominoes (6-cell)", GameRulesRegistry.get_rule("blockudoku", "hexominoes"),
			func(value: bool) -> void:
				GameRulesRegistry.set_rule("blockudoku", "hexominoes", value)
				GameRulesRegistry.save()
		)

		_add_toggle("Diagonals", GameRulesRegistry.get_rule("blockudoku", "diagonals"),
			func(value: bool) -> void:
				GameRulesRegistry.set_rule("blockudoku", "diagonals", value)
				GameRulesRegistry.save()
		)

		_add_option_button("Drag Offset", ["None", "Small", "Medium", "Large"], GameRulesRegistry.get_rule("blockudoku", "drag_offset"),
			func(idx: int) -> void:
				GameRulesRegistry.set_rule("blockudoku", "drag_offset", idx)
				GameRulesRegistry.save()
		)

		_add_toggle("Rotation Mode (tap to rotate)", GameRulesRegistry.get_rule("blockudoku", "rotation_mode"),
			func(value: bool) -> void:
				GameRulesRegistry.set_rule("blockudoku", "rotation_mode", value)
				GameRulesRegistry.save()
		)

		_add_separator()

	# --- General settings ---
	_add_header("General")

	# Dark mode
	var dark_idx := 0
	match PlatformSettings.dark_mode:
		"system": dark_idx = 0
		"light": dark_idx = 1
		"dark": dark_idx = 2
		"neon": dark_idx = 3
	_add_option_button("Theme", ["System", "Light", "Dark", "Neon"], dark_idx,
		func(idx: int) -> void:
			match idx:
				0: PlatformSettings.dark_mode = "system"
				1: PlatformSettings.dark_mode = "light"
				2: PlatformSettings.dark_mode = "dark"
				3: PlatformSettings.dark_mode = "neon"
			PlatformSettings.save_settings()
	)

	# Timer
	_add_toggle("Show Timer", PlatformSettings.show_timer,
		func(value: bool) -> void:
			PlatformSettings.show_timer = value
			PlatformSettings.save_settings()
	)

	# Sound
	_add_toggle("Sound Effects", PlatformSettings.sound_enabled,
		func(value: bool) -> void:
			PlatformSettings.sound_enabled = value
			PlatformSettings.save_settings()
	)

	# Haptic
	_add_toggle("Haptic Feedback", PlatformSettings.haptic_enabled,
		func(value: bool) -> void:
			PlatformSettings.haptic_enabled = value
			PlatformSettings.save_settings()
	)

	_add_separator()
	_add_header("Effects")

	# Screen shake
	_add_toggle("Screen Shake", PlatformSettings.screen_shake_enabled,
		func(value: bool) -> void:
			PlatformSettings.screen_shake_enabled = value
			PlatformSettings.save_settings()
	)

	# Shockwave distortion
	_add_toggle("Shockwave Distortion", PlatformSettings.shockwave_enabled,
		func(value: bool) -> void:
			PlatformSettings.shockwave_enabled = value
			PlatformSettings.save_settings()
	)

	# Particle effects
	_add_toggle("Particle Effects", PlatformSettings.particle_effects_enabled,
		func(value: bool) -> void:
			PlatformSettings.particle_effects_enabled = value
			PlatformSettings.save_settings()
	)


func _add_toggle(label_text: String, initial: bool, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
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
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	settings_list.add_child(label)


func _add_separator() -> void:
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 10)
	sep.mouse_filter = Control.MOUSE_FILTER_PASS
	settings_list.add_child(sep)


func _add_option_button(label_text: String, options: Array, selected: int, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
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
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)
