class_name CaromMultiplayerResults
extends Control

signal menu_requested

const PANEL_SIZE := Vector2(320, 220)
const BG_COLOR := Color(0.08, 0.08, 0.12, 0.95)
const WIN_COLOR := Color(0.2, 1.0, 0.6, 0.9)
const LOSS_COLOR := Color(1.0, 0.35, 0.35, 0.9)
const FORFEIT_COLOR := Color(1.0, 0.85, 0.25, 0.9)

var _panel: PanelContainer = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _score_label: Label = null


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_ui()
	hide()
	get_tree().root.size_changed.connect(_center_panel)
	_center_panel()


func show_results(won: bool, your_score: int, their_score: int, forfeit: bool) -> void:
	_ensure_ui()
	visible = true
	var accent: Color = FORFEIT_COLOR if forfeit else (WIN_COLOR if won else LOSS_COLOR)
	if forfeit:
		_title_label.text = "Opponent Left"
		_subtitle_label.text = "You win by forfeit"
		_subtitle_label.visible = true
	else:
		_title_label.text = "You Win!" if won else "You Lose!"
		_subtitle_label.visible = false
	_score_label.text = "%d – %d" % [your_score, their_score]
	_title_label.add_theme_color_override("font_color", accent)
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style.border_color = accent
	_panel.add_theme_stylebox_override("panel", style)
	_center_panel()


func _ensure_ui() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "ResultsPanel"
	_panel.custom_minimum_size = PANEL_SIZE
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = WIN_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_subtitle_label)

	_score_label = Label.new()
	_score_label.name = "ScoreLabel"
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_score_label)

	var menu_button := Button.new()
	menu_button.name = "BackToMenuButton"
	menu_button.text = "Back to Menu"
	menu_button.custom_minimum_size = Vector2(150, 44)
	menu_button.pressed.connect(func() -> void:
		menu_requested.emit()
	)
	vbox.add_child(menu_button)


func _center_panel() -> void:
	if _panel == null:
		return
	var insets: Dictionary = SafeAreaManager.get_insets()
	var left: float = insets["left"]
	var right: float = insets["right"]
	var top: float = insets["top"]
	var bottom: float = insets["bottom"]
	var viewport_size: Vector2 = get_viewport_rect().size
	var safe_width: float = maxf(0.0, viewport_size.x - left - right)
	var safe_height: float = maxf(0.0, viewport_size.y - top - bottom)
	var panel_size: Vector2 = _panel.custom_minimum_size
	var x: float = left + (safe_width - panel_size.x) * 0.5
	var y: float = top + (safe_height - panel_size.y) * 0.5
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = x
	_panel.offset_top = y
	_panel.offset_right = x + panel_size.x
	_panel.offset_bottom = y + panel_size.y
