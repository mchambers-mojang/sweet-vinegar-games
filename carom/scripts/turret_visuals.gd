class_name TurretVisuals
extends Node3D

## Presentation layer for CaromTurret.
## Must be a direct child of a CaromTurret node.
## Listens to turret signals and renders:
##   - Ammo ring (capsule meshes arranged in arc behind turret, world-aligned)
##   - Aim projection line (CaromAimProjection, rotates with turret)
##   - Reload pulse animation on the ammo ring

const AMMO_RING_RADIUS: float = 0.8
const AMMO_BULLET_RADIUS: float = 0.1
const AMMO_BULLET_HEIGHT: float = 0.35

var _turret: CaromTurret = null
var _aim_projection: CaromAimProjection = null
var _ammo_ring_node: Node3D = null
var _ammo_indicators: Array[MeshInstance3D] = []
var _pulse_tween: Tween = null


func _ready() -> void:
	_turret = get_parent() as CaromTurret
	if _turret == null:
		push_error("TurretVisuals must be a direct child of CaromTurret")
		return
	_turret.ammo_changed.connect(_on_ammo_changed)
	_turret.reload_completed.connect(_on_reload_completed)
	_turret.aim_projection_distance_changed.connect(_on_aim_projection_distance_changed)
	_create_ammo_ring()
	_ensure_aim_projection()


func _process(_delta: float) -> void:
	_update_aim_projection()


func _exit_tree() -> void:
	# Disconnect signals so a lingering turret reference can't call into a freed node.
	if _turret != null:
		if _turret.ammo_changed.is_connected(_on_ammo_changed):
			_turret.ammo_changed.disconnect(_on_ammo_changed)
		if _turret.reload_completed.is_connected(_on_reload_completed):
			_turret.reload_completed.disconnect(_on_reload_completed)
		if _turret.aim_projection_distance_changed.is_connected(_on_aim_projection_distance_changed):
			_turret.aim_projection_distance_changed.disconnect(_on_aim_projection_distance_changed)
	# Free the ammo ring node: it lives under the turret's parent (not under
	# TurretVisuals) so it is not freed automatically when this node is removed.
	if _ammo_ring_node and is_instance_valid(_ammo_ring_node):
		_ammo_ring_node.queue_free()
		_ammo_ring_node = null


# --- Aim projection ---

func _ensure_aim_projection() -> void:
	if _aim_projection == null:
		_aim_projection = CaromAimProjection.new()
		_aim_projection.name = "AimProjection"
		add_child(_aim_projection)


func _update_aim_projection() -> void:
	if _aim_projection == null or _turret == null:
		return
	if _turret.aim_projection_distance <= 0.0:
		_aim_projection.visible = false
		return
	var spawn := _turret.projectile_spawn
	var direction := -spawn.global_transform.basis.z.normalized()
	_aim_projection.update_projection(spawn.global_position, direction)


func _on_aim_projection_distance_changed(distance: float) -> void:
	_ensure_aim_projection()
	if _aim_projection:
		_aim_projection.set_max_distance(distance)


# --- Ammo ring ---

func _create_ammo_ring() -> void:
	_ammo_ring_node = Node3D.new()
	_ammo_ring_node.name = "AmmoRing"
	# Ring is added to the turret's parent so it stays world-aligned and
	# does not rotate when the turret aims.
	_turret.get_parent().call_deferred("add_child", _ammo_ring_node)
	call_deferred("_build_ammo_indicators")


func _build_ammo_indicators() -> void:
	# Turrets are stationary during a match, so setting the ring position once
	# here is sufficient and matches the original single-assignment behaviour.
	_ammo_ring_node.global_position = _turret.global_position + Vector3(0.0, 0.25, 0.0)
	_ammo_indicators.clear()

	var arc_start := -PI * 0.4
	var arc_end := PI * 0.4
	var arc_span := arc_end - arc_start

	for i in _turret.clip_size:
		var angle := arc_start + (arc_span * float(i) / float(maxi(_turret.clip_size - 1, 1)))
		# Offset behind the turret (positive Z is toward the player's own goal).
		var offset := Vector3(sin(angle) * AMMO_RING_RADIUS, 0.0, cos(angle) * AMMO_RING_RADIUS)
		if _turret.side == &"north":
			offset.z = -offset.z

		var mesh_inst := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = AMMO_BULLET_RADIUS
		capsule.height = AMMO_BULLET_HEIGHT
		mesh_inst.mesh = capsule

		var mat := StandardMaterial3D.new()
		mat.albedo_color = _turret.team_color
		mat.emission_enabled = true
		mat.emission = _turret.team_color
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
		if i < _turret.current_ammo:
			mat.albedo_color = _turret.team_color
			mat.emission = _turret.team_color
			mat.emission_energy_multiplier = 4.0
			indicator.scale = Vector3.ONE
			indicator.visible = true
		else:
			mat.albedo_color = Color(0.15, 0.15, 0.15)
			mat.emission = Color.BLACK
			mat.emission_energy_multiplier = 0.0
			indicator.scale = Vector3(0.5, 0.5, 0.5)
			indicator.visible = true


func _on_ammo_changed(_current: int, _max: int) -> void:
	if _ammo_indicators.size() > 0:
		_update_ammo_visuals()


func _on_reload_completed() -> void:
	_pulse_ammo_ring()


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
		# Emission spike: 4.0 -> 12.0 over 0.05s, then ease back to 4.0 over 0.3s.
		_pulse_tween.tween_property(mat, "emission_energy_multiplier", 12.0, 0.05)
		_pulse_tween.tween_property(mat, "emission_energy_multiplier", 4.0, 0.3).set_delay(0.05)
		# Scale bounce: 1.0 -> 1.3 -> 1.0 over 0.2s.
		_pulse_tween.tween_property(indicator, "scale", Vector3(1.3, 1.3, 1.3), 0.08)
		_pulse_tween.tween_property(indicator, "scale", Vector3.ONE, 0.12).set_delay(0.08)
