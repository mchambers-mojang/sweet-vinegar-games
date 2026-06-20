class_name CaromOnlineMenu
extends Control

## Standalone multiplayer lobby screen for Carom.
##
## Presents two top-level actions:
##   • Create Room — player becomes host; shows waiting state with room code.
##   • Join Room — player enters a 4-character code and connects.
##
## Not a GameMenu subclass — driven directly by a match/flow controller.
## Safe area is applied automatically by SceneTransition._auto_apply_safe_area().

signal room_create_requested
signal room_join_requested(code: String)
signal cancelled

## Valid characters for room codes (unambiguous subset of alphanumerics).
const VALID_CHARS := "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
const CODE_LENGTH := 4
const CODE_PLACEHOLDER := "----"

## Colours matching the existing Carom dark-panel style.
const BG_COLOR      := Color(0.04, 0.06, 0.12, 0.96)
const BORDER_COLOR  := Color(0.2, 0.6, 1.0, 0.8)
const ACCENT_COLOR  := Color(0.3, 0.85, 1.0)
const DIM_COLOR     := Color(0.6, 0.7, 0.85)
const CODE_COLOR    := Color(1.0, 0.9, 0.3)

# --- View references ---

var _lobby_view: Control = null
var _create_view: Control = null
var _join_view: Control = null

var _room_code_label: Label = null
var _code_input: LineEdit = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Called by the match/flow controller once a room code is assigned.
func set_room_code(code: String) -> void:
	if _room_code_label:
		_room_code_label.text = code if code != "" else CODE_PLACEHOLDER


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Full-screen dim backdrop
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.65)
	add_child(backdrop)

	# Centred card panel — full-rect MarginContainer provides safe-area padding,
	# CenterContainer keeps the card visually centred.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var center := CenterContainer.new()
	margin.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = BG_COLOR
	panel_style.border_color = BORDER_COLOR
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 28.0
	panel_style.content_margin_right = 28.0
	panel_style.content_margin_top = 28.0
	panel_style.content_margin_bottom = 28.0
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 0)
	panel.add_child(root_vbox)

	_lobby_view = _build_lobby_view()
	_create_view = _build_create_view()
	_join_view   = _build_join_view()

	root_vbox.add_child(_lobby_view)
	root_vbox.add_child(_create_view)
	root_vbox.add_child(_join_view)

	_show_lobby()


# --- Lobby (initial) view ---

func _build_lobby_view() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)

	var title := _make_title("Online Play")
	vbox.add_child(title)

	var sep := _make_separator()
	vbox.add_child(sep)

	var create_btn := _make_primary_button("Create Room")
	create_btn.pressed.connect(_on_create_room_pressed)
	vbox.add_child(create_btn)

	var join_btn := _make_secondary_button("Join Room")
	join_btn.pressed.connect(_on_join_room_pressed)
	vbox.add_child(join_btn)

	var cancel_btn := _make_cancel_button()
	cancel_btn.pressed.connect(_on_cancelled)
	vbox.add_child(cancel_btn)

	return vbox


# --- Create Room (waiting) view ---

func _build_create_view() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)

	var title := _make_title("Create Room")
	vbox.add_child(title)

	var sep := _make_separator()
	vbox.add_child(sep)

	var waiting_label := Label.new()
	waiting_label.text = "Waiting for opponent…"
	waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_label.add_theme_color_override("font_color", DIM_COLOR)
	waiting_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(waiting_label)

	var code_label_caption := Label.new()
	code_label_caption.text = "Room Code"
	code_label_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label_caption.add_theme_color_override("font_color", DIM_COLOR)
	code_label_caption.add_theme_font_size_override("font_size", 13)
	vbox.add_child(code_label_caption)

	_room_code_label = Label.new()
	_room_code_label.text = CODE_PLACEHOLDER
	_room_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_code_label.add_theme_color_override("font_color", CODE_COLOR)
	_room_code_label.add_theme_font_size_override("font_size", 48)
	vbox.add_child(_room_code_label)

	var cancel_btn := _make_cancel_button()
	cancel_btn.pressed.connect(_on_create_cancelled)
	vbox.add_child(cancel_btn)

	return vbox


# --- Join Room view ---

func _build_join_view() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)

	var title := _make_title("Join Room")
	vbox.add_child(title)

	var sep := _make_separator()
	vbox.add_child(sep)

	var instructions := Label.new()
	instructions.text = "Enter the 4-character room code:"
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_color_override("font_color", DIM_COLOR)
	instructions.add_theme_font_size_override("font_size", 14)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(instructions)

	_code_input = LineEdit.new()
	_code_input.max_length = CODE_LENGTH
	_code_input.placeholder_text = "e.g. A3K7"
	_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_input.add_theme_font_size_override("font_size", 32)
	_code_input.add_theme_color_override("font_color", CODE_COLOR)

	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.07, 0.10, 0.20, 1.0)
	input_style.border_color = BORDER_COLOR
	input_style.set_border_width_all(2)
	input_style.set_corner_radius_all(8)
	input_style.content_margin_left = 12.0
	input_style.content_margin_right = 12.0
	input_style.content_margin_top = 10.0
	input_style.content_margin_bottom = 10.0
	_code_input.add_theme_stylebox_override("normal", input_style)

	_code_input.text_changed.connect(_on_code_input_changed)
	_code_input.text_submitted.connect(_on_code_submitted)
	vbox.add_child(_code_input)

	var connect_btn := _make_primary_button("Connect")
	connect_btn.pressed.connect(_on_connect_pressed)
	vbox.add_child(connect_btn)

	var cancel_btn := _make_cancel_button()
	cancel_btn.pressed.connect(_on_join_cancelled)
	vbox.add_child(cancel_btn)

	return vbox


# ---------------------------------------------------------------------------
# Widget helpers
# ---------------------------------------------------------------------------

func _make_title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	return lbl


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.2, 0.6, 1.0, 0.3)
	sep_style.content_margin_top = 1.0
	sep_style.content_margin_bottom = 1.0
	sep.add_theme_stylebox_override("separator", sep_style)
	return sep


func _make_primary_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 16)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.4, 0.85, 1.0)
	normal.set_corner_radius_all(8)
	normal.content_margin_top = 12.0
	normal.content_margin_bottom = 12.0
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.15, 0.5, 1.0, 1.0)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed_style := normal.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.08, 0.3, 0.7, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	return btn


func _make_secondary_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 16)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.15, 0.28, 1.0)
	normal.border_color = BORDER_COLOR
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_top = 12.0
	normal.content_margin_bottom = 12.0
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.12, 0.22, 0.40, 1.0)
	btn.add_theme_stylebox_override("hover", hover)

	return btn


func _make_cancel_button() -> Button:
	var btn := Button.new()
	btn.text = "Cancel"
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", DIM_COLOR)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_corner_radius_all(6)
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	btn.add_theme_stylebox_override("hover", hover_style)

	return btn


# ---------------------------------------------------------------------------
# View switching
# ---------------------------------------------------------------------------

func _show_lobby() -> void:
	_lobby_view.visible = true
	_create_view.visible = false
	_join_view.visible   = false


func _show_create() -> void:
	_lobby_view.visible = false
	_create_view.visible = true
	_join_view.visible   = false
	# Reset placeholder until code is delivered externally.
	if _room_code_label:
		_room_code_label.text = CODE_PLACEHOLDER


func _show_join() -> void:
	_lobby_view.visible = false
	_create_view.visible = false
	_join_view.visible   = true
	if _code_input:
		_code_input.text = ""
		_code_input.call_deferred("grab_focus")


# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

## Filters the code input to only VALID_CHARS and enforces upper-case.
func _on_code_input_changed(new_text: String) -> void:
	var filtered := ""
	for ch in new_text.to_upper():
		if ch in VALID_CHARS:
			filtered += ch
	if filtered != new_text.to_upper():
		_code_input.text = filtered
		_code_input.caret_column = filtered.length()


func _on_code_submitted(text: String) -> void:
	_try_join(text)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_create_room_pressed() -> void:
	_show_create()
	room_create_requested.emit()


func _on_join_room_pressed() -> void:
	_show_join()


func _on_connect_pressed() -> void:
	_try_join(_code_input.text if _code_input else "")


func _try_join(raw_code: String) -> void:
	var code := raw_code.strip_edges().to_upper()
	if code.length() != CODE_LENGTH:
		return
	room_join_requested.emit(code)


func _on_create_cancelled() -> void:
	_show_lobby()
	cancelled.emit()


func _on_join_cancelled() -> void:
	_show_lobby()
	cancelled.emit()


func _on_cancelled() -> void:
	cancelled.emit()
