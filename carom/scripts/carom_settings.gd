class_name CaromSettings
extends Control

## Carom-specific settings panel and data store.
## Static data is accessible from anywhere without instantiation.
## Instantiate as a Control to show the settings UI panel.

enum AimMode {
	DRAG = 0,       ## Drag anywhere to aim; tap to fire.
	HOLD_ZONES = 1, ## Hold left/right half of screen to turn; tap to fire.
	GYROSCOPE = 2,  ## Tilt device to aim; tap to fire.
}

enum ReloadButtonSide {
	RIGHT = 0,
	LEFT = 1,
}

const SAVE_PATH := "user://carom_settings.cfg"
const CAMERA_MODE_TOP_DOWN := "top_down"
const CAMERA_MODE_ISOMETRIC := "isometric"
const CAMERA_MODE_TOP_DOWN_INDEX := 0
const CAMERA_MODE_ISOMETRIC_INDEX := 1

# --- Static data (singleton-like, persists across scene changes) ---

static var aim_mode: int = AimMode.DRAG
static var reload_button_side: int = ReloadButtonSide.RIGHT
static var camera_mode: String = CAMERA_MODE_TOP_DOWN
static var auto_reload: bool = false
static var _loaded: bool = false

signal closed
## Emitted when any setting value changes (e.g. reload button side).
## HUD listens to this to reposition the reload button immediately.
signal setting_changed


# --- Static helpers ---

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	aim_mode = config.get_value("carom", "aim_mode", AimMode.DRAG)
	reload_button_side = config.get_value("carom", "reload_button_side", ReloadButtonSide.RIGHT)
	camera_mode = normalize_camera_mode(config.get_value("carom", "camera_mode", CAMERA_MODE_TOP_DOWN))
	auto_reload = config.get_value("carom", "auto_reload", false)


static func save() -> void:
	var config := ConfigFile.new()
	config.set_value("carom", "aim_mode", aim_mode)
	config.set_value("carom", "reload_button_side", reload_button_side)
	config.set_value("carom", "camera_mode", camera_mode)
	config.set_value("carom", "auto_reload", auto_reload)
	config.save(SAVE_PATH)


static func normalize_camera_mode(mode: String) -> String:
	if mode == CAMERA_MODE_TOP_DOWN or mode == CAMERA_MODE_ISOMETRIC:
		return mode
	return CAMERA_MODE_TOP_DOWN


## Returns true if this device likely has a usable gyroscope sensor.
static func is_gyroscope_supported() -> bool:
	return OS.has_feature("mobile")


# --- Panel UI ---

func _ready() -> void:
	CaromSettings.ensure_loaded()
	custom_minimum_size = Vector2(300, 340)
	_build_ui()


func _build_ui() -> void:
	# Panel background
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 0.97)
	style.border_color = Color(0.2, 0.6, 1.0, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Carom Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	vbox.add_child(title)

	# Aim Mode row
	var aim_row := HBoxContainer.new()
	aim_row.add_theme_constant_override("separation", 8)
	vbox.add_child(aim_row)

	var aim_label := Label.new()
	aim_label.text = "Aim Mode"
	aim_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aim_row.add_child(aim_label)

	var aim_picker := OptionButton.new()
	aim_picker.add_item("Drag")
	aim_picker.add_item("Hold Zones")
	if CaromSettings.is_gyroscope_supported():
		aim_picker.add_item("Gyroscope")
	else:
		# If Gyroscope was saved but this device has no gyro, reset to Drag.
		if CaromSettings.aim_mode == CaromSettings.AimMode.GYROSCOPE:
			CaromSettings.aim_mode = CaromSettings.AimMode.DRAG
			CaromSettings.save()
	aim_picker.selected = CaromSettings.aim_mode
	aim_picker.item_selected.connect(func(idx: int) -> void:
		CaromSettings.aim_mode = idx
		CaromSettings.save()
		setting_changed.emit()
	)
	aim_row.add_child(aim_picker)

	# Reload Button Side row
	var side_row := HBoxContainer.new()
	side_row.add_theme_constant_override("separation", 8)
	vbox.add_child(side_row)

	var side_label := Label.new()
	side_label.text = "Reload Button Side"
	side_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_row.add_child(side_label)

	var side_picker := OptionButton.new()
	side_picker.add_item("Right")
	side_picker.add_item("Left")
	side_picker.selected = CaromSettings.reload_button_side
	side_picker.item_selected.connect(func(idx: int) -> void:
		CaromSettings.reload_button_side = idx
		CaromSettings.save()
		setting_changed.emit()
	)
	side_row.add_child(side_picker)

	# Auto-reload row
	var auto_row := HBoxContainer.new()
	auto_row.add_theme_constant_override("separation", 8)
	vbox.add_child(auto_row)

	var auto_label := Label.new()
	auto_label.text = "Auto Reload"
	auto_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_row.add_child(auto_label)

	var auto_check := CheckButton.new()
	auto_check.button_pressed = CaromSettings.auto_reload
	auto_check.toggled.connect(func(on: bool) -> void:
		CaromSettings.auto_reload = on
		CaromSettings.save()
		setting_changed.emit()
	)
	auto_row.add_child(auto_check)

	# Camera mode row
	var camera_row := HBoxContainer.new()
	camera_row.add_theme_constant_override("separation", 8)
	vbox.add_child(camera_row)

	var camera_label := Label.new()
	camera_label.text = "Camera"
	camera_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_row.add_child(camera_label)

	var camera_picker := OptionButton.new()
	camera_picker.add_item("Top Down")
	camera_picker.add_item("Isometric")
	camera_picker.selected = (
		CaromSettings.CAMERA_MODE_ISOMETRIC_INDEX
		if CaromSettings.camera_mode == CaromSettings.CAMERA_MODE_ISOMETRIC
		else CaromSettings.CAMERA_MODE_TOP_DOWN_INDEX
	)
	camera_picker.item_selected.connect(func(idx: int) -> void:
		CaromSettings.camera_mode = (
			CaromSettings.CAMERA_MODE_ISOMETRIC
			if idx == CaromSettings.CAMERA_MODE_ISOMETRIC_INDEX
			else CaromSettings.CAMERA_MODE_TOP_DOWN
		)
		CaromSettings.save()
		setting_changed.emit()
	)
	camera_row.add_child(camera_picker)

	# Aim mode description
	var desc_label := Label.new()
	desc_label.text = _get_aim_mode_description(CaromSettings.aim_mode)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(desc_label)

	# Update description when aim mode changes
	aim_picker.item_selected.connect(func(idx: int) -> void:
		desc_label.text = _get_aim_mode_description(idx)
	)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(100, 40)
	close_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_btn.pressed.connect(func() -> void:
		closed.emit()
		queue_free()
	)
	vbox.add_child(close_btn)


func _get_aim_mode_description(mode: int) -> String:
	match mode:
		CaromSettings.AimMode.DRAG:
			return "Drag anywhere on screen to aim. Tap (no drag) to fire."
		CaromSettings.AimMode.HOLD_ZONES:
			return "Hold left half to turn left, right half to turn right. Tap to fire."
		CaromSettings.AimMode.GYROSCOPE:
			return "Tilt your device to aim. Tap the screen to fire."
	return ""
