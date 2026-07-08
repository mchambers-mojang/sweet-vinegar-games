extends Control

## Settings screen

static var return_scene: String = Scenes.SUDOKU_MENU

@onready var back_button: Button = %BackButton
@onready var settings_list: VBoxContainer = %SettingsList


func _ready() -> void:
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(return_scene)
	)
	_build_settings_ui()
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


func _build_settings_ui() -> void:
	for child in settings_list.get_children():
		child.queue_free()

	var is_sudoku := return_scene in [Scenes.SUDOKU_MENU, Scenes.SUDOKU_GAME]

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

	var is_blockudoku := return_scene in [Scenes.BLOCKUDOKU_MENU, Scenes.BLOCKUDOKU_GAME]

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
		"custom": dark_idx = 4
	_add_option_button("Theme", ["System", "Light", "Dark", "Neon", "Custom"], dark_idx,
		func(idx: int) -> void:
			match idx:
				0: PlatformSettings.dark_mode = "system"
				1: PlatformSettings.dark_mode = "light"
				2: PlatformSettings.dark_mode = "dark"
				3: PlatformSettings.dark_mode = "neon"
				4:
					AppTheme.palette.ensure_default_palette()
					PlatformSettings.dark_mode = "custom"
			PlatformSettings.save_settings()
	)

	# Customize palette button
	_add_button("Customize Palette...", func() -> void:
		SceneTransition.transition_to(Scenes.THEME_EDITOR)
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

	_add_separator()
	_add_header("Leaderboards")

	# Display name
	_add_text_field("Display Name", PlayerIdentity.display_name, PlayerIdentity.MAX_DISPLAY_NAME_LENGTH,
		func(value: String) -> void:
			var trimmed := value.strip_edges().substr(0, PlayerIdentity.MAX_DISPLAY_NAME_LENGTH)
			if trimmed.is_empty():
				return
			if trimmed == PlayerIdentity.display_name:
				return
			PlayerIdentity.display_name = trimmed
			PlayerIdentity.sync_profile()
	)

	# Visibility toggle
	_add_toggle("Show on Leaderboards", PlayerIdentity.leaderboard_visible,
		func(value: bool) -> void:
			PlayerIdentity.leaderboard_visible = value
			PlayerIdentity.sync_profile()
	)

	# Data transmission kill switch — local-only, never synced to server
	_add_toggle("Submit Scores to Server", PlayerIdentity.leaderboard_data_enabled,
		func(value: bool) -> void:
			PlayerIdentity.leaderboard_data_enabled = value
			PlayerIdentity.save_local()
	)

	# Destructive action: purge all server-side leaderboard data
	_add_button("Delete All Leaderboard Data...", func() -> void:
		_show_delete_confirm_dialog()
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


func _add_button(label_text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = label_text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	settings_list.add_child(btn)


func _add_text_field(label_text: String, initial: String, max_length: int, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)

	var field := LineEdit.new()
	field.text = initial
	field.max_length = max_length
	field.custom_minimum_size = Vector2(140, 0)
	field.text_submitted.connect(callback)
	field.focus_exited.connect(func() -> void: callback.call(field.text))
	row.add_child(field)

	settings_list.add_child(row)


func _show_delete_confirm_dialog() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete All Leaderboard Data"
	dialog.dialog_text = "This will permanently delete all your scores from the server.\n\nThis cannot be undone."
	dialog.ok_button_text = "Delete"
	dialog.cancel_button_text = "Cancel"
	dialog.min_size = Vector2i(320, 0)
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		_show_delete_mode_dialog()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered()


func _show_delete_mode_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "How would you like to proceed?"
	dialog.dialog_text = "Stop Tracking: disables score submission and deletes all your scores from the server.\n\nClean Slate: deletes all your scores from the server but keeps score submission enabled."
	dialog.ok_button_text = "Stop Tracking"
	dialog.add_button("Clean Slate", true, "clean_slate")
	dialog.add_button("Cancel", true, "cancel")
	dialog.min_size = Vector2i(320, 0)
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		_perform_delete(true)
	)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "clean_slate":
			dialog.queue_free()
			_perform_delete(false)
		elif action == "cancel":
			dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered()


func _perform_delete(stop_tracking: bool) -> void:
	PlayerIdentity.delete_all_scores(stop_tracking, func(success: bool) -> void:
		_show_delete_result_dialog(success, stop_tracking)
	)


func _show_delete_result_dialog(success: bool, stop_tracking: bool) -> void:
	var dialog := AcceptDialog.new()
	if success:
		dialog.title = "Data Deleted"
		if stop_tracking:
			dialog.dialog_text = "All your leaderboard data has been deleted and score submission has been disabled."
		else:
			dialog.dialog_text = "All your leaderboard data has been deleted. Score submission remains enabled."
	else:
		dialog.title = "Delete Failed"
		dialog.dialog_text = "Could not delete your leaderboard data. Please check your connection and try again."
	dialog.ok_button_text = "OK"
	dialog.min_size = Vector2i(320, 0)
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		if success:
			_build_settings_ui()
	)
	dialog.popup_centered()


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)
