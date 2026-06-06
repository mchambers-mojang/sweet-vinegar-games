class_name CaromTurret
extends Node3D

## Mounted turret controller — handles aim, firing, manual reload, and simple AI behavior.

signal ammo_changed(current_ammo: int, max_ammo: int)
signal reload_state_changed(is_reloading: bool)
signal projectile_fired(projectile: CaromProjectile)

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
@export var aim_arc_degrees: float = 90.0
@export var base_yaw_degrees: float = 180.0
@export var control_mode: ControlMode = ControlMode.HUMAN
@export var touch_drag_sensitivity: float = 0.12

@export var team_color: Color = Color(0.16, 0.95, 1.0, 1.0)

var side: StringName = &"south"
var current_ammo: int = 0
var is_reloading: bool = false
var is_active: bool = true
var aim_offset_degrees: float = 0.0

var _reload_timer: float = 0.0
var _fire_cooldown_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _ai_target_aim_degrees: float = 0.0
var _ai_fire_timer: float = 0.0
var _ai_retarget_timer: float = 0.0

@onready var projectile_spawn: Marker3D = $ProjectileSpawn


func _ready() -> void:
	_rng.randomize()
	current_ammo = clip_size
	_schedule_ai_behavior()
	_update_rotation()
	ammo_changed.emit(current_ammo, clip_size)


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
	if control_mode == ControlMode.AI:
		_schedule_ai_behavior()
	ammo_changed.emit(current_ammo, clip_size)
	reload_state_changed.emit(false)


func set_active(active: bool) -> void:
	is_active = active
	if not is_active:
		cancel_reload()


func _process(delta: float) -> void:
	if _fire_cooldown_timer > 0.0:
		_fire_cooldown_timer = maxf(0.0, _fire_cooldown_timer - delta)

	if not is_active:
		return

	if control_mode == ControlMode.HUMAN:
		_process_human_input(delta)
	else:
		_process_ai(delta)

	_process_reload(delta)
	_update_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active or control_mode != ControlMode.HUMAN:
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			try_fire()
	elif event is InputEventScreenTouch:
		var screen_touch := event as InputEventScreenTouch
		if screen_touch.pressed:
			try_fire()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		aim_offset_degrees = clampf(
			aim_offset_degrees + drag.relative.x * touch_drag_sensitivity,
			-aim_arc_degrees * 0.5,
			aim_arc_degrees * 0.5
		)
		_update_rotation()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_R:
			start_reload()


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

	var parent_scene := get_tree().current_scene
	if parent_scene == null:
		parent_scene = get_parent()
	parent_scene.add_child(projectile)
	projectile.global_position = projectile_spawn.global_position
	projectile.setup(-projectile_spawn.global_transform.basis.z.normalized(), projectile_speed, side, team_color)
	projectile_fired.emit(projectile)

	if control_mode == ControlMode.AI and current_ammo <= 0:
		start_reload()
	return true


func start_reload() -> void:
	if current_ammo >= clip_size or is_reloading:
		return
	is_reloading = true
	_reload_timer = 0.0
	reload_state_changed.emit(true)


func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	_reload_timer = 0.0
	reload_state_changed.emit(false)


func _process_human_input(delta: float) -> void:
	var horizontal_input := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	if absf(horizontal_input) > 0.0:
		aim_offset_degrees = clampf(
			aim_offset_degrees + horizontal_input * aim_speed_degrees * delta,
			-aim_arc_degrees * 0.5,
			aim_arc_degrees * 0.5
		)

	if Input.is_action_just_pressed("ui_accept"):
		try_fire()

	if InputMap.has_action("reload"):
		if Input.is_action_just_pressed("reload"):
			start_reload()


func _process_ai(delta: float) -> void:
	_ai_retarget_timer -= delta
	if _ai_retarget_timer <= 0.0:
		_ai_target_aim_degrees = _rng.randf_range(-aim_arc_degrees * 0.5, aim_arc_degrees * 0.5)
		_ai_retarget_timer = _rng.randf_range(0.6, 1.4)

	aim_offset_degrees = move_toward(aim_offset_degrees, _ai_target_aim_degrees, aim_speed_degrees * delta * 0.7)

	_ai_fire_timer -= delta
	if _ai_fire_timer > 0.0:
		return

	if current_ammo <= 0:
		start_reload()
		_ai_fire_timer = _rng.randf_range(0.5, 0.9)
		return

	if is_reloading and current_ammo > 0 and _rng.randf() < 0.3:
		try_fire()
	elif not is_reloading:
		if current_ammo <= 2 and _rng.randf() < 0.35:
			start_reload()
		else:
			try_fire()
	_ai_fire_timer = _rng.randf_range(0.7, 1.35)


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
			cancel_reload()
			break


func _schedule_ai_behavior() -> void:
	_ai_target_aim_degrees = _rng.randf_range(-aim_arc_degrees * 0.5, aim_arc_degrees * 0.5)
	_ai_fire_timer = _rng.randf_range(0.7, 1.2)
	_ai_retarget_timer = _rng.randf_range(0.4, 1.0)


func _update_rotation() -> void:
	rotation_degrees = Vector3(0.0, base_yaw_degrees + aim_offset_degrees, 0.0)
