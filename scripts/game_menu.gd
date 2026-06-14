extends Control
class_name GameMenu

## Base class for all game menus. Handles shared ceremony (theme, safe area,
## settings navigation, back navigation, How-to-Play injection) and the
## continue/new-game/abandon flow.
##
## Config-driven mode (preferred): assign a MenuConfig .tres to `config` in
## _init().  All virtual methods then read from the resource; per-game
## subclasses reduce to a single _init() that preloads the .tres.
##
## Legacy mode: leave config null and override the virtual methods below
## directly.  Existing subclasses work without changes.

# --- MenuConfig resource (config-driven mode) ---

## Assign a MenuConfig resource to enable config-driven behaviour.
## When set, all virtual methods below delegate to the resource.
@export var config: MenuConfig = null

# --- Virtual methods (config-driven defaults; override in legacy subclasses) ---

## Unique game identifier (e.g. "sudoku", "shikaku")
func _get_game_id() -> String:
	return config.game_id if config else ""


## Display name shown in the menu title
func _get_display_name() -> String:
	return config.display_name if config else ""


## Scene path for this menu (used as settings return target)
func _get_menu_scene_path() -> String:
	return config.menu_scene_path if config else ""


## Scene path for the game screen
func _get_game_scene_path() -> String:
	return config.game_scene_path if config else ""


## Scene path for the stats screen (empty = no stats button wiring)
func _get_stats_scene_path() -> String:
	return config.stats_scene_path if config else ""


## Help topic name (empty = no How-to-Play button)
func _get_help_topic() -> String:
	return config.help_topic if config else ""


## Whether this menu supports save/continue flow
func _has_save_support() -> bool:
	return config.has_save_support if config else true


## Called after base _ready() completes.
## Config-driven menus: sets up the option button and registers game rules.
## Legacy subclasses: override to wire game-specific UI.
func _on_menu_ready() -> void:
	if not config:
		return
	# Register game rules defaults (no-op on subsequent calls)
	if not config.game_rules.is_empty():
		GameRulesRegistry.register_rules(config.game_id, config.game_rules)
	# Apply default selection on the option dropdown (if present)
	if not config.option_button_unique_name.is_empty():
		var opt_btn := get_node_or_null("%" + config.option_button_unique_name) as OptionButton
		if opt_btn:
			if config.option_default_index < opt_btn.item_count:
				opt_btn.selected = config.option_default_index
			else:
				push_warning("MenuConfig: option_default_index %d is out of bounds (item_count=%d) for %s" % [
					config.option_default_index, opt_btn.item_count, config.game_id
				])


## Called when starting a new game.
## Config-driven: reads game_scene_path, start_game_method, and option value.
## Legacy: override to instantiate scene and start.
func _start_game() -> void:
	if not config:
		return
	var option_val := _get_current_option_value()
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load(config.game_scene_path).instantiate()
		if not config.start_game_meta_key.is_empty():
			game_scene.set_meta(config.start_game_meta_key, option_val)
		get_tree().root.add_child(game_scene)
		if not config.start_game_method.is_empty():
			if config.start_game_passes_option_twice:
				game_scene.call(config.start_game_method, option_val, option_val)
			elif config.start_game_passes_option:
				game_scene.call(config.start_game_method, option_val)
			else:
				game_scene.call(config.start_game_method)
		queue_free()
	)


## Called when resuming a saved game.
## Config-driven: loads game_scene_path and calls resume_game(data).
## Legacy: override to load scene and resume.
func _resume_game(data: Dictionary) -> void:
	if not config:
		return
	SceneTransition.transition_with_callback(func() -> void:
		var game_scene: Node = load(config.game_scene_path).instantiate()
		get_tree().root.add_child(game_scene)
		game_scene.resume_game(data)
		queue_free()
	)


## Called after abandon is confirmed, before save is cleared.
## Config-driven: updates abandon counter and resets current_streak.
## Legacy: override to update stats (e.g. increment counter, reset streak).
func _on_abandon_confirmed() -> void:
	if not config or config.abandon_stat_prefix.is_empty():
		return
	var save_data := GameSaveManager.load_game(config.game_id)
	var stat_val: int = save_data.get(config.abandon_stat_save_key, config.abandon_stat_default)
	GameStatsManager.increment_counter(config.game_id, config.abandon_stat_prefix + str(stat_val))
	GameStatsManager.set_counter(config.game_id, "current_streak", 0)


## Apply game-specific theme.
## Config-driven: applies title_color_key to the TitleLabel when set.
## Legacy: override to apply colours (base provides a default panel background).
func _apply_game_theme() -> void:
	if config and not config.title_color_key.is_empty():
		var title_lbl := get_node_or_null("%TitleLabel") as Label
		if title_lbl:
			title_lbl.add_theme_color_override("font_color", AppTheme.get_color(config.title_color_key))


# --- Base lifecycle ---

func _ready() -> void:
	# Set title
	var title_lbl := get_node_or_null("%TitleLabel") as Label
	if title_lbl and not _get_display_name().is_empty():
		title_lbl.text = _get_display_name()

	# Wire standard buttons.
	# _find_button tries the subclass @onready property first (legacy mode), then
	# falls back to the unique-name scene lookup (config-driven / simplified mode).
	var continue_btn := _find_button("continue_button", "ContinueButton")
	var stats_btn := _find_button("stats_button", "StatsButton")
	var settings_btn := _find_button("settings_button", "SettingsButton")
	var back_btn := _find_button("back_button", "BackButton")
	var start_btn := _find_start_button()

	if back_btn:
		back_btn.pressed.connect(func() -> void:
			SceneTransition.transition_to(Scenes.GAME_PICKER)
		)

	if settings_btn:
		settings_btn.pressed.connect(func() -> void:
			var SettingsScreen := load("res://scripts/settings_screen.gd")
			SettingsScreen.return_scene = _get_menu_scene_path()
			SceneTransition.transition_to(Scenes.SETTINGS)
		)

	if stats_btn and not _get_stats_scene_path().is_empty():
		stats_btn.pressed.connect(func() -> void:
			SceneTransition.transition_to(_get_stats_scene_path())
		)

	# Save/continue flow
	if continue_btn:
		if _has_save_support():
			continue_btn.visible = GameSaveManager.has_saved_game(_get_game_id())
			continue_btn.pressed.connect(_on_continue_pressed)
		else:
			continue_btn.visible = false

	# Wire start/play button (connected regardless of save support so that
	# games with no saves, e.g. Carom, still work via _on_new_game_pressed).
	if start_btn:
		start_btn.pressed.connect(_on_new_game_pressed)

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


# --- Option value helpers ---

## Returns the currently selected option value.
## If an OptionButton is named in config, reads its selected index and maps it
## through config.option_values (if set).  Returns 0 when no option is present.
func _get_current_option_value() -> int:
	return _resolve_option_value(_get_current_option_index())


## Returns the currently selected index of the option dropdown, or 0 if absent.
func _get_current_option_index() -> int:
	if not config or config.option_button_unique_name.is_empty():
		return 0
	var opt_btn := get_node_or_null("%" + config.option_button_unique_name) as OptionButton
	if not opt_btn:
		return 0
	return opt_btn.selected


## Maps a dropdown index to its configured integer value.
## When config.option_values is empty the index itself is returned.
func _resolve_option_value(idx: int) -> int:
	if not config:
		return idx
	if not config.option_values.is_empty() and idx >= 0 and idx < config.option_values.size():
		return config.option_values[idx]
	return idx


# --- Theme ---

func _apply_theme_internal() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)
	_apply_game_theme()


# --- Helpers ---

## Returns the start/play button.
## Config-driven: uses config.start_button_unique_name (e.g. "PlayButton").
## Legacy: falls back to the "new_game_button" subclass property.
func _find_start_button() -> Button:
	if config:
		return get_node_or_null("%" + config.start_button_unique_name) as Button
	return _get_button("new_game_button")


## Finds a button by subclass property name, falling back to unique-name lookup.
## property_name — @onready property declared on the subclass (legacy convention).
## unique_name   — scene unique name used when no subclass property exists.
func _find_button(property_name: String, unique_name: String = "") -> Button:
	if property_name in self:
		var val = get(property_name)
		if val is Button:
			return val
	if not unique_name.is_empty():
		return get_node_or_null("%" + unique_name) as Button
	return null


## Gets a button by property name from the subclass (legacy convention).
## Kept for backward compatibility with existing subclasses.
func _get_button(property_name: String) -> Button:
	if property_name in self:
		var val = get(property_name)
		if val is Button:
			return val
	return null
