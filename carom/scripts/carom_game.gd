class_name CaromGame
extends Node

## Match controller — spawns actors, tracks score, resets rounds, and runs a simple player-vs-AI flow.

enum MatchState {
	SETUP,
	PLAYING,
	GOAL_SCORED,
	GAME_OVER,
}

@export var score_limit: int = 5
@export var round_reset_delay: float = 1.2
@export var player_turret_scene: PackedScene = preload("res://carom/scenes/carom_turret.tscn")
@export var ai_turret_scene: PackedScene = preload("res://carom/scenes/carom_turret.tscn")
@export var puck_scene: PackedScene = preload("res://carom/scenes/carom_puck.tscn")

## AI difficulty level (0=Easy, 1=Medium, 2=Hard, 3=Brutal)
var ai_difficulty_level: int = 1

var match_state: int = MatchState.SETUP
var player_score: int = 0
var ai_score: int = 0
var player_turret: CaromTurret = null
var ai_turret: CaromTurret = null
var puck: CaromPuck = null

@onready var arena: CaromArena = get_parent() as CaromArena
@onready var actors: Node3D = arena.get_node("Actors") as Node3D
@onready var player_score_label: Label = arena.get_node("HUD/MarginContainer/VBoxContainer/TopBar/PlayerScoreLabel") as Label
@onready var ai_score_label: Label = arena.get_node("HUD/MarginContainer/VBoxContainer/TopBar/AIScoreLabel") as Label
@onready var status_label: Label = arena.get_node("HUD/MarginContainer/VBoxContainer/StatusLabel") as Label
@onready var player_ammo_label: Label = arena.get_node("HUD/MarginContainer/VBoxContainer/AmmoBar/PlayerAmmoLabel") as Label
@onready var ai_ammo_label: Label = arena.get_node("HUD/MarginContainer/VBoxContainer/AmmoBar/AIAmmoLabel") as Label


func _ready() -> void:
	arena.goal_scored.connect(_on_goal_scored)
	# Read difficulty from menu selection
	var CaromMenu := load("res://carom/scripts/carom_menu.gd")
	if CaromMenu:
		ai_difficulty_level = CaromMenu.selected_difficulty
	# Defer spawn until parent arena's @onready vars are resolved
	call_deferred("_spawn_entities")
	call_deferred("_start_match")


func _unhandled_input(event: InputEvent) -> void:
	# No more tap-to-restart; handled by game over panel buttons
	pass


func _spawn_entities() -> void:
	if player_turret:
		player_turret.queue_free()
	if ai_turret:
		ai_turret.queue_free()
	if puck:
		puck.queue_free()

	player_turret = player_turret_scene.instantiate() as CaromTurret
	ai_turret = ai_turret_scene.instantiate() as CaromTurret
	puck = puck_scene.instantiate() as CaromPuck

	actors.add_child(player_turret)
	actors.add_child(ai_turret)
	actors.add_child(puck)

	player_turret.name = "PlayerTurret"
	ai_turret.name = "AITurret"
	puck.name = "Puck"

	player_turret.global_position = arena.get_turret_spawn_position(&"north")
	ai_turret.global_position = arena.get_turret_spawn_position(&"south")
	puck.global_position = arena.get_puck_spawn_position()

	player_turret.configure(&"north", CaromTurret.ControlMode.HUMAN, 0.0, Color(0.2, 0.6, 1.0))
	ai_turret.configure(&"south", CaromTurret.ControlMode.AI, 180.0, Color(1.0, 0.25, 0.2))
	puck.configure(arena.get_goal_targets(), arena.get_puck_spawn_position())

	# Set up AI controller with difficulty, puck awareness, and arena geometry
	var midfield_z := arena.get_puck_spawn_position().z
	var ai_goal_z := arena.get_turret_spawn_position(&"south").z
	var ai_difficulty := CaromAIDifficulty.get_preset(ai_difficulty_level)
	ai_turret.setup_ai(ai_difficulty, puck, player_turret, midfield_z, ai_goal_z)

	player_turret.ammo_changed.connect(_on_player_ammo_changed)
	player_turret.reload_state_changed.connect(_on_player_reload_state_changed)
	ai_turret.ammo_changed.connect(_on_ai_ammo_changed)
	ai_turret.reload_state_changed.connect(_on_ai_reload_state_changed)


func _start_match() -> void:
	player_score = 0
	ai_score = 0
	_update_score_labels()
	_begin_round()


func _begin_round() -> void:
	match_state = MatchState.PLAYING
	arena.reset_goal_lock()
	puck.reset_to_center(arena.get_puck_spawn_position())
	player_turret.reset_for_round()
	ai_turret.reset_for_round()
	player_turret.set_active(true)
	ai_turret.set_active(true)
	var diff_name := CaromAIDifficulty.get_preset(ai_difficulty_level).difficulty_name
	status_label.text = "First to %d • %s AI • Enter/click to fire • R to reload" % [score_limit, diff_name]
	_update_ammo_labels()


func _on_goal_scored(scoring_side: StringName, goal_puck: CaromPuck) -> void:
	if match_state != MatchState.PLAYING:
		return

	match_state = MatchState.GOAL_SCORED
	player_turret.set_active(false)
	ai_turret.set_active(false)
	goal_puck.reset_to_center(arena.get_puck_spawn_position())

	if scoring_side == &"north":
		player_score += 1
		status_label.text = "Player scores!"
	else:
		ai_score += 1
		status_label.text = "AI scores!"

	_update_score_labels()
	_update_ammo_labels()

	if player_score >= score_limit or ai_score >= score_limit:
		_finish_match()
		return

	call_deferred("_queue_round_restart")


func _queue_round_restart() -> void:
	await get_tree().create_timer(round_reset_delay).timeout
	if match_state == MatchState.GOAL_SCORED:
		_begin_round()


func _finish_match() -> void:
	match_state = MatchState.GAME_OVER
	var winner := "Player" if player_score > ai_score else "AI"
	status_label.text = ""
	_show_game_over_panel(winner)


var _game_over_panel: Control = null

func _show_game_over_panel(winner: String) -> void:
	if _game_over_panel:
		_game_over_panel.queue_free()

	_game_over_panel = PanelContainer.new()
	_game_over_panel.set_anchors_preset(Control.PRESET_CENTER)
	_game_over_panel.custom_minimum_size = Vector2(320, 260)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_color = Color(0.2, 0.8, 1.0, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	_game_over_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	_game_over_panel.add_child(vbox)

	# Winner text
	var winner_label := Label.new()
	winner_label.text = "%s Wins!" % winner
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_label.add_theme_font_size_override("font_size", 28)
	winner_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
	vbox.add_child(winner_label)

	# Score
	var score_text := Label.new()
	score_text.text = "%d – %d" % [player_score, ai_score]
	score_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_text.add_theme_font_size_override("font_size", 22)
	vbox.add_child(score_text)

	# Difficulty selector
	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(diff_row)

	var diff_label := Label.new()
	diff_label.text = "Difficulty: "
	diff_row.add_child(diff_label)

	var diff_picker := OptionButton.new()
	diff_picker.add_item("Easy")
	diff_picker.add_item("Medium")
	diff_picker.add_item("Hard")
	diff_picker.add_item("Brutal")
	diff_picker.selected = ai_difficulty_level
	diff_picker.item_selected.connect(func(idx: int) -> void:
		ai_difficulty_level = idx
		var CaromMenu := load("res://carom/scripts/carom_menu.gd")
		if CaromMenu:
			CaromMenu.selected_difficulty = idx
	)
	diff_row.add_child(diff_picker)

	# Buttons
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)
	vbox.add_child(button_row)

	var rematch_button := Button.new()
	rematch_button.text = "Rematch"
	rematch_button.custom_minimum_size = Vector2(120, 44)
	rematch_button.pressed.connect(func() -> void:
		_game_over_panel.queue_free()
		_game_over_panel = null
		_spawn_entities()
		_start_match()
	)
	button_row.add_child(rematch_button)

	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.custom_minimum_size = Vector2(120, 44)
	menu_button.pressed.connect(func() -> void:
		SceneTransition.transition_to("res://scenes/carom_menu.tscn")
	)
	button_row.add_child(menu_button)

	# Add to HUD layer
	var hud := arena.get_node("HUD") as CanvasLayer
	hud.add_child(_game_over_panel)


func _update_score_labels() -> void:
	player_score_label.text = "PLAYER %d" % player_score
	ai_score_label.text = "AI %d" % ai_score


func _update_ammo_labels() -> void:
	if player_turret:
		_on_player_ammo_changed(player_turret.current_ammo, player_turret.clip_size)
	if ai_turret:
		_on_ai_ammo_changed(ai_turret.current_ammo, ai_turret.clip_size)


func _on_player_ammo_changed(current_ammo: int, max_ammo: int) -> void:
	player_ammo_label.text = "Ammo %d/%d%s" % [
		current_ammo,
		max_ammo,
		" • Reloading" if player_turret and player_turret.is_reloading else "",
	]


func _on_ai_ammo_changed(current_ammo: int, max_ammo: int) -> void:
	ai_ammo_label.text = "AI Ammo %d/%d%s" % [
		current_ammo,
		max_ammo,
		" • Reloading" if ai_turret and ai_turret.is_reloading else "",
	]


func _on_player_reload_state_changed(_is_reloading: bool) -> void:
	if player_turret:
		_on_player_ammo_changed(player_turret.current_ammo, player_turret.clip_size)


func _on_ai_reload_state_changed(_is_reloading: bool) -> void:
	if ai_turret:
		_on_ai_ammo_changed(ai_turret.current_ammo, ai_turret.clip_size)
