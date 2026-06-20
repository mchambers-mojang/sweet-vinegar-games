class_name CaromOnlineMatchController
extends Node

## Match controller for online 1v1 Carom matches.
##
## Differences from CaromMatchController (single-player):
## - Both turrets are human-controlled (remote uses CaromNetworkInput)
## - Sim ticking driven by CaromMultiplayerController (not autonomous)
## - No AI, no difficulty settings
## - Match flow: connect → sync → countdown → play → results

@export var score_limit: int = 5

signal connection_status_changed(status: String, message: String)
signal match_ended(won: bool, your_score: int, their_score: int, forfeit: bool)

enum Phase { IDLE, CONNECTING, SYNCING, COUNTDOWN, PLAYING, DISCONNECTED, GAME_OVER }

var phase: Phase = Phase.IDLE
var _is_host: bool = false

@onready var arena: CaromArena = get_parent() as CaromArena
@onready var actors: Node3D = arena.get_node("Actors") as Node3D
@onready var setup: CaromMatchSetup = arena.get_node("MatchSetup") as CaromMatchSetup
@onready var hud: CaromHUD = arena.get_node("HUD/HUDController") as CaromHUD

var _bridge: CaromSimBridge = null
var _multiplayer_ctrl: CaromMultiplayerController = null
var _match_round: CaromMatchRound = CaromMatchRound.new()
var _effects: CaromEffectsController = null
var _use_local_network: bool = false

var _local_turret: CaromTurret = null
var _remote_turret: CaromTurret = null

var _player_score: int = 0
var _opponent_score: int = 0

## Tick accumulator for driving multiplayer at fixed rate.
var _tick_accum: float = 0.0
const TICK_RATE: float = 1.0 / 30.0

## Match timer (driven by sim ticks).
var _timer_sim: SimWorld = SimWorld.new()
var _timer_accum: float = 0.0

## Disconnect handling.
const DISCONNECT_TIMEOUT: float = 10.0
const SOFT_DISCONNECT_TIMEOUT: float = 3.0
var _disconnect_timer: float = 0.0
var _no_input_timer: float = 0.0
var _last_remote_frame: int = -1


func _ready() -> void:
	set_process(false)
	arena.goal_scored.connect(_on_goal_scored)
	hud.pause_requested.connect(_on_pause)
	hud.resume_requested.connect(_on_resume)
	hud.menu_requested.connect(_on_menu)
	hud.camera_mode_changed.connect(_on_camera_mode_changed)


## Start hosting an online match.
func host(signaling_url: String) -> void:
	_is_host = true
	phase = Phase.CONNECTING
	connection_status_changed.emit("connecting", "Connecting to server...")
	_setup_match()
	_multiplayer_ctrl.host_match(signaling_url)


## Join an existing online match.
func join(code: String, signaling_url: String) -> void:
	_is_host = false
	phase = Phase.CONNECTING
	connection_status_changed.emit("connecting", "Connecting to server...")
	_setup_match()
	_multiplayer_ctrl.join_match(code, signaling_url)


## Enter matchmaking queue — server pairs us with another player.
func matchmake(signaling_url: String) -> void:
	_is_host = false  # Will be assigned by server after matching
	phase = Phase.CONNECTING
	connection_status_changed.emit("connecting", "Finding opponent...")
	# Don't call _setup_match() yet — we don't know our role.
	# Setup happens in _on_match_connected after the server assigns us.
	_setup_match_deferred(signaling_url)


## Host a local match (direct TCP, no WebRTC).
func host_local() -> void:
	_is_host = true
	_use_local_network = true
	phase = Phase.CONNECTING
	connection_status_changed.emit("connecting", "Waiting for player...")
	_setup_match()
	_multiplayer_ctrl.host_match("")


## Join a local match (direct TCP, no WebRTC).
func join_local() -> void:
	_is_host = false
	_use_local_network = true
	phase = Phase.CONNECTING
	connection_status_changed.emit("connecting", "Connecting...")
	_setup_match()
	_multiplayer_ctrl.join_match(CaromLocalNetwork.ROOM_CODE, "")


func get_room_code() -> String:
	if _multiplayer_ctrl:
		return _multiplayer_ctrl.get_room_code()
	return ""


var _is_matchmaking: bool = false

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Deferred setup for matchmaking — only creates network layer, spawns later.
func _setup_match_deferred(signaling_url: String) -> void:
	_is_matchmaking = true
	if is_instance_valid(_multiplayer_ctrl):
		_multiplayer_ctrl.shutdown()
		_multiplayer_ctrl.queue_free()
	_multiplayer_ctrl = CaromMultiplayerController.new()
	_multiplayer_ctrl.name = "MultiplayerController"
	arena.add_child(_multiplayer_ctrl)
	# Setup with no bridge/turrets yet — just the network
	_multiplayer_ctrl.setup(null, null, null, null)
	_multiplayer_ctrl.match_connected.connect(_on_match_connected)
	_multiplayer_ctrl.match_started.connect(_on_match_started)
	_multiplayer_ctrl.match_disconnected.connect(_on_match_disconnected)
	_multiplayer_ctrl.room_created.connect(_on_room_created)
	_multiplayer_ctrl.connection_failed.connect(_on_connection_failed)
	_multiplayer_ctrl.matchmake_queued.connect(_on_matchmake_queued)
	_multiplayer_ctrl.matchmake(signaling_url)

func _setup_match() -> void:
	_player_score = 0
	_opponent_score = 0

	# Create the sim bridge in multiplayer mode
	if is_instance_valid(_bridge):
		_bridge.cleanup_all_projectiles()
		_bridge.queue_free()
	_bridge = CaromSimBridge.new()
	_bridge.name = "SimBridge"
	_bridge.multiplayer_mode = true
	arena.add_child(_bridge)
	_bridge.setup_arena(arena)
	_bridge.puck_zone_entered.connect(_on_bridge_puck_zone_entered)
	_bridge.projectile_zone_entered.connect(_on_bridge_projectile_zone_entered)

	# Spawn entities — both turrets configured as HUMAN
	_spawn_multiplayer_entities()

	# Apply perspective normalization: isometric for online, top-down for local
	var camera_mode := "isometric" if not _use_local_network else "top_down"
	arena.set_camera_mode(camera_mode, false)
	arena.set_perspective_flipped(not _is_host, false)

	# Register with sim bridge
	for puck: CaromPuck in setup.pucks:
		_bridge.register_puck(puck, puck.global_position)
	_bridge.register_turret(_local_turret)
	_bridge.register_turret(_remote_turret)

	# Create multiplayer controller
	if is_instance_valid(_multiplayer_ctrl):
		_multiplayer_ctrl.shutdown()
		_multiplayer_ctrl.queue_free()
	_multiplayer_ctrl = CaromMultiplayerController.new()
	_multiplayer_ctrl.name = "MultiplayerController"
	arena.add_child(_multiplayer_ctrl)
	var net_override: Node = CaromLocalNetwork.new() if _use_local_network else null
	_multiplayer_ctrl.setup(_bridge, _local_turret, _remote_turret, net_override)
	_multiplayer_ctrl.is_host_side = _is_host
	_multiplayer_ctrl.lockstep = true

	# Connect multiplayer signals
	_multiplayer_ctrl.match_connected.connect(_on_match_connected)
	_multiplayer_ctrl.match_started.connect(_on_match_started)
	_multiplayer_ctrl.match_disconnected.connect(_on_match_disconnected)
	_multiplayer_ctrl.room_created.connect(_on_room_created)
	_multiplayer_ctrl.connection_failed.connect(_on_connection_failed)

	# Set up effects
	_setup_effects()

	# Wire HUD
	_local_turret.ammo_changed.connect(func(ammo: int, max_a: int) -> void:
		hud.update_player_ammo(ammo, max_a, _local_turret.is_reloading))
	_local_turret.reload_state_changed.connect(func(_r: bool) -> void:
		hud.update_player_ammo(_local_turret.current_ammo, _local_turret.clip_size, _local_turret.is_reloading))
	hud.reload_requested.connect(func() -> void:
		if _local_turret and _local_turret.is_active:
			_local_turret.start_reload())


func _spawn_multiplayer_entities() -> void:
	# Clean up existing entities
	if setup.player_turret:
		setup.player_turret.queue_free()
		setup.player_turret = null
	if setup.ai_turret:
		setup.ai_turret.queue_free()
		setup.ai_turret = null
	for p in setup.pucks:
		if is_instance_valid(p):
			p.queue_free()
	setup.pucks.clear()

	# Spawn turrets — both as HUMAN mode (remote gets network input later)
	var turret_scene: PackedScene = preload("res://carom/scenes/carom_turret.tscn")
	_local_turret = turret_scene.instantiate() as CaromTurret
	_remote_turret = turret_scene.instantiate() as CaromTurret
	actors.add_child(_local_turret)
	actors.add_child(_remote_turret)

	# Host is south, joiner is north
	var local_side: StringName = &"south" if _is_host else &"north"
	var remote_side: StringName = &"north" if _is_host else &"south"

	_local_turret.name = "LocalTurret"
	_remote_turret.name = "RemoteTurret"
	_local_turret.global_position = arena.get_turret_spawn_position(local_side)
	_remote_turret.global_position = arena.get_turret_spawn_position(remote_side)

	var local_yaw: float = 0.0 if local_side == &"south" else 180.0
	var remote_yaw: float = 0.0 if remote_side == &"south" else 180.0

	_local_turret.configure(local_side, CaromTurret.ControlMode.HUMAN, local_yaw, Color(0.2, 0.6, 1.0))
	_remote_turret.configure(remote_side, CaromTurret.ControlMode.HUMAN, remote_yaw, Color(1.0, 0.25, 0.2))

	# In multiplayer, turret logic is driven by tick (not _process)
	_local_turret.multiplayer_driven = true
	_remote_turret.multiplayer_driven = true
	# Remote turret has no local input — entirely driven by apply_tick
	_remote_turret.input = null

	# Store in setup for CaromMatchRound compatibility
	setup.player_turret = _local_turret
	setup.ai_turret = _remote_turret

	# Spawn pucks
	var puck_scene: PackedScene = preload("res://carom/scenes/carom_puck.tscn")
	var spawn_positions := arena.get_puck_spawn_positions()
	var goal_targets: Array[Vector3] = arena.get_goal_targets()
	# Reverse goal targets for joiner so goal_targets[0] is always the local player's danger zone
	if not _is_host:
		goal_targets.reverse()
	for i in spawn_positions.size():
		var p := puck_scene.instantiate() as CaromPuck
		actors.add_child(p)
		p.name = "Puck%d" % (i + 1)
		p.global_position = spawn_positions[i]
		p.configure(goal_targets, spawn_positions[i])
		setup.pucks.append(p)

	# Set aim projection distance for local player
	var arena_length := absf(arena.north_goal.global_position.z - arena.south_goal.global_position.z)
	_local_turret.set_aim_projection_distance(arena_length * 0.85)
	_remote_turret.set_aim_projection_distance(0.0)


# ---------------------------------------------------------------------------
# Match flow callbacks
# ---------------------------------------------------------------------------

func _on_room_created(code: String) -> void:
	connection_status_changed.emit("waiting", "Room: %s\nWaiting for opponent..." % code)


func _on_matchmake_queued() -> void:
	connection_status_changed.emit("connecting", "Searching for opponent...")


func _on_match_connected() -> void:
	if _is_matchmaking:
		# Now we know our role — finish setting up the match
		_is_host = _multiplayer_ctrl.is_host()
		_is_matchmaking = false
		_finish_matchmake_setup()
	phase = Phase.SYNCING
	connection_status_changed.emit("connected", "Opponent found!")


## Complete match setup after matchmaking assigns our role.
func _finish_matchmake_setup() -> void:
	_player_score = 0
	_opponent_score = 0

	# Create sim bridge
	if is_instance_valid(_bridge):
		_bridge.cleanup_all_projectiles()
		_bridge.queue_free()
	_bridge = CaromSimBridge.new()
	_bridge.name = "SimBridge"
	_bridge.multiplayer_mode = true
	arena.add_child(_bridge)
	_bridge.setup_arena(arena)
	_bridge.puck_zone_entered.connect(_on_bridge_puck_zone_entered)
	_bridge.projectile_zone_entered.connect(_on_bridge_projectile_zone_entered)

	# Spawn entities
	_spawn_multiplayer_entities()

	# Camera — isometric for online, flipped for joiner
	arena.set_camera_mode("isometric", false)
	arena.set_perspective_flipped(not _is_host, false)

	# Register with sim
	for puck: CaromPuck in setup.pucks:
		_bridge.register_puck(puck, puck.global_position)
	_bridge.register_turret(_local_turret)
	_bridge.register_turret(_remote_turret)

	# Late-bind the bridge and turrets to the existing multiplayer controller
	_multiplayer_ctrl.bind_match(_bridge, _local_turret, _remote_turret)
	_multiplayer_ctrl.is_host_side = _is_host
	_multiplayer_ctrl.lockstep = true

	# Effects + HUD
	_setup_effects()
	_local_turret.ammo_changed.connect(func(ammo: int, max_a: int) -> void:
		hud.update_player_ammo(ammo, max_a, _local_turret.is_reloading))
	_local_turret.reload_state_changed.connect(func(_r: bool) -> void:
		hud.update_player_ammo(_local_turret.current_ammo, _local_turret.clip_size, _local_turret.is_reloading))
	hud.reload_requested.connect(func() -> void:
		if _local_turret and _local_turret.is_active:
			_local_turret.start_reload())


func _on_match_started() -> void:
	phase = Phase.PLAYING
	connection_status_changed.emit("playing", "")
	_begin_play()


func _on_match_disconnected() -> void:
	if phase == Phase.PLAYING:
		# Opponent disconnected mid-match — pause and start countdown
		_enter_disconnect_state("Opponent disconnected")
	elif phase == Phase.DISCONNECTED:
		pass  # Already handling disconnect
	elif phase != Phase.GAME_OVER:
		phase = Phase.IDLE
		connection_status_changed.emit("error", "Connection lost")


func _enter_disconnect_state(message: String) -> void:
	phase = Phase.DISCONNECTED
	_disconnect_timer = DISCONNECT_TIMEOUT
	hud.show_disconnect_overlay(message)
	hud.update_disconnect_countdown(ceili(_disconnect_timer))


func _process_disconnect(delta: float) -> void:
	_disconnect_timer -= delta
	var secs := ceili(_disconnect_timer)
	hud.update_disconnect_countdown(secs)
	if _disconnect_timer <= 0.0:
		# Timeout — opponent forfeits
		hud.hide_disconnect_overlay()
		phase = Phase.GAME_OVER
		set_process(false)
		match_ended.emit(true, _player_score, _opponent_score, true)


func _on_connection_failed(reason: String) -> void:
	phase = Phase.IDLE
	connection_status_changed.emit("error", reason)


func _begin_play() -> void:
	_match_round.configure(arena, setup)
	_match_round.start_round()
	_timer_sim = SimWorld.new()
	_timer_accum = 0.0
	_tick_accum = 0.0
	hud.update_scores(_player_score, _opponent_score)
	hud.update_player_ammo(_local_turret.current_ammo, _local_turret.clip_size, false)
	set_process(true)


# ---------------------------------------------------------------------------
# Tick loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if phase == Phase.DISCONNECTED:
		_process_disconnect(delta)
		return

	if phase != Phase.PLAYING:
		return

	# Soft-disconnect detection: if lockstep is stuck for too long, opponent is gone
	if _multiplayer_ctrl and _multiplayer_ctrl._lockstep_pending_send:
		_no_input_timer += delta
		if _no_input_timer >= SOFT_DISCONNECT_TIMEOUT:
			_enter_disconnect_state("Opponent disconnected")
			return
	else:
		_no_input_timer = 0.0

	_tick_accum += delta

	# Lockstep: only attempt one tick per frame, wait for remote input
	if _tick_accum >= TICK_RATE:
		if _multiplayer_ctrl and _multiplayer_ctrl._lockstep_pending_send:
			# Already waiting for remote input — just poll, don't consume new events
			_multiplayer_ctrl.advance_with_input(0.0, false, false)
		else:
			_do_tick()
		# Only drain the accumulator if the tick actually advanced
		if _multiplayer_ctrl and _multiplayer_ctrl._lockstep_pending_send == false:
			_tick_accum -= TICK_RATE
			# Cap to prevent burst after a stall
			_tick_accum = minf(_tick_accum, TICK_RATE)

	# Match timer
	_timer_accum += delta
	while _timer_accum >= TICK_RATE:
		_timer_accum -= TICK_RATE
		_timer_sim.advance()
		if _timer_sim.time_expired:
			_on_time_expired()
			return
	hud.update_timer(_timer_sim.get_timer_ticks_remaining(), false)


func _do_tick() -> void:
	if _multiplayer_ctrl == null or not _multiplayer_ctrl.is_ready_to_play():
		return

	# Capture local turret's aim angle (absolute radians for the wire)
	var aim_rad: float = deg_to_rad(_local_turret.aim_offset_degrees + _local_turret.base_yaw_degrees)

	# Poll fire/reload events that occurred since last tick
	var events: Dictionary = _local_turret.consume_tick_events()
	var fire: bool = events.fired
	var reload: bool = events.reloaded

	_multiplayer_ctrl.advance_with_input(aim_rad, fire, reload)


# ---------------------------------------------------------------------------
# Goal scoring
# ---------------------------------------------------------------------------

func _on_goal_scored(scoring_side: StringName, goal_puck: CaromPuck) -> void:
	if phase != Phase.PLAYING:
		return

	var puck_index := setup.pucks.find(goal_puck)
	if puck_index >= 0:
		var spawn_positions := arena.get_puck_spawn_positions()
		var reset_pos := spawn_positions[puck_index] if puck_index < spawn_positions.size() else arena.get_puck_spawn_position()
		goal_puck.reset_to_center(reset_pos)

	# Determine who scored based on goal side and which side the local player is on
	var local_scored: bool = false
	if _is_host:
		# Host is south — scores when puck enters north goal
		local_scored = scoring_side == &"south"
	else:
		# Joiner is north — scores when puck enters south goal
		local_scored = scoring_side == &"north"

	if local_scored:
		_player_score += 1
		HapticManager.vibrate_success()
	else:
		_opponent_score += 1
		HapticManager.vibrate_error()

	hud.update_scores(_player_score, _opponent_score)

	if _effects:
		var goal_zone := arena.south_goal if scoring_side == &"north" else arena.north_goal
		var scoring_color := _local_turret.team_color if local_scored else _remote_turret.team_color
		_effects.play_goal_scored(goal_puck.global_position, scoring_side, scoring_color, goal_puck, goal_zone)

	if _player_score >= score_limit or _opponent_score >= score_limit:
		_finish_match()
		return

	_match_round.unlock_goals()


func _on_bridge_puck_zone_entered(body_id: int, zone_id: int) -> void:
	var puck_node := _bridge.get_puck_node(body_id)
	if puck_node == null:
		return
	var scoring_side: StringName = &"south" if zone_id == CaromSimBridge.ZONE_NORTH_GOAL else &"north"
	arena.on_sim_puck_scored(puck_node, scoring_side)


func _on_bridge_projectile_zone_entered(body_id: int, _zone_id: int) -> void:
	var projectile := _bridge.get_projectile_node(body_id)
	if is_instance_valid(projectile):
		projectile.enter_goal()


func _on_time_expired() -> void:
	_finish_match()


func _finish_match() -> void:
	phase = Phase.GAME_OVER
	set_process(false)
	_match_round.end_round()
	var won: bool = _player_score > _opponent_score
	match_ended.emit(won, _player_score, _opponent_score, false)


# ---------------------------------------------------------------------------
# HUD / Pause
# ---------------------------------------------------------------------------

var _is_paused: bool = false

func _on_pause() -> void:
	if _is_paused or phase != Phase.PLAYING:
		return
	_is_paused = true
	set_process(false)
	hud.show_pause_overlay()
	hud.set_pause_button_visible(false)


func _on_resume() -> void:
	if not _is_paused:
		return
	_is_paused = false
	hud.hide_pause_overlay()
	hud.set_pause_button_visible(true)
	set_process(true)


func _on_menu() -> void:
	shutdown()
	SceneTransition.transition_to(Scenes.CAROM_MENU)


func _on_camera_mode_changed(mode: String) -> void:
	arena.set_camera_mode(mode, true)


# ---------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------

func _setup_effects() -> void:
	if _effects == null:
		_effects = CaromEffectsController.new()
		_effects.name = "EffectsController"
		arena.add_child(_effects)
	_effects.register_turret(_local_turret)
	_effects.register_turret(_remote_turret)


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

func shutdown() -> void:
	set_process(false)
	if _multiplayer_ctrl:
		_multiplayer_ctrl.shutdown()


func _exit_tree() -> void:
	shutdown()
