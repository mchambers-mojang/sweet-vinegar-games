class_name CaromTurret
extends Node3D

## Mounted turret controller — handles aim, firing, manual reload.
## Input is provided by a CaromTurretInput (human or AI).

signal ammo_changed(current_ammo: int, max_ammo: int)
signal reload_state_changed(is_reloading: bool)
signal reload_completed
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
@export var aim_arc_degrees: float = 160.0
@export var base_yaw_degrees: float = 180.0
@export var control_mode: ControlMode = ControlMode.HUMAN
@export var touch_drag_sensitivity: float = 0.12

@export var team_color: Color = Color(0.16, 0.95, 1.0, 1.0)

const AIM_PROJECTION_SCRIPT := preload("res://carom/scripts/carom_aim_projection.gd")

var side: StringName = &"south"
var current_ammo: int = 0
var is_reloading: bool = false
var is_active: bool = true
var aim_offset_degrees: float = 0.0

var _reload_timer: float = 0.0
var _fire_cooldown_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _aim_projection: CaromAimProjection = null
var _aim_projection_distance: float = 0.0
var _ammo_indicators: Array[MeshInstance3D] = []
var _ammo_ring_node: Node3D = null
var _pulse_tween: Tween = null

## Input provider (CaromHumanInput or CaromAI)
var input: CaromTurretInput = null

## AI controller reference (for debug overlay access)
var ai_controller: CaromAI = null

@onready var projectile_spawn: Marker3D = $ProjectileSpawn


func _ready() -> void:
	_rng.randomize()
	current_ammo = clip_size
	_update_rotation()
	_create_ammo_ring()
	ammo_changed.connect(_on_ammo_changed_visual)
	ammo_changed.emit(current_ammo, clip_size)
	_ensure_aim_projection()
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


func _process(delta: float) -> void:
	if _fire_cooldown_timer > 0.0:
		_fire_cooldown_timer = maxf(0.0, _fire_cooldown_timer - delta)

	if not is_active:
		return

	# Poll input provider for commands
	if input:
		var state := _get_turret_state()
		var commands := input.process(delta, state)
		_apply_commands(commands)

	_process_reload(delta)
	_update_rotation()
	_update_aim_projection()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active or control_mode != ControlMode.HUMAN:
		return
	if input is CaromHumanInput:
		(input as CaromHumanInput).handle_input_event(event, aim_arc_degrees)

func set_aim_projection_distance(distance: float) -> void:
	_aim_projection_distance = maxf(0.0, distance)
	_ensure_aim_projection()
	if _aim_projection:
		_aim_projection.set_max_distance(_aim_projection_distance)


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
			cancel_reload()
			_pulse_ammo_ring()
			reload_completed.emit()
			break


func _update_rotation() -> void:
	rotation_degrees = Vector3(0.0, base_yaw_degrees + aim_offset_degrees, 0.0)


func _ensure_aim_projection() -> void:
	if _aim_projection == null:
		_aim_projection = AIM_PROJECTION_SCRIPT.new() as CaromAimProjection
		if _aim_projection:
			_aim_projection.name = "AimProjection"
			add_child(_aim_projection)


func _update_aim_projection() -> void:
	if _aim_projection == null:
		return
	if _aim_projection_distance <= 0.0:
		_aim_projection.visible = false
		return
	var direction := -projectile_spawn.global_transform.basis.z.normalized()
	_aim_projection.update_projection(projectile_spawn.global_position, direction)


# --- Ammo ring (3D visual on turret base) ---

const AMMO_RING_RADIUS: float = 0.8
const AMMO_BULLET_RADIUS: float = 0.1
const AMMO_BULLET_HEIGHT: float = 0.35

func _create_ammo_ring() -> void:
	_ammo_ring_node = Node3D.new()
	_ammo_ring_node.name = "AmmoRing"
	# Ring stays world-aligned (doesn't rotate with turret aim)
	get_parent().call_deferred("add_child", _ammo_ring_node)
	call_deferred("_build_ammo_indicators")


func _build_ammo_indicators() -> void:
	_ammo_ring_node.global_position = global_position + Vector3(0.0, 0.25, 0.0)
	_ammo_indicators.clear()

	var arc_start := -PI * 0.4
	var arc_end := PI * 0.4
	var arc_span := arc_end - arc_start

	for i in clip_size:
		var angle := arc_start + (arc_span * float(i) / float(maxi(clip_size - 1, 1)))
		# Offset behind the turret (positive Z is toward player's own goal)
		var offset := Vector3(sin(angle) * AMMO_RING_RADIUS, 0.0, cos(angle) * AMMO_RING_RADIUS)
		if side == &"north":
			offset.z = -offset.z

		var mesh_inst := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = AMMO_BULLET_RADIUS
		capsule.height = AMMO_BULLET_HEIGHT
		mesh_inst.mesh = capsule

		var mat := StandardMaterial3D.new()
		mat.albedo_color = team_color
		mat.emission_enabled = true
		mat.emission = team_color
		mat.emission_energy_multiplier = 4.0
		mesh_inst.material_override = mat

		mesh_inst.position = offset
		_ammo_ring_node.add_child(mesh_inst)
		_ammo_indicators.append(mesh_inst)

	_update_ammo_visuals()


func _update_ammo_visuals() -> void:
	for i in _ammo_indicators.size():
		var indicator := _ammo_indicators[i]
		var mat := indicator.material_override as StandardMaterial3D
		if i < current_ammo:
			mat.albedo_color = team_color
			mat.emission = team_color
			mat.emission_energy_multiplier = 4.0
			indicator.scale = Vector3.ONE
			indicator.visible = true
		else:
			mat.albedo_color = Color(0.15, 0.15, 0.15)
			mat.emission = Color.BLACK
			mat.emission_energy_multiplier = 0.0
			indicator.scale = Vector3(0.5, 0.5, 0.5)
			indicator.visible = true


func _on_ammo_changed_visual(_current: int, _max: int) -> void:
	if _ammo_indicators.size() > 0:
		_update_ammo_visuals()


func _pulse_ammo_ring() -> void:
	if _ammo_indicators.is_empty():
		return
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_parallel(true)
	for indicator: MeshInstance3D in _ammo_indicators:
		var mat := indicator.material_override as StandardMaterial3D
		if mat == null:
			continue
		# Emission spike: 4.0 -> 12.0 over 0.05 s, then ease back to 4.0 over 0.3 s
		_pulse_tween.tween_property(mat, "emission_energy_multiplier", 12.0, 0.05)
		_pulse_tween.tween_property(mat, "emission_energy_multiplier", 4.0, 0.3).set_delay(0.05)
		# Scale bounce: 1.0 -> 1.3 -> 1.0 over 0.2 s
		_pulse_tween.tween_property(indicator, "scale", Vector3(1.3, 1.3, 1.3), 0.08)
		_pulse_tween.tween_property(indicator, "scale", Vector3.ONE, 0.12).set_delay(0.08)
