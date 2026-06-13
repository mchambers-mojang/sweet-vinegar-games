extends Control
class_name GameMenu

## Base class for all game menus. Handles shared ceremony (theme, safe area,
## settings navigation, back navigation, How-to-Play injection) and the
## continue/new-game/abandon flow with virtual hooks.
##
## Subclasses must define @onready vars for buttons they use:
##   continue_button, new_game_button, stats_button, settings_button, back_button
## Any of these may be null if the menu doesn't need that button.

# --- Virtual methods (override in subclasses) ---

## Unique game identifier (e.g. "sudoku", "shikaku")
func _get_game_id() -> String:
	return ""


## Scene path for this menu (used as settings return target)
func _get_menu_scene_path() -> String:
	return ""


## Scene path for the game screen
func _get_game_scene_path() -> String:
	return ""


## Scene path for the stats screen (empty = no stats button wiring)
func _get_stats_scene_path() -> String:
	return ""


## Help topic name (empty = no How-to-Play button)
func _get_help_topic() -> String:
	return ""


## Whether this menu supports save/continue flow
func _has_save_support() -> bool:
	return true


## Called after base _ready() completes. Wire game-specific UI here.
func _on_menu_ready() -> void:
	pass


## Called when starting a new game. Override to instantiate scene and start.
func _start_game() -> void:
	pass


## Called when resuming a saved game. Override to load scene and resume.
func _resume_game(data: Dictionary) -> void:
	pass  # @warning: unused parameter 'data'


## Called after abandon is confirmed, before save is cleared.
## Use to update stats (e.g. increment abandon counter, reset streak).
func _on_abandon_confirmed() -> void:
	pass


## Apply game-specific theme. Base provides a default panel background.
func _apply_game_theme() -> void:
	pass


# --- Base lifecycle ---

func _ready() -> void:
	# Wire standard buttons (null-safe)
	var continue_btn := _get_button("continue_button")
	var new_game_btn := _get_button("new_game_button")
	var stats_btn := _get_button("stats_button")
	var settings_btn := _get_button("settings_button")
	var back_btn := _get_button("back_button")

	if back_btn:
		back_btn.pressed.connect(func() -> void:
			SceneTransition.transition_to("res://scenes/game_picker.tscn")
		)

	if settings_btn:
		settings_btn.pressed.connect(func() -> void:
			var SettingsScreen := load("res://scripts/settings_screen.gd")
			SettingsScreen.return_scene = _get_menu_scene_path()
			SceneTransition.transition_to("res://scenes/settings.tscn")
		)

	if stats_btn and not _get_stats_scene_path().is_empty():
		stats_btn.pressed.connect(func() -> void:
			SceneTransition.transition_to(_get_stats_scene_path())
		)

	# Save/continue flow
	if _has_save_support():
		if continue_btn:
			continue_btn.visible = GameSaveManager.has_saved_game(_get_game_id())
			continue_btn.pressed.connect(_on_continue_pressed)
		if new_game_btn:
			new_game_btn.pressed.connect(_on_new_game_pressed)
	else:
		if continue_btn:
			continue_btn.visible = false

	# How to Play button injection
	if not _get_help_topic().is_empty() and settings_btn:
		var btn := Button.new()
		btn.text = "How to Play"
		btn.custom_minimum_size = Vector2(0, 50)
		var topic := _get_help_topic()
		btn.pressed.connect(func() -> void: HowToPlay.show_for(self, topic))
		settings_btn.get_parent().add_child(btn)
		settings_btn.get_parent().move_child(btn, settings_btn.get_index())

	# Theme
	_apply_theme_internal()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme_internal())

	# Safe area
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)

	_on_menu_ready()


# --- Continue/New-game/Abandon orchestration ---

func _on_continue_pressed() -> void:
	var data := GameSaveManager.load_game(_get_game_id())
	if data.is_empty():
		return
	_resume_game(data)


func _on_new_game_pressed() -> void:
	if GameSaveManager.has_saved_game(_get_game_id()):
		_show_abandon_dialog()
	else:
		_start_game()


func _show_abandon_dialog() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Abandon Game?"
	dialog.dialog_text = "Starting a new game will abandon\nyour current game."
	dialog.ok_button_text = "Start New"
	dialog.cancel_button_text = "Cancel"
	dialog.min_size = Vector2i(300, 0)
	dialog.size = Vector2i(300, 0)
	add_child(dialog)
	dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		_on_abandon_confirmed()
		GameSaveManager.clear_save(_get_game_id())
		dialog.queue_free()
		_start_game()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())


# --- Theme ---

func _apply_theme_internal() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)
	_apply_game_theme()


# --- Helpers ---

## Gets a button by property name from the subclass (convention-based).
func _get_button(property_name: String) -> Button:
	if property_name in self:
		var val = get(property_name)
		if val is Button:
			return val
	return null
