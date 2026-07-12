extends GameMenu

## Sudoku main menu — config-driven via assets/menu/sudoku_menu.tres
##
## Extends the base GameMenu to add:
##   • Rule-set dropdown (Standard / Anti-Knight / Anti-King)
##   • Rule-set–aware LaunchParams construction
##   • Leaderboard button that covers all rule-set + difficulty combinations

## Rule set ids indexed by RuleSetButton position.
const RULE_SET_IDS: Array[String] = ["", "anti_knight", "anti_king"]

## Labels shown in the leaderboard dropdown, grouped by rule set.
const LB_MODES: Array[String] = [
	"easy", "medium", "hard", "expert",
	"sudoku_antiknight_easy", "sudoku_antiknight_medium",
	"sudoku_antiknight_hard", "sudoku_antiknight_expert",
	"sudoku_antiking_easy",   "sudoku_antiking_medium",
	"sudoku_antiking_hard",   "sudoku_antiking_expert",
]
const LB_LABELS: Array[String] = [
	"Easy", "Medium", "Hard", "Expert",
	"Anti-Knight Easy", "Anti-Knight Medium",
	"Anti-Knight Hard", "Anti-Knight Expert",
	"Anti-King Easy",   "Anti-King Medium",
	"Anti-King Hard",   "Anti-King Expert",
]


func _init() -> void:
	config = preload("res://assets/menu/sudoku_menu.tres")


func _get_save_adapter() -> GameSaveAdapter:
	return SudokuSaveAdapter.new()


func _on_menu_ready() -> void:
	super._on_menu_ready()
	# Persist the last selected rule set across menu visits.
	var rule_btn := get_node_or_null("%RuleSetButton") as OptionButton
	if rule_btn:
		var saved_idx: int = int(GameRulesRegistry.get_rule("sudoku", "rule_set_index"))
		if saved_idx >= 0 and saved_idx < rule_btn.item_count:
			rule_btn.selected = saved_idx
		rule_btn.item_selected.connect(func(idx: int) -> void:
			GameRulesRegistry.set_rule("sudoku", "rule_set_index", idx)
		)


## Build LaunchParams that includes both the difficulty and the rule set.
func _start_game() -> void:
	var params := config.build_launch_params(_get_current_option_value())
	# Read the rule set from the %RuleSetButton (0 = Standard, 1 = Anti-Knight, 2 = Anti-King).
	var rule_btn := get_node_or_null("%RuleSetButton") as OptionButton
	if rule_btn and rule_btn.selected >= 0 and rule_btn.selected < RULE_SET_IDS.size():
		params.rule_set = RULE_SET_IDS[rule_btn.selected]
	SceneTransition.navigate(config.game_scene_path, func(game_scene: Node) -> void:
		game_scene.launch(params)
	)


## Override the leaderboard button to show all rule-set + difficulty combos.
func _setup_leaderboard_button(stats_btn: Button) -> void:
	if not config:
		return
	var btn := Button.new()
	btn.text = "Leaderboard"
	btn.custom_minimum_size = Vector2(0, 50)
	btn.pressed.connect(func() -> void:
		# Default selection: match current rule-set + difficulty dropdowns.
		var selected_lb_idx := 0
		var rule_btn := get_node_or_null("%RuleSetButton") as OptionButton
		var diff_btn := get_node_or_null("%DifficultyButton") as OptionButton
		var rule_idx := rule_btn.selected if rule_btn else 0
		var diff_idx := diff_btn.selected if diff_btn else 0
		# Easy/Medium/Hard/Expert are at positions 0-3; Evil (4) has no leaderboard.
		if diff_idx < 4:
			selected_lb_idx = rule_idx * 4 + diff_idx
		var return_path := _get_menu_scene_path()
		SceneTransition.navigate(Scenes.LEADERBOARD, func(screen: Node) -> void:
			screen.setup("sudoku", LB_MODES, LB_LABELS, true, selected_lb_idx, return_path)
		)
	)
	if stats_btn:
		var parent := stats_btn.get_parent()
		parent.add_child(btn)
		parent.move_child(btn, stats_btn.get_index() + 1)
	else:
		add_child(btn)
