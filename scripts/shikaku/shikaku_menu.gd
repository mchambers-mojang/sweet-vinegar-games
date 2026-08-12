extends GameMenu

## Shikaku main menu — config-driven via assets/menu/shikaku_menu.tres
##
## Extends GameMenu with a Mode dropdown (Standard / Shapes) injected dynamically
## below the existing SizeButton row, following the Sudoku rule-set-row pattern.
## The selected mode is forwarded to the game screen via LaunchParams.rule_set.

const MODE_STANDARD := ShikakuLogic.RULE_SET_STANDARD
const MODE_SHAPES := ShikakuLogic.RULE_SET_SHAPES

## Leaderboard mode strings for the Shapes variant (indexed to match size option order).
static var SHAPES_LEADERBOARD_MODES := PackedStringArray([
	"shapes_5", "shapes_7", "shapes_8", "shapes_10", "shapes_12", "shapes_15"
])
static var SHAPES_LEADERBOARD_LABELS := PackedStringArray([
	"Shapes 5×5", "Shapes 7×7", "Shapes 8×8", "Shapes 10×10", "Shapes 12×12", "Shapes 15×15"
])

var _mode_index: int = MODE_STANDARD
var _mode_button: OptionButton = null


func _init() -> void:
	config = preload("res://assets/menu/shikaku_menu.tres")


func _get_save_adapter() -> GameSaveAdapter:
	return ShikakuSaveAdapter.new()


func _get_help_topic() -> String:
	return "shikaku_shapes" if _mode_index == MODE_SHAPES else "shikaku"


func _on_menu_ready() -> void:
	super._on_menu_ready()
	_inject_mode_row()


## Injects an HBoxContainer with a "Mode:" label and OptionButton
## (Standard / Shapes) directly below the SizeButton row.
func _inject_mode_row() -> void:
	var size_btn := get_node_or_null("%SizeButton") as OptionButton
	if size_btn == null:
		return
	var size_row: Node = size_btn.get_parent()
	var vbox := size_row.get_parent() as VBoxContainer
	if vbox == null:
		return

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var lbl := Label.new()
	lbl.text = "Mode: "
	row.add_child(lbl)

	_mode_button = OptionButton.new()
	_mode_button.add_item("Standard")
	_mode_button.add_item("Shapes")
	_mode_button.selected = _mode_index
	_mode_button.item_selected.connect(_on_mode_changed)
	row.add_child(_mode_button)

	vbox.add_child(row)
	vbox.move_child(row, size_row.get_index() + 1)


## Override _start_game to include the mode in LaunchParams.
func _start_game() -> void:
	if not config:
		return
	var params := _build_launch_params(_get_current_option_value())
	SceneTransition.navigate(config.game_scene_path, func(game_scene: Node) -> void:
		game_scene.launch(params)
	)


func _build_launch_params(option_value: int) -> LaunchParams:
	var params := config.build_launch_params(option_value)
	params.rule_set = _mode_index
	return params


## Override _setup_leaderboard_button to add Shapes-mode leaderboard entries.
func _setup_leaderboard_button(stats_btn: Button) -> void:
	if not config or config.leaderboard_modes.is_empty():
		return

	# Standard modes from config
	var modes: PackedStringArray = PackedStringArray()
	var labels: PackedStringArray = PackedStringArray()
	var opt_btn := get_node_or_null("%SizeButton") as OptionButton
	for i in range(config.leaderboard_modes.size()):
		var m: String = config.leaderboard_modes[i]
		if m.is_empty():
			continue
		modes.append(m)
		if opt_btn and i < opt_btn.item_count:
			labels.append(opt_btn.get_item_text(i))
		else:
			labels.append(m)

	# Shapes modes
	for i in range(SHAPES_LEADERBOARD_MODES.size()):
		modes.append(SHAPES_LEADERBOARD_MODES[i])
		labels.append(SHAPES_LEADERBOARD_LABELS[i])

	if modes.is_empty():
		return

	var btn := Button.new()
	btn.text = "Leaderboard"
	btn.custom_minimum_size = Vector2(0, 50)
	btn.pressed.connect(func() -> void:
		var size_idx := _get_current_option_index()
		var std_count: int = 0
		for m in config.leaderboard_modes:
			if not m.is_empty():
				std_count += 1
		var selected_lb_idx := 0
		if _mode_index == MODE_SHAPES:
			selected_lb_idx = std_count + mini(size_idx, SHAPES_LEADERBOARD_MODES.size() - 1)
		else:
			selected_lb_idx = mini(size_idx, std_count - 1)
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


func _on_mode_changed(index: int) -> void:
	_mode_index = index


## Override to use mode-aware abandon counter key.
## Standard games use "abandoned_s{width}"; Shapes games use "abandoned_shapes_s{width}".
func _on_abandon_confirmed() -> void:
	if not config or config.abandon_stat_prefix.is_empty():
		super._on_abandon_confirmed()
		return
	var save_data := GameSaveManager.load_game(config.game_id)
	var stat_val: int = save_data.get(config.abandon_stat_save_key, config.abandon_stat_default)
	var saved_mode: int = save_data.get("mode", ShikakuLogic.RULE_SET_STANDARD)
	var prefix: String
	if saved_mode == ShikakuLogic.RULE_SET_SHAPES:
		prefix = "abandoned_shapes_s"
	else:
		prefix = config.abandon_stat_prefix
	GameStatsManager.increment_counter(config.game_id, prefix + str(stat_val))
	GameStatsManager.set_counter(config.game_id, "current_streak", 0)
	GameStatsManager.set_counter("general", "current_win_streak", 0)
