class_name CaromMatchController
extends Node

## Match adapter — bridges CaromMatchState to the scene tree (turrets, pucks, HUD).

@export var score_limit: int = 5


var state: CaromMatchState = CaromMatchState.new()

@onready var arena: CaromArena = get_parent() as CaromArena
@onready var actors: Node3D = arena.get_node("Actors") as Node3D
@onready var setup: CaromMatchSetup = arena.get_node("MatchSetup") as CaromMatchSetup
@onready var hud: CaromHUD = arena.get_node("HUD/HUDController") as CaromHUD

var _effects: CaromEffectsController = null

const MATCH_WIN_SLOWMO_SCALE: float = 0.3
const MATCH_WIN_SLOWMO_REAL_SECONDS: float = 1.0
const MATCH_WIN_RECOVER_REAL_SECONDS: float = 0.3
const MATCH_WIN_TWEEN_SPEED_MULTIPLIER: float = 1.0 / MATCH_WIN_SLOWMO_SCALE


func _ready() -> void:
	arena.goal_scored.connect(_on_goal_scored)
	hud.rematch_requested.connect(_on_rematch)
	hud.menu_requested.connect(_on_menu)
	hud.difficulty_changed.connect(_on_difficulty_changed)
	hud.reload_requested.connect(_on_reload_requested)
	hud.pause_requested.connect(_on_pause)
	hud.resume_requested.connect(_on_resume)

	state.difficulty = arena.get_meta("carom_difficulty", 1) as int
	if arena.has_meta("carom_difficulty"):
		arena.remove_meta("carom_difficulty")

	call_deferred("_init_match")


var _is_paused: bool = false


func _exit_tree() -> void:
	_reset_time_scale()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if not _is_paused and state.phase == CaromMatchState.Phase.PLAYING:
			_on_pause()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_F3:
			hud.toggle_debug_overlay()
		elif key_event.keycode == KEY_ESCAPE:
			if _is_paused:
				_on_resume()
			elif state.phase == CaromMatchState.Phase.PLAYING:
				_on_pause()


func _process(_delta: float) -> void:
	if setup.ai_turret:
		hud.update_debug_overlay(setup.ai_turret)


func _init_match() -> void:
	setup.spawn_entities(arena, actors, state.difficulty)
	_wire_hud_signals()
	_setup_effects()
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
	hud.update_status("")
	_update_ammo_display()


func _on_goal_scored(scoring_side: StringName, goal_puck: CaromPuck) -> void:
	if state.phase != CaromMatchState.Phase.PLAYING:
		return

	var goal_position: Vector3 = goal_puck.global_position

	# Only respawn the puck that scored — gameplay continues uninterrupted
	var puck_index := setup.pucks.find(goal_puck)
	if puck_index >= 0:
		var spawn_positions := arena.get_puck_spawn_positions()
		var reset_pos := spawn_positions[puck_index] if puck_index < spawn_positions.size() else arena.get_puck_spawn_position()
		goal_puck.reset_to_center(reset_pos)

	var scorer := "player" if scoring_side == &"north" else "ai"
	var result := state.on_goal_scored(scorer)

	# Haptic feedback for goals
	if scorer == "player":
		HapticManager.vibrate_success()
	else:
		HapticManager.vibrate_error()

	hud.update_scores(state.player_score, state.ai_score)
	_update_ammo_display()

	if result.match_over:
		await _play_match_win_sequence(goal_position)
		_finish_match(result.winner)
		return

	# Unlock goals so the next puck entry can score
	arena.reset_goal_lock()



func _finish_match(winner: String) -> void:
	_reset_time_scale()
	setup.player_turret.set_active(false)
	setup.ai_turret.set_active(false)
	hud.update_status("")
	hud.show_game_over(winner, state.player_score, state.ai_score, state.difficulty)


func _play_match_win_sequence(goal_position: Vector3) -> void:
	Engine.time_scale = MATCH_WIN_SLOWMO_SCALE

	if _effects:
		_effects.play_match_win(goal_position)

	var hold_tween := create_tween()
	hold_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	hold_tween.set_speed_scale(MATCH_WIN_TWEEN_SPEED_MULTIPLIER)
	hold_tween.tween_interval(MATCH_WIN_SLOWMO_REAL_SECONDS)
	await hold_tween.finished

	var recover_tween := create_tween()
	recover_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	recover_tween.set_speed_scale(MATCH_WIN_TWEEN_SPEED_MULTIPLIER)
	recover_tween.tween_property(Engine, "time_scale", 1.0, MATCH_WIN_RECOVER_REAL_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await recover_tween.finished


func _reset_time_scale() -> void:
	if not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0


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
	_setup_effects()
	_start_match()


func _on_menu() -> void:
	get_tree().paused = false
	SceneTransition.transition_to(Scenes.CAROM_MENU)


func _setup_effects() -> void:
	if _effects == null:
		_effects = CaromEffectsController.new()
		_effects.name = "EffectsController"
		arena.add_child(_effects)
	_effects.register_turret(setup.player_turret)
	_effects.register_turret(setup.ai_turret)


func _on_difficulty_changed(level: int) -> void:
	state.difficulty = level


func _on_reload_requested() -> void:
	if setup.player_turret and setup.player_turret.is_active:
		setup.player_turret.start_reload()


func _on_pause() -> void:
	if _is_paused:
		return
	_is_paused = true
	get_tree().paused = true
	hud.show_pause_overlay()
	hud.set_pause_button_visible(false)


func _on_resume() -> void:
	if not _is_paused:
		return
	_is_paused = false
	hud.hide_pause_overlay()
	hud.set_pause_button_visible(true)
	get_tree().paused = false
