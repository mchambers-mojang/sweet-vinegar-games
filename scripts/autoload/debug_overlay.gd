extends CanvasLayer

const MAX_ANALYTICS_EVENTS := 8
const VERSION_TAP_WINDOW_SEC := 1.0

var _enabled: bool = false
var _overlay_active: bool = false
var _version_taps: Array[float] = []
var _touch_points: Dictionary = {} # id -> Vector2
var _analytics_tail: Array[String] = []
var _last_scene_path: String = ""

var _root: Control
var _draw_layer: Control
var _info_label: Label
var _analytics_label: RichTextLabel
var _settings_button: Button
var _settings_panel: PanelContainer


func _ready() -> void:
	_enabled = OS.is_debug_build()
	if not _enabled:
		visible = false
		set_process(false)
		set_process_input(false)
		return

	layer = 110
	_build_ui()
	get_tree().root.size_changed.connect(func() -> void:
		if _overlay_active:
			_position_right_side_controls()
			_draw_layer.queue_redraw()
	)
	set_process(true)
	set_process_input(true)
	log_analytics_event("debug_overlay_ready")


func register_version_label_tap() -> void:
	if not _enabled:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_version_taps.append(now)
	while _version_taps.size() > 0 and now - _version_taps[0] > VERSION_TAP_WINDOW_SEC:
		_version_taps.remove_at(0)
	if _version_taps.size() >= 5:
		_version_taps.clear()
		_toggle_overlay("version_tap")


func log_analytics_event(event_name: String) -> void:
	if not _enabled:
		return
	var ts := Time.get_time_string_from_system()
	_analytics_tail.append("%s  %s" % [ts, event_name])
	if _analytics_tail.size() > MAX_ANALYTICS_EVENTS:
		_analytics_tail.remove_at(0)


func _input(event: InputEvent) -> void:
	if not _enabled:
		return

	# Global keyboard shortcut: Ctrl+Shift+D or F12 to toggle debug overlay
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_F12 or (key.keycode == KEY_D and key.ctrl_pressed and key.shift_pressed):
				_toggle_overlay("keyboard")
				get_viewport().set_input_as_handled()
				return

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touch_points[st.index] = st.position
			# 4-finger tap toggles debug overlay on mobile
			if _touch_points.size() >= 4:
				_toggle_overlay("four_finger_tap")
		else:
			_touch_points.erase(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touch_points[sd.index] = sd.position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_touch_points[-1] = mb.position
			else:
				_touch_points.erase(-1)
	elif event is InputEventMouseMotion and _touch_points.has(-1):
		var mm := event as InputEventMouseMotion
		_touch_points[-1] = mm.position


func _process(_delta: float) -> void:
	if not _enabled:
		return

	_track_scene_changes()

	if _overlay_active:
		_refresh_overlay_text()
		_draw_layer.queue_redraw()


func _track_scene_changes() -> void:
	var current := get_tree().current_scene
	if current == null:
		return
	var scene_path := current.scene_file_path
	if scene_path.is_empty():
		scene_path = current.name
	if scene_path != _last_scene_path:
		_last_scene_path = scene_path
		log_analytics_event("scene_changed:%s" % scene_path)


func _toggle_overlay(source: String) -> void:
	_overlay_active = not _overlay_active
	log_analytics_event("overlay_%s:%s" % ["on" if _overlay_active else "off", source])
	_update_overlay_visibility()


func _build_ui() -> void:
	var safe_top := float(SafeAreaManager.get_insets().get("top", 0))

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_draw_layer = Control.new()
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_layer.draw.connect(_draw_debug_overlay)
	_root.add_child(_draw_layer)

	_info_label = Label.new()
	_info_label.position = Vector2(10, safe_top + 10)
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_info_label)

	_analytics_label = RichTextLabel.new()
	_analytics_label.position = Vector2(10, safe_top + 100)
	_analytics_label.size = Vector2(460, 180)
	_analytics_label.bbcode_enabled = false
	_analytics_label.fit_content = false
	_analytics_label.scroll_active = false
	_analytics_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_analytics_label)

	_settings_button = Button.new()
	_settings_button.text = "Debug"
	_settings_button.position = Vector2(0, safe_top + 10)
	_settings_button.size = Vector2(86, 34)
	_settings_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_button.pressed.connect(func() -> void:
		_settings_panel.visible = not _settings_panel.visible
	)
	_root.add_child(_settings_button)

	_settings_panel = PanelContainer.new()
	_settings_panel.position = Vector2(0, safe_top + 50)
	_settings_panel.size = Vector2(280, 300)
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_settings_panel)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	_settings_panel.add_child(list)

	_add_setting_toggle(list, "FPS counter", "fps")
	_add_setting_toggle(list, "Touch points", "touch")
	_add_setting_toggle(list, "Safe area bounds", "safe_area")
	_add_setting_toggle(list, "Current scene", "scene")
	_add_setting_toggle(list, "Memory usage", "memory")
	_add_setting_toggle(list, "Analytics tail", "analytics")
	_add_setting_toggle(list, "Grid coordinates", "grid")

	var reset_btn := Button.new()
	reset_btn.text = "Reset Achievements"
	reset_btn.pressed.connect(func() -> void:
		AchievementManager.reset_all_progress()
		log_analytics_event("debug_cheat:reset_achievements")
	)
	list.add_child(reset_btn)

	_update_overlay_visibility()


func _update_overlay_visibility() -> void:
	_info_label.visible = _overlay_active
	_analytics_label.visible = _overlay_active and DebugFlags.debug_show_analytics_tail
	_settings_button.visible = _overlay_active
	_settings_panel.visible = false
	_draw_layer.visible = _overlay_active
	if _overlay_active:
		_position_right_side_controls()
		_refresh_overlay_text()


func _position_right_side_controls() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_settings_button.position.x = viewport_size.x - _settings_button.size.x - 10
	_settings_panel.position.x = viewport_size.x - _settings_panel.size.x - 10


func _refresh_overlay_text() -> void:
	var lines: Array[String] = []
	if DebugFlags.debug_show_fps:
		lines.append("FPS: %d" % Engine.get_frames_per_second())
	if DebugFlags.debug_show_scene_name:
		lines.append("Scene: %s" % _get_current_scene_name())
	if DebugFlags.debug_show_memory:
		var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
		lines.append("Memory: %.1f MB" % mem)
	if DebugFlags.debug_show_grid_coordinates:
		lines.append("Grid: %s" % _get_grid_coordinate_label())
	_info_label.text = "\n".join(PackedStringArray(lines))
	_analytics_label.position.y = _info_label.position.y + _info_label.get_combined_minimum_size().y + 10.0

	if DebugFlags.debug_show_analytics_tail:
		_analytics_label.text = "Analytics events:\n%s" % "\n".join(PackedStringArray(_analytics_tail))


func _draw_debug_overlay() -> void:
	if DebugFlags.debug_show_touch_points:
		for id in _touch_points.keys():
			var pos: Vector2 = _touch_points[id]
			_draw_layer.draw_circle(pos, 22.0, Color(0.1, 1.0, 1.0, 0.18))
			_draw_layer.draw_circle(pos, 8.0, Color(0.1, 1.0, 1.0, 0.95))

	if DebugFlags.debug_show_safe_area:
		var insets := SafeAreaManager.get_insets()
		var viewport_size := get_viewport().get_visible_rect().size
		var left := float(insets.get("left", 0))
		var top := float(insets.get("top", 0))
		var right := float(insets.get("right", 0))
		var bottom := float(insets.get("bottom", 0))
		var safe_rect := Rect2(
			Vector2(left, top),
			Vector2(maxf(1.0, viewport_size.x - left - right), maxf(1.0, viewport_size.y - top - bottom))
		)
		_draw_layer.draw_rect(safe_rect, Color(0.2, 1.0, 0.2, 0.9), false, 2.0)


func _get_current_scene_name() -> String:
	var current := get_tree().current_scene
	if current == null:
		return "--"
	if current.scene_file_path.is_empty():
		return current.name
	return current.scene_file_path.get_file()


func _get_grid_coordinate_label() -> String:
	var point := get_viewport().get_mouse_position()
	# Prefer active touch point on mobile while still falling back to mouse on desktop.
	for id in _touch_points.keys():
		point = _touch_points[id]
		break

	for node in get_tree().get_nodes_in_group("debug_grid_source"):
		if node is Control:
			var control := node as Control
			if not control.visible:
				continue
			if not control.get_global_rect().has_point(point):
				continue
			if node.has_method("debug_screen_to_grid"):
				var cell: Variant = node.call("debug_screen_to_grid", point)
				if cell is Vector2i:
					var grid_cell := cell as Vector2i
					if grid_cell.x >= 0 and grid_cell.y >= 0:
						return "%s (%d, %d)" % [control.name, grid_cell.x, grid_cell.y]
	return "--"


func _add_setting_toggle(list: VBoxContainer, title: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var toggle := CheckButton.new()
	toggle.button_pressed = _get_debug_setting(key)
	toggle.toggled.connect(func(value: bool) -> void:
		_set_debug_setting(key, value)
	)
	row.add_child(toggle)
	list.add_child(row)


func _get_debug_setting(key: String) -> bool:
	match key:
		"fps":
			return DebugFlags.debug_show_fps
		"touch":
			return DebugFlags.debug_show_touch_points
		"safe_area":
			return DebugFlags.debug_show_safe_area
		"scene":
			return DebugFlags.debug_show_scene_name
		"memory":
			return DebugFlags.debug_show_memory
		"analytics":
			return DebugFlags.debug_show_analytics_tail
		"grid":
			return DebugFlags.debug_show_grid_coordinates
	return true


func _set_debug_setting(key: String, value: bool) -> void:
	match key:
		"fps":
			DebugFlags.debug_show_fps = value
		"touch":
			DebugFlags.debug_show_touch_points = value
		"safe_area":
			DebugFlags.debug_show_safe_area = value
		"scene":
			DebugFlags.debug_show_scene_name = value
		"memory":
			DebugFlags.debug_show_memory = value
		"analytics":
			DebugFlags.debug_show_analytics_tail = value
		"grid":
			DebugFlags.debug_show_grid_coordinates = value
	DebugFlags.save_settings()
	log_analytics_event("debug_setting:%s=%s" % [key, value])
	_update_overlay_visibility()
	_draw_layer.queue_redraw()
