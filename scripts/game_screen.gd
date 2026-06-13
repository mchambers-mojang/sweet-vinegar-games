extends Control
class_name GameScreen

## Base class for all Game Screens in the Collection.
## Handles the shared lifecycle ceremony: crash reporting, settings navigation,
## theme, safe area, help button, session persistence, replay, and analytics.
## Subclasses override virtual methods to provide game-specific behavior.


# --- Virtual methods (override in subclasses) ---

## Return the game_id used for saves, stats, analytics, replay.
func _get_game_id() -> String:
	return ""


## Return the scene path for this game screen (used for settings return).
func _get_scene_path() -> String:
	return ""


## Serialize the current game state for saving.
func _serialize_state() -> Dictionary:
	return {}


## Restore game state from a saved Dictionary.
func _deserialize_state(_data: Dictionary) -> void:
	pass


## Return true if the game has been explicitly initialized (from menu).
## Used to decide whether auto-resume should fire.
func _is_initialized() -> bool:
	return false


## Return true if the game is completed (don't save completed games).
func _is_completed() -> bool:
	return false


## Return crash state dictionary for CrashReporter.
func _get_crash_state() -> Dictionary:
	return {"game": _get_game_id()}


## Return the help topic string for HowToPlay.
func _get_help_topic() -> String:
	return _get_game_id()


## Called after the base lifecycle setup is complete.
## Subclass should wire its own buttons and signals here.
func _on_game_screen_ready() -> void:
	pass


## Apply visual theme. Called on ready and on theme changes.
func _apply_game_theme() -> void:
	pass


# --- Lifecycle ---

func _ready() -> void:
	# Crash reporting
	CrashReporter.register_state_provider(_get_crash_state)
	CrashReporter.register_user_action("%s_screen_opened" % _get_game_id())

	# Settings button
	var settings_btn := _find_settings_button()
	if settings_btn:
		settings_btn.pressed.connect(_on_settings_pressed)

	# Help button
	_setup_help_button()

	# Theme
	_apply_game_theme()
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_game_theme())

	# Safe area
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)

	# Let subclass do its own setup
	_on_game_screen_ready()

	# Auto-resume (deferred so subclass _ready and explicit init can happen first)
	_try_auto_resume.call_deferred()


func _exit_tree() -> void:
	CrashReporter.unregister_state_provider(_get_crash_state)


# --- Save / Resume ---

func save_progress() -> void:
	if _is_completed():
		return
	GameSaveManager.save_game(_get_game_id(), _serialize_state())


func clear_save() -> void:
	GameSaveManager.clear_save(_get_game_id())


func _try_auto_resume() -> void:
	if _is_initialized():
		return
	if GameSaveManager.has_saved_game(_get_game_id()):
		var data := GameSaveManager.load_game(_get_game_id())
		if not data.is_empty():
			_deserialize_state(data)


# --- Navigation ---

func _on_settings_pressed() -> void:
	var SettingsScreen := load("res://scripts/settings_screen.gd")
	SettingsScreen.return_scene = _get_scene_path()
	SceneTransition.transition_to("res://scenes/settings.tscn")


func navigate_to_menu(menu_scene: String) -> void:
	SceneTransition.transition_to(menu_scene)


# --- Help Button ---

func _setup_help_button() -> void:
	var settings_btn := _find_settings_button()
	if not settings_btn:
		return
	var topic := _get_help_topic()
	if topic.is_empty():
		return
	var btn := Button.new()
	btn.text = "?"
	btn.custom_minimum_size = Vector2(36, 0)
	btn.pressed.connect(func() -> void: HowToPlay.show_for(self, topic))
	var parent := settings_btn.get_parent()
	if parent:
		parent.add_child(btn)
		parent.move_child(btn, settings_btn.get_index())


# --- Internals ---

func _find_settings_button() -> Button:
	return get_node_or_null("%SettingsButton") as Button
