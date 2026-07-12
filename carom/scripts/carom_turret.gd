class_name CaromTurret
extends Node3D

## Mounted turret controller — handles aim, firing, manual reload.
## Input is provided by a CaromTurretInput (human or AI).
## All visual presentation is handled by the TurretVisuals child node.

signal ammo_changed(current_ammo: int, max_ammo: int)
signal reload_state_changed(is_reloading: bool)
signal reload_completed
signal projectile_fired(projectile: CaromProjectile)
signal aim_projection_distance_changed(distance: float)

enum ControlMode {
	HUMAN,
	AI,
}

@export var projectile_scene: PackedScene = preload("res://carom/scenes/carom_projectile.tscn")
@export var clip_size: int = 8
@export var reload_rate: float = 0.5
@export var projectile_speed: float = 18.0
@export var fire_cooldown: float = 0.18
@export var aim_speed_degrees: float = 110.0
@export var aim_arc_degrees: float = 160.0
@export var base_yaw_degrees: float = 180.0
@export var control_mode: ControlMode = ControlMode.HUMAN
@export var touch_drag_sensitivity: float = 0.12

@export var team_color: Color = Color(0.16, 0.95, 1.0, 1.0)

var side: StringName = &"south"
var current_ammo: int = 0
var is_reloading: bool = false
var is_active: bool = true
var aim_offset_degrees: float = 0.0
var aim_projection_distance: float = 0.0

var _reload_timer: float = 0.0
var _fire_cooldown_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Tick-level event flags for multiplayer input capture.
## Poll via consume_tick_events() each sim tick, then clear.
var _fired_this_tick: bool = false
var _reload_started_this_tick: bool = false

## When true, fire/reload are deferred to apply_tick() for determinism.
## Aim input still flows freely in _process for responsiveness.
var multiplayer_driven: bool = false

## Pending fire/reload intent for next tick (set by input, consumed by _do_tick).
var _pending_fire: bool = false
var _pending_reload: bool = false

## Input provider (CaromHumanInput or CaromAI)
var input: CaromTurretInput = null

## AI controller reference (for debug overlay access)
var ai_controller: CaromAI = null

@onready var projectile_spawn: Marker3D = $ProjectileSpawn


func _ready() -> void:
	_rng.randomize()
	current_ammo = clip_size
	_update_rotation()
	ammo_changed.emit(current_ammo, clip_size)
	# Default to human input if not configured yet
	if input == null and control_mode == ControlMode.HUMAN:
		input = CaromHumanInput.new()


func setup_ai(difficulty: CaromAIDifficulty, puck: CaromPuck, opponent: CaromTurret, midfield_z: float, own_goal_z: float) -> void:
	var ai := CaromAI.new(difficulty)
	ai.configure_arena(midfield_z, own_goal_z)
	ai.set_puck(puck)
	ai.set_opponent(opponent)
	ai_controller = ai
	input = ai


func configure(new_side: StringName, new_control_mode: ControlMode, new_base_yaw_degrees: float, new_color: Color = Color(-1, -1, -1)) -> void:
	side = new_side
	control_mode = new_control_mode
	base_yaw_degrees = new_base_yaw_degrees
	if new_color.r >= 0.0:
		team_color = new_color
	_update_rotation()


func reset_for_round() -> void:
	is_active = true
	is_reloading = false
	_reload_timer = 0.0
	_fire_cooldown_timer = 0.0
	current_ammo = clip_size
	if ai_controller:
		ai_controller.reset()
	ammo_changed.emit(current_ammo, clip_size)
	reload_state_changed.emit(false)


func set_active(active: bool) -> void:
	is_active = active
	if not is_active:
		cancel_reload()


func set_aim_projection_distance(distance: float) -> void:
	aim_projection_distance = maxf(0.0, distance)
	aim_projection_distance_changed.emit(aim_projection_distance)


func _process(delta: float) -> void:
	if _fire_cooldown_timer > 0.0 and not multiplayer_driven:
		_fire_cooldown_timer = maxf(0.0, _fire_cooldown_timer - delta)

	if not is_active:
		return

	# Poll input provider for commands
	if input:
		var state := _get_turret_state()
		var commands := input.process(delta, state)
		if multiplayer_driven:
			# Only apply aim; record fire/reload as pending for next tick
			if commands.has("aim_target"):
				aim_offset_degrees = clampf(
					commands["aim_target"],
					-aim_arc_degrees * 0.5,
					aim_arc_degrees * 0.5
				)
			if commands.get("fire", false):
				_pending_fire = true
			if commands.get("start_reload", false):
				_pending_reload = true
		else:
			_apply_commands(commands)
			_process_reload(delta)

	_update_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active or control_mode != ControlMode.HUMAN:
		return
	if input:
		input.handle_input_event(event, aim_arc_degrees)


func try_fire() -> bool:
	if _fire_cooldown_timer > 0.0:
		return false
	if current_ammo <= 0:
		return false
	if projectile_scene == null:
		return false
	if is_reloading:
		cancel_reload()

	var projectile := projectile_scene.instantiate() as CaromProjectile
	if projectile == null:
		return false

	current_ammo -= 1
	ammo_changed.emit(current_ammo, clip_size)
	_fire_cooldown_timer = fire_cooldown
	_fired_this_tick = true

	var parent_scene := get_tree().current_scene
	if parent_scene == null:
		parent_scene = get_parent()
	parent_scene.add_child(projectile)
	projectile.global_position = projectile_spawn.global_position
	projectile.setup(-projectile_spawn.global_transform.basis.z.normalized(), projectile_speed, side, team_color)
	projectile_fired.emit(projectile)
	return true


func start_reload() -> void:
	if current_ammo >= clip_size or is_reloading:
		return
	is_reloading = true
	_reload_timer = 0.0
	_reload_started_this_tick = true
	reload_state_changed.emit(true)


func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	_reload_timer = 0.0
	reload_state_changed.emit(false)


## Poll and clear tick-level events. Returns {fired: bool, reloaded: bool}.
## Call once per sim tick in multiplayer to capture input for the network.
func consume_tick_events() -> Dictionary:
	var events: Dictionary
	if multiplayer_driven:
		# In multiplayer, read from pending intent flags (set by _process input)
		events = { fired = _pending_fire, reloaded = _pending_reload }
		_pending_fire = false
		_pending_reload = false
	else:
		events = { fired = _fired_this_tick, reloaded = _reload_started_this_tick }
		_fired_this_tick = false
		_reload_started_this_tick = false
	return events


## Apply one multiplayer tick with deterministic inputs. Call BEFORE sim advance.
## aim_offset_deg: turret aim offset in degrees (derived from quantized value)
## fire: true if player fired this tick
## reload: true if player started reload this tick
## tick_delta: fixed time step (e.g. 1/30)
func apply_tick(aim_offset_deg: float, fire: bool, reload: bool, tick_delta: float) -> void:
	# Apply aim
	aim_offset_degrees = clampf(aim_offset_deg, -aim_arc_degrees * 0.5, aim_arc_degrees * 0.5)
	_update_rotation()

	# Process fire cooldown with fixed delta
	if _fire_cooldown_timer > 0.0:
		_fire_cooldown_timer = maxf(0.0, _fire_cooldown_timer - tick_delta)

	# Fire
	if fire:
		try_fire()

	# Reload
	if reload and not is_reloading and current_ammo < clip_size:
		start_reload()

	# Process reload with fixed delta
	_process_reload(tick_delta)


func _get_turret_state() -> Dictionary:
	return {
		"aim_offset": aim_offset_degrees,
		"aim_arc": aim_arc_degrees,
		"aim_speed": aim_speed_degrees,
		"base_yaw": base_yaw_degrees,
		"ammo": current_ammo,
		"clip_size": clip_size,
		"is_reloading": is_reloading,
		"is_active": is_active,
		"global_position": global_position,
	}


func _apply_commands(commands: Dictionary) -> void:
	if commands.is_empty():
		return
	if commands.has("aim_target"):
		aim_offset_degrees = clampf(
			commands["aim_target"],
			-aim_arc_degrees * 0.5,
			aim_arc_degrees * 0.5
		)
	if commands.get("fire", false):
		try_fire()
	if commands.get("cancel_reload", false):
		cancel_reload()
	if commands.get("start_reload", false):
		start_reload()


func _process_reload(delta: float) -> void:
	if not is_reloading:
		return
	if current_ammo >= clip_size:
		cancel_reload()
		return

	_reload_timer += delta
	while _reload_timer >= reload_rate and current_ammo < clip_size:
		_reload_timer -= reload_rate
		current_ammo += 1
		ammo_changed.emit(current_ammo, clip_size)
		if current_ammo >= clip_size:
			if control_mode == ControlMode.HUMAN:
				FeedbackManager.vibrate_medium()
			cancel_reload()
			reload_completed.emit()
			break


func _update_rotation() -> void:
	rotation_degrees = Vector3(0.0, base_yaw_degrees + aim_offset_degrees, 0.0)
