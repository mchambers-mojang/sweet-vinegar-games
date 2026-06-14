class_name CaromMatchController
extends Node

## Match adapter — bridges CaromMatchState to the scene tree (turrets, pucks, HUD).

@export var score_limit: int = 5


var state: CaromMatchState = CaromMatchState.new()

@onready var arena: CaromArena = get_parent() as CaromArena
@onready var actors: Node3D = arena.get_node("Actors") as Node3D
@onready var setup: CaromMatchSetup = arena.get_node("MatchSetup") as CaromMatchSetup
@onready var hud: CaromHUD = arena.get_node("HUD/HUDController") as CaromHUD


func _ready() -> void:
	arena.goal_scored.connect(_on_goal_scored)
	hud.rematch_requested.connect(_on_rematch)
	hud.menu_requested.connect(_on_menu)
	hud.difficulty_changed.connect(_on_difficulty_changed)
	hud.reload_requested.connect(_on_reload_requested)

	state.difficulty = arena.get_meta("carom_difficulty", 1) as int
	if arena.has_meta("carom_difficulty"):
		arena.remove_meta("carom_difficulty")

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
	setup.spawn_entities(arena, actors, state.difficulty)
	_wire_hud_signals()
	_start_match()


func _start_match() -> void:
	state.init_match(state.difficulty, score_limit)
	hud.update_scores(state.player_score, state.ai_score)
	_begin_round()


func _begin_round() -> void:
	state.on_round_ready()
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

	var diff_name := CaromAIDifficulty.get_preset(state.difficulty).difficulty_name
	hud.update_status("First to %d • %s AI" % [score_limit, diff_name])
	_update_ammo_display()


func _on_goal_scored(scoring_side: StringName, goal_puck: CaromPuck) -> void:
	if state.phase != CaromMatchState.Phase.PLAYING:
		return

	# Only respawn the puck that scored — gameplay continues uninterrupted
	var puck_index := setup.pucks.find(goal_puck)
	if puck_index >= 0:
		var spawn_positions := arena.get_puck_spawn_positions()
		var reset_pos := spawn_positions[puck_index] if puck_index < spawn_positions.size() else arena.get_puck_spawn_position()
		goal_puck.reset_to_center(reset_pos)

	var scorer := "player" if scoring_side == &"north" else "ai"
	var result := state.on_goal_scored(scorer)

	if result.scorer == "player":
		hud.update_status("Player scores!")
	else:
		hud.update_status("AI scores!")
	hud.update_scores(state.player_score, state.ai_score)
	_update_ammo_display()

	if result.match_over:
		_finish_match(result.winner)
		return

	# Unlock goals so the next puck entry can score
	arena.reset_goal_lock()



func _finish_match(winner: String) -> void:
	hud.update_status("")
	hud.show_game_over(winner, state.player_score, state.ai_score, state.difficulty)


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
	setup.spawn_entities(arena, actors, state.difficulty)
	_wire_hud_signals()
	_start_match()


func _on_menu() -> void:
	SceneTransition.transition_to(Scenes.CAROM_MENU)


func _on_difficulty_changed(level: int) -> void:
	state.difficulty = level


func _on_reload_requested() -> void:
	if setup.player_turret and setup.player_turret.is_active:
		setup.player_turret.start_reload()
