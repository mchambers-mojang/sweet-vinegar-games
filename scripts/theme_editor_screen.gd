extends Control

## Theme editor screen — manage named custom palettes and edit their colors.
## Provides a palette list picker, 4 ColorPickerButton slots, a live preview
## demo board, and save/apply controls.

@onready var back_button: Button = %BackButton
@onready var editor_content: VBoxContainer = %EditorContent

# Built dynamically in _build_ui()
var _palette_option: OptionButton = null
var _rename_button: Button = null
var _duplicate_button: Button = null
var _delete_button: Button = null
var _bg_picker: ColorPickerButton = null
var _accent_picker: ColorPickerButton = null
var _secondary_picker: ColorPickerButton = null
var _error_picker: ColorPickerButton = null
var _preview_board: _PreviewBoard = null
var _apply_button: Button = null

# Editing state
var _editing_index: int = -1  # Index of the palette currently being edited
var _unsaved: bool = false     # Whether the current pickers differ from saved


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	_build_ui()
	_ensure_default_palette()
	_reload_palette_list()
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())
	CrashCollector.register_state_provider(_get_crash_state)

	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)


func _exit_tree() -> void:
	CrashCollector.unregister_state_provider(_get_crash_state)


func _get_crash_state() -> Dictionary:
	var pal_name := ""
	if _editing_index >= 0:
		var pal: Dictionary = AppTheme.palette.get_custom_palette(_editing_index)
		if not pal.is_empty():
			pal_name = str(pal.get("name", ""))
	return {
		"screen": "theme_editor",
		"editing_palette_index": _editing_index,
		"editing_palette_name": pal_name,
		"unsaved_changes": _unsaved,
		"total_palettes": AppTheme.palette.custom_palettes.size(),
		"active_palette_index": AppTheme.palette.active_custom_palette_index,
	}


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	for child in editor_content.get_children():
		child.queue_free()

	# --- Saved Palettes ---
	_add_header("Saved Palettes")

	var palette_row := HBoxContainer.new()
	palette_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_row.mouse_filter = Control.MOUSE_FILTER_PASS
	editor_content.add_child(palette_row)

	_palette_option = OptionButton.new()
	_palette_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_option.item_selected.connect(_on_palette_selected)
	palette_row.add_child(_palette_option)

	var new_button := Button.new()
	new_button.text = "New"
	new_button.pressed.connect(_on_new_palette)
	palette_row.add_child(new_button)

	var action_row := HBoxContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.mouse_filter = Control.MOUSE_FILTER_PASS
	editor_content.add_child(action_row)

	_rename_button = Button.new()
	_rename_button.text = "Rename"
	_rename_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_button.pressed.connect(_on_rename_palette)
	action_row.add_child(_rename_button)

	_duplicate_button = Button.new()
	_duplicate_button.text = "Duplicate"
	_duplicate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_duplicate_button.pressed.connect(_on_duplicate_palette)
	action_row.add_child(_duplicate_button)

	_delete_button = Button.new()
	_delete_button.text = "Delete"
	_delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_button.pressed.connect(_on_delete_palette)
	action_row.add_child(_delete_button)

	_add_separator()

	# --- Color pickers ---
	_add_header("Colors")

	_bg_picker = _add_color_row("Background", Color(0.04, 0.04, 0.1))
	_accent_picker = _add_color_row("Accent", Color(0.0, 1.5, 1.5))
	_secondary_picker = _add_color_row("Secondary", Color(2.0, 0.3, 1.8))
	_error_picker = _add_color_row("Error", Color(2.0, 0.0, 0.2))

	_bg_picker.color_changed.connect(_on_color_changed)
	_accent_picker.color_changed.connect(_on_color_changed)
	_secondary_picker.color_changed.connect(_on_color_changed)
	_error_picker.color_changed.connect(_on_color_changed)

	var reset_button := Button.new()
	reset_button.text = "Reset to Default"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button.pressed.connect(_on_reset_to_default)
	editor_content.add_child(reset_button)

	_add_separator()

	# --- Apply / Save ---
	_apply_button = Button.new()
	_apply_button.text = "Apply & Save"
	_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button.pressed.connect(_on_apply_and_save)
	editor_content.add_child(_apply_button)

	_add_separator()

	# --- Preview ---
	_add_header("Preview")

	_preview_board = _PreviewBoard.new()
	_preview_board.custom_minimum_size = Vector2(0, 220)
	_preview_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_content.add_child(_preview_board)


func _add_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	editor_content.add_child(label)


func _add_separator() -> void:
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 10)
	sep.mouse_filter = Control.MOUSE_FILTER_PASS
	editor_content.add_child(sep)


## Creates a labeled row with a ColorPickerButton and returns the picker.
func _add_color_row(label_text: String, default_color: Color) -> ColorPickerButton:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)

	var picker := ColorPickerButton.new()
	picker.color = Color(default_color.r, default_color.g, default_color.b, 1.0)
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(80, 36)
	# PopupPanel defaults to transparent=true, making all backgrounds invisible
	picker.get_popup().transparent = false
	row.add_child(picker)

	editor_content.add_child(row)
	return picker


# ---------------------------------------------------------------------------
# Palette list management
# ---------------------------------------------------------------------------

func _ensure_default_palette() -> void:
	if AppTheme.palette.ensure_default_palette():
		AppTheme.palette.save()


func _reload_palette_list() -> void:
	if not _palette_option:
		return
	_palette_option.clear()
	var palettes := AppTheme.palette.custom_palettes
	for p in palettes:
		_palette_option.add_item(str(p.get("name", "Palette")))

	var has_palettes := palettes.size() > 0
	_rename_button.disabled = not has_palettes
	_duplicate_button.disabled = not has_palettes
	_delete_button.disabled = not has_palettes
	if _apply_button:
		_apply_button.disabled = not has_palettes

	if has_palettes:
		# Select the active palette, or default to first
		var active := AppTheme.palette.active_custom_palette_index
		var idx := clampi(active if active >= 0 else 0, 0, palettes.size() - 1)
		_palette_option.selected = idx
		_editing_index = idx
		_load_palette_into_pickers(idx)
	else:
		_editing_index = -1
		_load_default_colors_into_pickers()

	_update_preview()


func _load_palette_into_pickers(index: int) -> void:
	var pal: Dictionary = AppTheme.palette.get_custom_palette(index)
	if pal.is_empty():
		return
	_bg_picker.color = Color(pal["bg"], 1.0)
	_accent_picker.color = Color(pal["accent"], 1.0)
	_secondary_picker.color = Color(pal["secondary"], 1.0)
	_error_picker.color = Color(pal["error"], 1.0)
	_unsaved = false


func _load_default_colors_into_pickers() -> void:
	var defaults: Dictionary = ThemePalette.default_palette_colors()
	_bg_picker.color = Color(defaults["bg"], 1.0)
	_accent_picker.color = Color(defaults["accent"], 1.0)
	_secondary_picker.color = Color(defaults["secondary"], 1.0)
	_error_picker.color = Color(defaults["error"], 1.0)
	_unsaved = false


func _update_preview() -> void:
	if not _preview_board or not _bg_picker:
		return
	var pal := ThemePalette.build_custom(
		_bg_picker.color, _accent_picker.color,
		_secondary_picker.color, _error_picker.color
	)
	_preview_board.set_palette(pal)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_back() -> void:
	if _unsaved:
		_show_unsaved_dialog(func() -> void: SceneTransition.transition_to(Scenes.SETTINGS))
		return
	SceneTransition.transition_to(Scenes.SETTINGS)


func _on_palette_selected(index: int) -> void:
	if _unsaved and index != _editing_index:
		_show_unsaved_dialog(func() -> void:
			_editing_index = index
			_load_palette_into_pickers(index)
			_update_preview()
		)
		# Revert the OptionButton visual back to the current editing index
		# (the dialog callback will update it if the user confirms)
		if _editing_index >= 0:
			_palette_option.selected = _editing_index
		return
	_editing_index = index
	_load_palette_into_pickers(index)
	_update_preview()


func _on_new_palette() -> void:
	if _unsaved:
		_show_unsaved_dialog(func() -> void: _on_new_palette())
		return
	_show_name_dialog("New Palette", "My Palette", func(name: String) -> void:
		var defaults: Dictionary = ThemePalette.default_palette_colors()
		var new_idx := AppTheme.palette.add_custom_palette(
			name,
			defaults["bg"], defaults["accent"], defaults["secondary"], defaults["error"]
		)
		AppTheme.palette.save()
		_reload_palette_list()
		_palette_option.selected = new_idx
		_editing_index = new_idx
		_load_palette_into_pickers(new_idx)
		_update_preview()
	)


func _on_rename_palette() -> void:
	if _editing_index < 0:
		return
	var current_pal: Dictionary = AppTheme.palette.get_custom_palette(_editing_index)
	if current_pal.is_empty():
		return
	var current_name: String = str(current_pal.get("name", "Palette"))
	_show_name_dialog("Rename Palette", current_name, func(name: String) -> void:
		var pal: Dictionary = AppTheme.palette.get_custom_palette(_editing_index)
		if pal.is_empty():
			return
		AppTheme.palette.update_custom_palette(
			_editing_index, name,
			pal["bg"], pal["accent"], pal["secondary"], pal["error"]
		)
		AppTheme.palette.save()
		var was_editing := _editing_index
		_reload_palette_list()
		_palette_option.selected = was_editing
		_editing_index = was_editing
		_load_palette_into_pickers(was_editing)
	)


func _on_duplicate_palette() -> void:
	if _editing_index < 0:
		return
	if _unsaved:
		_show_unsaved_dialog(func() -> void: _on_duplicate_palette())
		return
	var new_idx := AppTheme.palette.duplicate_custom_palette(_editing_index)
	if new_idx >= 0:
		AppTheme.palette.save()
		_reload_palette_list()
		_palette_option.selected = new_idx
		_editing_index = new_idx
		_load_palette_into_pickers(new_idx)
		_update_preview()


func _on_delete_palette() -> void:
	if _editing_index < 0:
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete Palette"
	dialog.dialog_text = "Delete this palette? This cannot be undone."
	dialog.confirmed.connect(func() -> void:
		var was_active := AppTheme.palette.active_custom_palette_index == _editing_index
		AppTheme.palette.remove_custom_palette(_editing_index)
		if was_active:
			AppTheme.palette.set_mode("neon")
		AppTheme.palette.save()
		_reload_palette_list()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _on_reset_to_default() -> void:
	_load_default_colors_into_pickers()
	_unsaved = true
	_update_preview()


func _on_color_changed(_color: Color) -> void:
	_unsaved = true
	_update_preview()


func _on_apply_and_save() -> void:
	if _editing_index < 0:
		# No palette exists yet — create one with current picker colors
		_show_name_dialog("Save Palette", "My Palette", func(name: String) -> void:
			var new_idx := AppTheme.palette.add_custom_palette(
				name,
				_bg_picker.color, _accent_picker.color,
				_secondary_picker.color, _error_picker.color
			)
			AppTheme.palette.active_custom_palette_index = new_idx
			AppTheme.palette.set_mode("custom")
			AppTheme.palette.save()
			_reload_palette_list()
		)
		return

	# Save current pickers into the selected palette
	var existing_pal: Dictionary = AppTheme.palette.get_custom_palette(_editing_index)
	var existing_name: String = str(existing_pal.get("name", "Palette")) if not existing_pal.is_empty() else "Palette"
	AppTheme.palette.update_custom_palette(
		_editing_index,
		existing_name,
		_bg_picker.color, _accent_picker.color,
		_secondary_picker.color, _error_picker.color
	)
	AppTheme.palette.active_custom_palette_index = _editing_index
	AppTheme.palette.set_mode("custom")
	AppTheme.palette.save()
	_unsaved = false


# ---------------------------------------------------------------------------
# Name input dialog
# ---------------------------------------------------------------------------

func _show_unsaved_dialog(on_discard: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Unsaved Changes"
	dialog.dialog_text = "You have unsaved changes. Discard them?"
	dialog.ok_button_text = "Discard"
	dialog.confirmed.connect(func() -> void:
		_unsaved = false
		on_discard.call()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _show_name_dialog(title: String, initial: String, on_confirmed: Callable) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.ok_button_text = "OK"

	var line := LineEdit.new()
	line.text = initial
	line.custom_minimum_size = Vector2(260, 0)
	line.select_all_on_focus = true
	dialog.get_vbox().add_child(line)

	dialog.confirmed.connect(func() -> void:
		var entered := line.text.strip_edges()
		if entered.is_empty():
			entered = initial
		on_confirmed.call(entered)
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(320, 120))
	line.grab_focus()


# ---------------------------------------------------------------------------
# Theme application
# ---------------------------------------------------------------------------

func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)


# ---------------------------------------------------------------------------
# Preview board — inner class that draws a mini palette demo
# ---------------------------------------------------------------------------

class _PreviewBoard extends Control:
	var _palette: Dictionary = {}

	func set_palette(palette: Dictionary) -> void:
		_palette = palette
		queue_redraw()

	func _draw() -> void:
		if _palette.is_empty():
			return

		var w := size.x
		var h := size.y
		var cols := 5
		var rows := 4
		var cell_w := w / cols
		var cell_h := h / rows

		# Background
		draw_rect(Rect2(0, 0, w, h), _c("background"))

		# Cell states to demonstrate:
		# [row][col] → state key
		var layout := [
			["given",      "given",      "normal",     "selected",   "normal"],
			["normal",     "error",      "given",      "highlighted","given"],
			["placed",     "normal",     "same_number","normal",     "placed"],
			["normal",     "given",      "normal",     "pencil",     "normal"],
		]
		var numbers := [
			[5, 3, 0, 7, 0],
			[0, 0, 8, 0, 4],
			[2, 0, 0, 0, 6],
			[0, 9, 0, 0, 0],
		]

		var font := ThemeDB.fallback_font
		var font_size := int(cell_h * 0.5)

		for r in rows:
			for c in cols:
				var state: String = layout[r][c]
				var rect := Rect2(c * cell_w, r * cell_h, cell_w, cell_h)

				# Cell background
				var bg_color: Color
				match state:
					"selected":    bg_color = _c("cell_selected")
					"error":       bg_color = _c("cell_error")
					"highlighted": bg_color = _c("cell_highlighted")
					"same_number": bg_color = _c("cell_same_number")
					"given":       bg_color = _c("cell_given")
					_:             bg_color = _c("cell_background")
				draw_rect(rect, bg_color)

				# Grid lines
				var is_thick_v := c % cols == 0
				var is_thick_h := r % rows == 0
				var line_color_v := _c("grid_line_thick") if is_thick_v else _c("grid_line_thin")
				var line_color_h := _c("grid_line_thick") if is_thick_h else _c("grid_line_thin")
				draw_line(Vector2(rect.position.x, rect.position.y),
						  Vector2(rect.position.x, rect.end.y), line_color_v, 1.5)
				draw_line(Vector2(rect.position.x, rect.position.y),
						  Vector2(rect.end.x, rect.position.y), line_color_h, 1.5)

				# Text
				var num: int = numbers[r][c]
				if state == "pencil" and num == 0:
					# Draw pencil marks (small numbers)
					var pm_size := font_size / 2
					for pm in [1, 2, 4]:
						var px := int((pm - 1) % 3)
						var py := int((pm - 1) / 3)
						var pm_pos := Vector2(
							rect.position.x + (px + 0.2) * cell_w / 3.0,
							rect.position.y + (py + 0.8) * cell_h / 3.0
						)
						draw_string(font, pm_pos, str(pm), HORIZONTAL_ALIGNMENT_LEFT, -1, pm_size, _c("text_pencil"))
				elif num > 0:
					var text_color: Color
					match state:
						"given":  text_color = _c("text_given")
						"error":  text_color = _c("text_error")
						_:        text_color = _c("text_placed")
					var text_pos := Vector2(
						rect.position.x + cell_w * 0.5,
						rect.position.y + cell_h * 0.72
					)
					draw_string(font, text_pos, str(num), HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)

		# Right and bottom border
		draw_line(Vector2(w, 0), Vector2(w, h), _c("grid_line_thick"), 1.5)
		draw_line(Vector2(0, h), Vector2(w, h), _c("grid_line_thick"), 1.5)


	func _c(key: String) -> Color:
		return _palette.get(key, Color.MAGENTA)
