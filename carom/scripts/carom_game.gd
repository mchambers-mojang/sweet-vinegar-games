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
	_spawn_entities()
	_start_match()


func _unhandled_input(event: InputEvent) -> void:
	if match_state != MatchState.GAME_OVER:
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			_start_match()
	elif event is InputEventScreenTouch:
		var screen_touch := event as InputEventScreenTouch
		if screen_touch.pressed:
			_start_match()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_SPACE:
			_start_match()


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

	player_turret.global_position = arena.get_turret_spawn_position(&"south")
	ai_turret.global_position = arena.get_turret_spawn_position(&"north")
	puck.global_position = arena.get_puck_spawn_position()

	player_turret.configure(&"south", CaromTurret.ControlMode.HUMAN, 180.0)
	ai_turret.configure(&"north", CaromTurret.ControlMode.AI, 0.0)
	puck.configure(arena.get_goal_targets(), arena.get_puck_spawn_position())

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
	status_label.text = "First to %d • Enter/click to fire • R to reload" % score_limit
	_update_ammo_labels()


func _on_goal_scored(scoring_side: StringName, goal_puck: CaromPuck) -> void:
	if match_state != MatchState.PLAYING:
		return

	match_state = MatchState.GOAL_SCORED
	player_turret.set_active(false)
	ai_turret.set_active(false)
	goal_puck.reset_to_center(arena.get_puck_spawn_position())

	if scoring_side == &"south":
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

	_call_deferred("_queue_round_restart")


func _queue_round_restart() -> void:
	await get_tree().create_timer(round_reset_delay).timeout
	if match_state == MatchState.GOAL_SCORED:
		_begin_round()


func _finish_match() -> void:
	match_state = MatchState.GAME_OVER
	var winner := "Player" if player_score > ai_score else "AI"
	status_label.text = "%s wins! Click or press Enter to restart." % winner


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
