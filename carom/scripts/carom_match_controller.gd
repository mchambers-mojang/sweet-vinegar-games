class_name CaromMatchController
extends Node

## Match state machine — coordinates setup, scoring, round flow, and HUD.

enum MatchState {
	SETUP,
	PLAYING,
	GOAL_SCORED,
	GAME_OVER,
}

@export var score_limit: int = 5
@export var round_reset_delay: float = 1.2

var match_state: int = MatchState.SETUP
var player_score: int = 0
var ai_score: int = 0
var ai_difficulty_level: int = 1

@onready var arena: CaromArena = get_parent() as CaromArena
@onready var actors: Node3D = arena.get_node("Actors") as Node3D
@onready var setup: CaromMatchSetup = arena.get_node("MatchSetup") as CaromMatchSetup
@onready var hud: CaromHUD = arena.get_node("HUD/HUDController") as CaromHUD


func _ready() -> void:
	arena.goal_scored.connect(_on_goal_scored)
	hud.rematch_requested.connect(_on_rematch)
	hud.menu_requested.connect(_on_menu)
	hud.difficulty_changed.connect(_on_difficulty_changed)

	# Read difficulty from menu selection
	var CaromMenu := load("res://carom/scripts/carom_menu.gd")
	if CaromMenu:
		ai_difficulty_level = CaromMenu.selected_difficulty

	call_deferred("_init_match")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_F3:
			hud.toggle_debug_overlay()


func _process(_delta: float) -> void:
	if setup.ai_turret:
		hud.update_debug_overlay(setup.ai_turret)


func _init_match() -> void:
	setup.spawn_entities(arena, actors, ai_difficulty_level)
	_wire_hud_signals()
	_start_match()


func _start_match() -> void:
	player_score = 0
	ai_score = 0
	hud.update_scores(player_score, ai_score)
	_begin_round()


func _begin_round() -> void:
	match_state = MatchState.PLAYING
	arena.reset_goal_lock()

	var spawn_positions := arena.get_puck_spawn_positions()
	for i in setup.pucks.size():
		if is_instance_valid(setup.pucks[i]):
			var reset_pos := spawn_positions[i] if i < spawn_positions.size() else arena.get_puck_spawn_position()
			setup.pucks[i].reset_to_center(reset_pos)

	setup.player_turret.reset_for_round()
	setup.ai_turret.reset_for_round()
	setup.player_turret.set_active(true)
	setup.ai_turret.set_active(true)

	var diff_name := CaromAIDifficulty.get_preset(ai_difficulty_level).difficulty_name
	hud.update_status("First to %d • %s AI • Enter/click to fire • R to reload" % [score_limit, diff_name])
	_update_ammo_display()


func _on_goal_scored(scoring_side: StringName, _goal_puck: CaromPuck) -> void:
	if match_state != MatchState.PLAYING:
		return

	match_state = MatchState.GOAL_SCORED
	setup.player_turret.set_active(false)
	setup.ai_turret.set_active(false)

	# Reset all pucks
	var spawn_positions := arena.get_puck_spawn_positions()
	for i in setup.pucks.size():
		if is_instance_valid(setup.pucks[i]):
			var reset_pos := spawn_positions[i] if i < spawn_positions.size() else arena.get_puck_spawn_position()
			setup.pucks[i].reset_to_center(reset_pos)

	if scoring_side == &"north":
		player_score += 1
		hud.update_status("Player scores!")
	else:
		ai_score += 1
		hud.update_status("AI scores!")

	hud.update_scores(player_score, ai_score)
	_update_ammo_display()

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
	hud.update_status("")
	hud.show_game_over(winner, player_score, ai_score, ai_difficulty_level)


# --- HUD signal wiring ---

func _wire_hud_signals() -> void:
	setup.player_turret.ammo_changed.connect(_on_player_ammo_changed)
	setup.player_turret.reload_state_changed.connect(_on_player_reload_state_changed)
	setup.ai_turret.ammo_changed.connect(_on_ai_ammo_changed)
	setup.ai_turret.reload_state_changed.connect(_on_ai_reload_state_changed)


func _update_ammo_display() -> void:
	if setup.player_turret:
		hud.update_player_ammo(setup.player_turret.current_ammo, setup.player_turret.clip_size, setup.player_turret.is_reloading)
	if setup.ai_turret:
		hud.update_ai_ammo(setup.ai_turret.current_ammo, setup.ai_turret.clip_size, setup.ai_turret.is_reloading)


func _on_player_ammo_changed(current_ammo: int, max_ammo: int) -> void:
	hud.update_player_ammo(current_ammo, max_ammo, setup.player_turret.is_reloading if setup.player_turret else false)


func _on_ai_ammo_changed(current_ammo: int, max_ammo: int) -> void:
	hud.update_ai_ammo(current_ammo, max_ammo, setup.ai_turret.is_reloading if setup.ai_turret else false)


func _on_player_reload_state_changed(_is_reloading: bool) -> void:
	if setup.player_turret:
		hud.update_player_ammo(setup.player_turret.current_ammo, setup.player_turret.clip_size, setup.player_turret.is_reloading)


func _on_ai_reload_state_changed(_is_reloading: bool) -> void:
	if setup.ai_turret:
		hud.update_ai_ammo(setup.ai_turret.current_ammo, setup.ai_turret.clip_size, setup.ai_turret.is_reloading)


# --- Game-over panel callbacks ---

func _on_rematch() -> void:
	setup.spawn_entities(arena, actors, ai_difficulty_level)
	_wire_hud_signals()
	_start_match()


func _on_menu() -> void:
	SceneTransition.transition_to("res://scenes/carom_menu.tscn")


func _on_difficulty_changed(level: int) -> void:
	ai_difficulty_level = level
	var CaromMenu := load("res://carom/scripts/carom_menu.gd")
	if CaromMenu:
		CaromMenu.selected_difficulty = level
