extends GameMenu

## Sudoku main menu — config-driven via assets/menu/sudoku_menu.tres
##
## Extends GameMenu with a "Rule Set" dropdown (Standard / Anti-Knight / Anti-King / Killer)
## injected dynamically below the existing DifficultyButton row.
## The selected rule set is forwarded to the game screen via LaunchParams.rule_set.

const RULE_SET_STANDARD := 0
const RULE_SET_ANTI_KNIGHT := 1
const RULE_SET_ANTI_KING := 2
const RULE_SET_KILLER := 3

const ANTI_KNIGHT_MODES := PackedStringArray(["antiknight_easy", "antiknight_medium", "antiknight_hard", "antiknight_expert"])
const ANTI_KNIGHT_LABELS := PackedStringArray(["Anti-Knight Easy", "Anti-Knight Medium", "Anti-Knight Hard", "Anti-Knight Expert"])
const ANTI_KING_MODES := PackedStringArray(["antiking_easy", "antiking_medium", "antiking_hard", "antiking_expert"])
const ANTI_KING_LABELS := PackedStringArray(["Anti-King Easy", "Anti-King Medium", "Anti-King Hard", "Anti-King Expert"])
const KILLER_MODES := PackedStringArray(["killer_easy", "killer_medium", "killer_hard", "killer_expert"])
const KILLER_LABELS := PackedStringArray(["Killer Easy", "Killer Medium", "Killer Hard", "Killer Expert"])

var _rule_set_index: int = RULE_SET_STANDARD
var _rule_set_button: OptionButton = null


func _init() -> void:
	config = preload("res://assets/menu/sudoku_menu.tres")


func _get_save_adapter() -> GameSaveAdapter:
	return SudokuSaveAdapter.new()


func _on_menu_ready() -> void:
	super._on_menu_ready()
	_inject_rule_set_row()


## Injects an HBoxContainer with "Rule Set:" label and OptionButton
## (Standard / Anti-Knight / Anti-King / Killer) directly below the DifficultyRow.
func _inject_rule_set_row() -> void:
	var diff_btn := get_node_or_null("%DifficultyButton") as OptionButton
	if diff_btn == null:
		return
	var diff_row: Node = diff_btn.get_parent()
	var vbox := diff_row.get_parent() as VBoxContainer
	if vbox == null:
		return

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var lbl := Label.new()
	lbl.text = "Rule Set: "
	row.add_child(lbl)

	_rule_set_button = OptionButton.new()
	_rule_set_button.add_item("Standard")
	_rule_set_button.add_item("Anti-Knight")
	_rule_set_button.add_item("Anti-King")
	_rule_set_button.add_item("Killer")
	_rule_set_button.selected = _rule_set_index
	_rule_set_button.item_selected.connect(_on_rule_set_changed)
	row.add_child(_rule_set_button)

	vbox.add_child(row)
	vbox.move_child(row, diff_row.get_index() + 1)


## Override _start_game to include the rule_set in LaunchParams.
func _start_game() -> void:
	if not config:
		return
	var params := config.build_launch_params(_get_current_option_value())
	params.rule_set = _rule_set_index
	SceneTransition.navigate(config.game_scene_path, func(game_scene: Node) -> void:
		game_scene.launch(params)
	)


## Override _setup_leaderboard_button to add Anti-Knight, Anti-King and Killer modes.
func _setup_leaderboard_button(stats_btn: Button) -> void:
	if not config or config.leaderboard_modes.is_empty():
		return

	# Build combined mode + label lists: standard first, then variants.
	var modes: PackedStringArray = PackedStringArray()
	var labels: PackedStringArray = PackedStringArray()
	var opt_btn := get_node_or_null("%DifficultyButton") as OptionButton

	# Standard modes (from config, skip empty Evil slot — Evil difficulty has no leaderboard support)
	for i in range(config.leaderboard_modes.size()):
		var m: String = config.leaderboard_modes[i]
		if m.is_empty():
			continue
		modes.append(m)
		if opt_btn and i < opt_btn.item_count:
			labels.append(opt_btn.get_item_text(i))
		else:
			labels.append(m.capitalize())

	# Anti-Knight modes
	for i in range(ANTI_KNIGHT_MODES.size()):
		modes.append(ANTI_KNIGHT_MODES[i])
		labels.append(ANTI_KNIGHT_LABELS[i])

	# Anti-King modes
	for i in range(ANTI_KING_MODES.size()):
		modes.append(ANTI_KING_MODES[i])
		labels.append(ANTI_KING_LABELS[i])

	# Killer modes
	for i in range(KILLER_MODES.size()):
		modes.append(KILLER_MODES[i])
		labels.append(KILLER_LABELS[i])

	if modes.is_empty():
		return

	var btn := Button.new()
	btn.text = "Leaderboard"
	btn.custom_minimum_size = Vector2(0, 50)
	btn.pressed.connect(func() -> void:
		# Pre-select: map current (rule_set, difficulty) to the combined modes list.
		var diff_idx := _get_current_option_index()
		var standard_modes_count := 0
		for m in config.leaderboard_modes:
			if not m.is_empty():
				standard_modes_count += 1
		var selected_lb_idx := 0
		if _rule_set_index == RULE_SET_ANTI_KNIGHT:
			selected_lb_idx = standard_modes_count + mini(diff_idx, ANTI_KNIGHT_MODES.size() - 1)
		elif _rule_set_index == RULE_SET_ANTI_KING:
			selected_lb_idx = standard_modes_count + ANTI_KNIGHT_MODES.size() + mini(diff_idx, ANTI_KING_MODES.size() - 1)
		elif _rule_set_index == RULE_SET_KILLER:
			selected_lb_idx = standard_modes_count + ANTI_KNIGHT_MODES.size() + ANTI_KING_MODES.size() + mini(diff_idx, KILLER_MODES.size() - 1)
		else:
			# Map diff_idx to the non-empty standard modes index
			var count := 0
			for i in range(config.leaderboard_modes.size()):
				if config.leaderboard_modes[i].is_empty():
					continue
				if i == diff_idx:
					selected_lb_idx = count
					break
				count += 1
		var return_path := _get_menu_scene_path()
		SceneTransition.navigate(Scenes.LEADERBOARD, func(screen: Node) -> void:
			screen.setup(config.game_id, modes, labels, config.leaderboard_is_time_based, selected_lb_idx, return_path)
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

func _on_rule_set_changed(index: int) -> void:
	_rule_set_index = index
	_update_difficulty_options(index)


## Hide the "Evil" difficulty when Killer is selected (no Killer–Evil mode).
func _update_difficulty_options(rule_idx: int) -> void:
	var diff_btn := get_node_or_null("%DifficultyButton") as OptionButton
	if not diff_btn:
		return
	var is_killer := rule_idx == RULE_SET_KILLER
	# Item 4 is "Evil" — disable/enable based on rule set
	diff_btn.set_item_disabled(4, is_killer)
	if is_killer and diff_btn.selected == 4:
		diff_btn.selected = 3  # Clamp to Expert
