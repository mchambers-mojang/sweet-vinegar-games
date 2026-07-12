extends GameMenu

## Sudoku main menu — config-driven via assets/menu/sudoku_menu.tres
##
## Extends GameMenu with a Rule Set dropdown (Standard / Killer) that sits
## above the Difficulty dropdown.  The encoded option_value passed to the
## game screen is:
##   0-4  → Standard Sudoku at difficulty 0-4 (Easy … Evil)
##   5-8  → Killer Sudoku at difficulty 0-3 (Easy … Expert)
##
## When Killer is selected the DifficultyButton hides the "Evil" option
## (index 4) since there is no Killer–Evil leaderboard mode.

const KILLER_OFFSET := 5
const KILLER_MAX_DIFF := 3  # Expert

func _init() -> void:
	config = preload("res://assets/menu/sudoku_menu.tres")


func _get_save_adapter() -> GameSaveAdapter:
	return SudokuSaveAdapter.new()


## Called after base _ready().  Wire the RuleSetButton in addition to the
## standard DifficultyButton handling from GameMenu._on_menu_ready().
func _on_menu_ready() -> void:
	super._on_menu_ready()
	var rule_btn := get_node_or_null("%RuleSetButton") as OptionButton
	if rule_btn:
		rule_btn.item_selected.connect(_on_rule_set_changed)
		# Restore last-used rule set from prefs
		var cfg := ConfigFile.new()
		if cfg.load("user://settings.cfg") == OK:
			var saved_rule := int(cfg.get_value("last_rule_set", "sudoku", 0))
			rule_btn.selected = clampi(saved_rule, 0, rule_btn.item_count - 1)
		_update_difficulty_options(rule_btn.selected)


## Returns the combined option_value for the current rule set + difficulty.
func _get_current_option_value() -> int:
	var diff_idx := _get_current_option_index()
	var rule_idx := _get_current_rule_set_index()
	if rule_idx == 0:
		return diff_idx  # Standard
	# Killer: clamp to max killer difficulty
	return KILLER_OFFSET + mini(diff_idx, KILLER_MAX_DIFF)


# ---------------------------------------------------------------------------
# Leaderboard override
# ---------------------------------------------------------------------------

## Override to pass both Standard and Killer modes to the leaderboard screen.
func _setup_leaderboard_button(stats_btn: Button) -> void:
	if not config:
		return

	var modes: PackedStringArray = PackedStringArray(
		["easy", "medium", "hard", "expert",
		 "killer_easy", "killer_medium", "killer_hard", "killer_expert"])
	var labels: PackedStringArray = PackedStringArray(
		["Easy", "Medium", "Hard", "Expert",
		 "Killer Easy", "Killer Medium", "Killer Hard", "Killer Expert"])

	var btn := Button.new()
	btn.text = "Leaderboard"
	btn.custom_minimum_size = Vector2(0, 50)
	btn.pressed.connect(func() -> void:
		# Pre-select based on current rule set + difficulty
		var rule_idx := _get_current_rule_set_index()
		var diff_idx := _get_current_option_index()
		var lb_idx := 0
		if rule_idx == 0:
			lb_idx = clampi(diff_idx, 0, 3)
		else:
			lb_idx = 4 + clampi(diff_idx, 0, 3)
		var return_path := _get_menu_scene_path()
		SceneTransition.navigate(Scenes.LEADERBOARD, func(screen: Node) -> void:
			screen.setup(config.game_id, modes, labels,
					config.leaderboard_is_time_based, lb_idx, return_path)
		)
	)
	if stats_btn:
		stats_btn.get_parent().add_child(btn)
		stats_btn.get_parent().move_child(btn, stats_btn.get_index() + 1)
	else:
		var vbox := find_child("VBoxContainer", true, false)
		if vbox:
			vbox.add_child(btn)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _get_current_rule_set_index() -> int:
	var rule_btn := get_node_or_null("%RuleSetButton") as OptionButton
	if rule_btn:
		return rule_btn.selected
	return 0


func _on_rule_set_changed(index: int) -> void:
	_update_difficulty_options(index)
	# Persist rule set selection
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("last_rule_set", "sudoku", index)
	cfg.save("user://settings.cfg")


## Hide the "Evil" difficulty when Killer is selected (no Killer–Evil mode).
func _update_difficulty_options(rule_idx: int) -> void:
	var diff_btn := get_node_or_null("%DifficultyButton") as OptionButton
	if not diff_btn:
		return
	var is_killer := rule_idx == 1
	# Item 4 is "Evil" — disable/enable based on rule set
	diff_btn.set_item_disabled(4, is_killer)
	if is_killer and diff_btn.selected == 4:
		diff_btn.selected = 3  # Clamp to Expert
