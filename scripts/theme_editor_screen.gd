extends Control

## Custom palette editor screen.
## Presents 4 ColorPickerButtons (Background, Accent, Secondary, Error),
## a live-preview demo board, and Reset / Save controls.
## Saving writes the palette to PlatformSettings and switches to "custom" mode.

@onready var back_button: Button = %BackButton
@onready var save_button: Button = %SaveButton
@onready var reset_button: Button = %ResetButton
@onready var bg_picker: ColorPickerButton = %BgPicker
@onready var accent_picker: ColorPickerButton = %AccentPicker
@onready var secondary_picker: ColorPickerButton = %SecondaryPicker
@onready var error_picker: ColorPickerButton = %ErrorPicker
@onready var demo_board: Control = %DemoBoard

## Neon palette defaults — what "Reset to Default" restores.
const DEFAULT_BG := Color(0.04, 0.04, 0.1)
const DEFAULT_ACCENT := Color(0.0, 1.5, 1.5)
const DEFAULT_SECONDARY := Color(2.0, 0.3, 1.8)
const DEFAULT_ERROR := Color(2.0, 0.0, 0.2)


func _ready() -> void:
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)

	# Initialise pickers from saved custom palette
	bg_picker.color = PlatformSettings.custom_palette_bg
	accent_picker.color = PlatformSettings.custom_palette_accent
	secondary_picker.color = PlatformSettings.custom_palette_secondary
	error_picker.color = PlatformSettings.custom_palette_error

	bg_picker.color_changed.connect(func(_c: Color) -> void: _on_color_changed())
	accent_picker.color_changed.connect(func(_c: Color) -> void: _on_color_changed())
	secondary_picker.color_changed.connect(func(_c: Color) -> void: _on_color_changed())
	error_picker.color_changed.connect(func(_c: Color) -> void: _on_color_changed())

	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(Scenes.SETTINGS)
	)
	save_button.pressed.connect(_on_save_pressed)
	reset_button.pressed.connect(_on_reset_pressed)

	_on_color_changed()
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


func _on_color_changed() -> void:
	if demo_board:
		demo_board.set_palette(
			bg_picker.color,
			accent_picker.color,
			secondary_picker.color,
			error_picker.color
		)


func _on_save_pressed() -> void:
	PlatformSettings.custom_palette_bg = bg_picker.color
	PlatformSettings.custom_palette_accent = accent_picker.color
	PlatformSettings.custom_palette_secondary = secondary_picker.color
	PlatformSettings.custom_palette_error = error_picker.color
	PlatformSettings.dark_mode = "custom"
	PlatformSettings.save_settings()
	SceneTransition.transition_to(Scenes.SETTINGS)


func _on_reset_pressed() -> void:
	bg_picker.color = DEFAULT_BG
	accent_picker.color = DEFAULT_ACCENT
	secondary_picker.color = DEFAULT_SECONDARY
	error_picker.color = DEFAULT_ERROR
	_on_color_changed()


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)
