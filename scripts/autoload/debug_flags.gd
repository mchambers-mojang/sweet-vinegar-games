extends Node

## Debug-only overlay flags and dev keyboard shortcuts

signal settings_changed

const SAVE_PATH := "user://settings.cfg"

var debug_show_fps: bool = true
var debug_show_touch_points: bool = true
var debug_show_safe_area: bool = true
var debug_show_scene_name: bool = true
var debug_show_memory: bool = true
var debug_show_analytics_tail: bool = true
var debug_show_grid_coordinates: bool = true
var debug_fire_screen_shake: bool = false


func _ready() -> void:
	load_settings()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		# Ctrl+Shift+R: reload current scene (note: script changes require F5 restart)
		if key.keycode == KEY_R and key.ctrl_pressed and key.shift_pressed:
			print("Reloading current scene...")
			get_tree().reload_current_scene()
			get_viewport().set_input_as_handled()
		# Ctrl+Shift+C: copy latest crash report for easy sharing
		elif key.keycode == KEY_C and key.ctrl_pressed and key.shift_pressed:
			if CrashWriter.copy_latest_report_to_clipboard():
				print("Copied latest crash report to clipboard")
			else:
				print("No crash report found to copy")
			get_viewport().set_input_as_handled()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("debug", "show_fps", debug_show_fps)
	config.set_value("debug", "show_touch_points", debug_show_touch_points)
	config.set_value("debug", "show_safe_area", debug_show_safe_area)
	config.set_value("debug", "show_scene_name", debug_show_scene_name)
	config.set_value("debug", "show_memory", debug_show_memory)
	config.set_value("debug", "show_analytics_tail", debug_show_analytics_tail)
	config.set_value("debug", "show_grid_coordinates", debug_show_grid_coordinates)
	config.set_value("debug", "fire_screen_shake", debug_fire_screen_shake)
	config.save(SAVE_PATH)
	settings_changed.emit()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	debug_show_fps = config.get_value("debug", "show_fps", debug_show_fps)
	debug_show_touch_points = config.get_value("debug", "show_touch_points", debug_show_touch_points)
	debug_show_safe_area = config.get_value("debug", "show_safe_area", debug_show_safe_area)
	debug_show_scene_name = config.get_value("debug", "show_scene_name", debug_show_scene_name)
	debug_show_memory = config.get_value("debug", "show_memory", debug_show_memory)
	debug_show_analytics_tail = config.get_value("debug", "show_analytics_tail", debug_show_analytics_tail)
	debug_show_grid_coordinates = config.get_value("debug", "show_grid_coordinates", debug_show_grid_coordinates)
	debug_fire_screen_shake = config.get_value("debug", "fire_screen_shake", debug_fire_screen_shake)
