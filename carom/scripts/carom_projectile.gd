class_name CaromProjectile
extends Node3D

## Straight-line projectile — render adapter.
## Position is driven by CaromSimBridge each frame via interpolation between
## deterministic sim ticks.  The sim handles all bouncing and collision logic.

## Emitted by CaromSimBridge when the sim body collides with something.
## pos is the impact position in world space; hit_puck is true when the
## collision was against the puck body.
signal impact_occurred(pos: Vector3, hit_puck: bool)

@export var speed: float = 18.0

var direction: Vector3 = Vector3.FORWARD
var owner_side: StringName = StringName()

## Set by CaromSimBridge.setup_sim_bridge() after the projectile is registered.
var _bridge: CaromSimBridge = null
var _sim_body_id: int = 0


func setup(new_direction: Vector3, new_speed: float, new_owner_side: StringName, color: Color = Color(0.16, 0.95, 1.0)) -> void:
	direction = new_direction.normalized()
	if new_speed > 0.0:
		speed = new_speed
	owner_side = new_owner_side
	if direction.length_squared() > 0.0:
		look_at(global_position + direction, Vector3.UP)
	# Apply team color to mesh
	var mesh_instance := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color.r * 0.1, color.g * 0.1, color.b * 0.1)
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.0
		mesh_instance.material_override = mat


## Called by CaromSimBridge after the projectile's sim body is registered.
func setup_sim_bridge(bridge: CaromSimBridge, body_id: int) -> void:
	_bridge = bridge
	_sim_body_id = body_id


func _process(_delta: float) -> void:
	if _bridge != null and _sim_body_id != 0:
		var alpha := _bridge.get_render_alpha()
		global_position = _bridge.get_projectile_position(_sim_body_id, alpha)


## Called when this projectile enters a goal zone — removes it from play.
func enter_goal() -> void:
	queue_free()

