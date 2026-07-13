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

# Cached save adapter — set in _ready() via _get_save_adapter().
# null for games that have not yet migrated to the adapter contract.
var _save_adapter: GameSaveAdapter = null

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


## Return a GameSaveAdapter for this game, or null to fall back to direct
## GameSaveManager calls.  Override in concrete menus.
func _get_save_adapter() -> GameSaveAdapter:
	return null


## Called after base _ready() completes.
## Config-driven menus: sets up the option button and registers game rules.
## Legacy subclasses: override to wire game-specific UI.
func _on_menu_ready() -> void:
	if not config:
		return
	# Register game rules defaults (no-op on subsequent calls)
	if not config.game_rules.is_empty():
		GameRulesRegistry.register_rules(config.game_id, config.game_rules)
	# Apply saved or default selection on the option dropdown (if present)
	if not config.option_button_unique_name.is_empty():
		var opt_btn := get_node_or_null("%" + config.option_button_unique_name) as OptionButton
		if opt_btn:
			var saved_idx := _load_last_option_index()
			var idx := saved_idx if saved_idx >= 0 and saved_idx < opt_btn.item_count else config.option_default_index
			if idx < opt_btn.item_count:
				opt_btn.selected = idx
			else:
				push_warning("MenuConfig: option_default_index %d is out of bounds (item_count=%d) for %s" % [
					config.option_default_index, opt_btn.item_count, config.game_id
				])
			opt_btn.item_selected.connect(_on_option_changed)
	# Leaderboard button is wired in _ready() via _setup_leaderboard_button()


## Adds a "Leaderboard" button below stats (if leaderboard modes are configured).
func _setup_leaderboard_button(stats_btn: Button) -> void:
	if not config or config.leaderboard_modes.is_empty():
		return
	# Collect only non-empty modes and their labels from the option dropdown
	var modes: PackedStringArray = PackedStringArray()
	var labels: PackedStringArray = PackedStringArray()
	var opt_btn: OptionButton = null
	if not config.option_button_unique_name.is_empty():
		opt_btn = get_node_or_null("%" + config.option_button_unique_name) as OptionButton
	for i in range(config.leaderboard_modes.size()):
		var m: String = config.leaderboard_modes[i]
		if m.is_empty():
			continue
		modes.append(m)
		if opt_btn and i < opt_btn.item_count:
			labels.append(opt_btn.get_item_text(i))
		else:
			labels.append(m.capitalize())
	if modes.is_empty():
		return
	# Create button
	var btn := Button.new()
	btn.text = "Leaderboard"
	btn.custom_minimum_size = Vector2(0, 50)
	btn.pressed.connect(func() -> void:
		# Determine which mode index to pre-select
		var current_opt_idx := _get_current_option_index()
		var selected_lb_idx := 0
		# Map the option dropdown index to our filtered modes list
		if current_opt_idx >= 0 and current_opt_idx < config.leaderboard_modes.size():
			var current_mode: String = config.leaderboard_modes[current_opt_idx]
			for j in range(modes.size()):
				if modes[j] == current_mode:
					selected_lb_idx = j
					break
		var return_path := _get_menu_scene_path()
		SceneTransition.navigate(Scenes.LEADERBOARD, func(screen: Node) -> void:
			screen.setup(config.game_id, modes, labels, config.leaderboard_is_time_based, selected_lb_idx, return_path)
		)
	)
	# Place below stats button
	if stats_btn:
		stats_btn.get_parent().add_child(btn)
		stats_btn.get_parent().move_child(btn, stats_btn.get_index() + 1)
	else:
		var vbox := find_child("VBoxContainer", true, false)
		if vbox:
			vbox.add_child(btn)


## Called when starting a new game.
## Builds a LaunchParams from the current option value and calls
## game_scene.launch(params).
func _start_game() -> void:
	if not config:
		return
	var params := config.build_launch_params(_get_current_option_value())
	SceneTransition.navigate(config.game_scene_path, func(game_scene: Node) -> void:
		game_scene.launch(params)
	)


## Called when resuming a saved game.
## Config-driven: loads game_scene_path and calls resume_game(data).
## Legacy: override to load scene and resume.
func _resume_game(data: Dictionary) -> void:
	if not config:
		return
	SceneTransition.navigate(config.game_scene_path, func(game_scene: Node) -> void:
		game_scene.resume_game(data)
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
	GameStatsManager.set_counter("general", "current_win_streak", 0)


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
	# Cache the save adapter (null for games not yet using the adapter contract)
	_save_adapter = _get_save_adapter()

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
	if start_btn and config and not config.start_button_text.is_empty():
		start_btn.text = config.start_button_text

	if back_btn:
		back_btn.pressed.connect(func() -> void:
			SceneTransition.navigate(Scenes.GAME_PICKER)
		)

	if settings_btn:
		settings_btn.pressed.connect(func() -> void:
			var SettingsScreen := load("res://scripts/settings_screen.gd")
			SettingsScreen.return_scene = _get_menu_scene_path()
			SceneTransition.push(Scenes.SETTINGS)
		)

	if stats_btn and not _get_stats_scene_path().is_empty():
		stats_btn.pressed.connect(func() -> void:
			SceneTransition.navigate(_get_stats_scene_path())
		)
	elif stats_btn:
		stats_btn.visible = false

	# Leaderboard button (shown only when config has leaderboard modes)
	_setup_leaderboard_button(stats_btn)

	# Save/continue flow
	if continue_btn:
		if _has_save_support():
			var resumable: bool = _save_adapter.can_resume() if _save_adapter else GameSaveManager.has_saved_game(_get_game_id())
			continue_btn.visible = resumable
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
	var data: Dictionary = _save_adapter.restore() if _save_adapter else GameSaveManager.load_game(_get_game_id())
	if data.is_empty():
		return
	_resume_game(data)


func _on_new_game_pressed() -> void:
	var has_game: bool = _save_adapter.has_save() if _save_adapter else GameSaveManager.has_saved_game(_get_game_id())
	if has_game:
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
		if _save_adapter:
			_save_adapter.clear()
		else:
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
		var btn := get_node_or_null("%" + config.start_button_unique_name) as Button
		if btn:
			return btn
		btn = find_child(config.start_button_unique_name, true, false) as Button
		if btn:
			return btn
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
		var btn := get_node_or_null("%" + unique_name) as Button
		if btn:
			return btn
		# Fall back to recursive find_child — handles instanced sub-scenes
		# where unique_name_in_owner is scoped to the sub-scene root.
		btn = find_child(unique_name, true, false) as Button
		if btn:
			return btn
	return null


## Gets a button by property name from the subclass (legacy convention).
## Kept for backward compatibility with existing subclasses.
func _get_button(property_name: String) -> Button:
	if property_name in self:
		var val = get(property_name)
		if val is Button:
			return val
	return null


# --- Last-used option persistence ---

const _PREFS_PATH := "user://settings.cfg"

func _on_option_changed(index: int) -> void:
	if not config:
		return
	var cfg := ConfigFile.new()
	cfg.load(_PREFS_PATH)
	cfg.set_value("last_mode", config.game_id, index)
	cfg.save(_PREFS_PATH)


func _load_last_option_index() -> int:
	if not config:
		return -1
	var cfg := ConfigFile.new()
	if cfg.load(_PREFS_PATH) != OK:
		return -1
	return cfg.get_value("last_mode", config.game_id, -1)
