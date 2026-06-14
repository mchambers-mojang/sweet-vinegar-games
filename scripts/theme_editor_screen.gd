extends Control

## Custom palette editor screen.
## Presents 4 ColorPickerButton + Glow Intensity slider pairs (Background, Accent, Secondary, Error),
## a live-preview demo board, and Reset / Save controls.
## Each picker shows a normalised [0,1] color; the glow slider (1.0–3.0) multiplies it
## to produce the final HDR output stored in PlatformSettings.
## Saving writes the palette to PlatformSettings and switches to "custom" mode.

@onready var back_button: Button = %BackButton
@onready var save_button: Button = %SaveButton
@onready var reset_button: Button = %ResetButton
@onready var bg_picker: ColorPickerButton = %BgPicker
@onready var accent_picker: ColorPickerButton = %AccentPicker
@onready var secondary_picker: ColorPickerButton = %SecondaryPicker
@onready var error_picker: ColorPickerButton = %ErrorPicker
@onready var bg_glow: HSlider = %BgGlowSlider
@onready var accent_glow: HSlider = %AccentGlowSlider
@onready var secondary_glow: HSlider = %SecondaryGlowSlider
@onready var error_glow: HSlider = %ErrorGlowSlider
@onready var demo_board: Control = %DemoBoard

## Neon palette defaults — what "Reset to Default" restores.
## These are the picker (normalised) colors; multiply by *_GLOW to get the HDR value.
const DEFAULT_BG := Color(0.04, 0.04, 0.1)
const DEFAULT_BG_GLOW := 1.0
const DEFAULT_ACCENT := Color(0.0, 1.0, 1.0)
const DEFAULT_ACCENT_GLOW := 1.5
const DEFAULT_SECONDARY := Color(1.0, 0.15, 0.9)
const DEFAULT_SECONDARY_GLOW := 2.0
const DEFAULT_ERROR := Color(1.0, 0.0, 0.1)
const DEFAULT_ERROR_GLOW := 2.0


func _ready() -> void:
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)

	# Decompose stored HDR colors into picker color + glow intensity
	_init_picker_and_glow(bg_picker, bg_glow, PlatformSettings.custom_palette_bg)
	_init_picker_and_glow(accent_picker, accent_glow, PlatformSettings.custom_palette_accent)
	_init_picker_and_glow(secondary_picker, secondary_glow, PlatformSettings.custom_palette_secondary)
	_init_picker_and_glow(error_picker, error_glow, PlatformSettings.custom_palette_error)

	bg_picker.color_changed.connect(func(_c: Color) -> void: _on_color_changed())
	accent_picker.color_changed.connect(func(_c: Color) -> void: _on_color_changed())
	secondary_picker.color_changed.connect(func(_c: Color) -> void: _on_color_changed())
	error_picker.color_changed.connect(func(_c: Color) -> void: _on_color_changed())
	bg_glow.value_changed.connect(func(_v: float) -> void: _on_color_changed())
	accent_glow.value_changed.connect(func(_v: float) -> void: _on_color_changed())
	secondary_glow.value_changed.connect(func(_v: float) -> void: _on_color_changed())
	error_glow.value_changed.connect(func(_v: float) -> void: _on_color_changed())

	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(Scenes.SETTINGS)
	)
	save_button.pressed.connect(_on_save_pressed)
	reset_button.pressed.connect(_on_reset_pressed)

	_on_color_changed()
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


## Splits an HDR color into its normalised picker color and glow multiplier.
## glow = max channel clamped to [1, 3]; picker = hdr / glow (all channels <= 1).
## When max(r,g,b) < 1.0 glow clamps to 1.0 and the picker receives the color unchanged,
## so non-HDR values (e.g. background) round-trip without modification.
func _init_picker_and_glow(picker: ColorPickerButton, slider: HSlider, hdr: Color) -> void:
	var glow := clampf(maxf(hdr.r, hdr.g, hdr.b), 1.0, 3.0)
	picker.color = Color(hdr.r / glow, hdr.g / glow, hdr.b / glow, 1.0)
	slider.value = glow


## Returns the HDR output color: picker.color multiplied by glow intensity.
func _hdr(picker: ColorPickerButton, slider: HSlider) -> Color:
	var g := slider.value
	return Color(picker.color.r * g, picker.color.g * g, picker.color.b * g, 1.0)


func _on_color_changed() -> void:
	if demo_board:
		demo_board.set_palette(
			_hdr(bg_picker, bg_glow),
			_hdr(accent_picker, accent_glow),
			_hdr(secondary_picker, secondary_glow),
			_hdr(error_picker, error_glow)
		)


func _on_save_pressed() -> void:
	PlatformSettings.custom_palette_bg = _hdr(bg_picker, bg_glow)
	PlatformSettings.custom_palette_accent = _hdr(accent_picker, accent_glow)
	PlatformSettings.custom_palette_secondary = _hdr(secondary_picker, secondary_glow)
	PlatformSettings.custom_palette_error = _hdr(error_picker, error_glow)
	PlatformSettings.dark_mode = "custom"
	PlatformSettings.save_settings()
	SceneTransition.transition_to(Scenes.SETTINGS)


func _on_reset_pressed() -> void:
	bg_picker.color = DEFAULT_BG
	bg_glow.value = DEFAULT_BG_GLOW
	accent_picker.color = DEFAULT_ACCENT
	accent_glow.value = DEFAULT_ACCENT_GLOW
	secondary_picker.color = DEFAULT_SECONDARY
	secondary_glow.value = DEFAULT_SECONDARY_GLOW
	error_picker.color = DEFAULT_ERROR
	error_glow.value = DEFAULT_ERROR_GLOW
	_on_color_changed()


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)
