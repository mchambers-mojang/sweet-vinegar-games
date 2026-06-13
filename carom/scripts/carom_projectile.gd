class_name CaromProjectile
extends RigidBody3D

## Straight-line projectile that bounces off walls and pushes the puck via natural physics.
## Only leaves play when entering a goal area.

@export var speed: float = 18.0

var direction: Vector3 = Vector3.FORWARD
var owner_side: StringName = StringName()


func _ready() -> void:
	# Lock to ground plane
	axis_lock_linear_y = true
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func setup(new_direction: Vector3, new_speed: float, new_owner_side: StringName, color: Color = Color(0.16, 0.95, 1.0)) -> void:
	direction = new_direction.normalized()
	if new_speed > 0.0:
		speed = new_speed
	owner_side = new_owner_side
	linear_velocity = direction * speed
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


func _physics_process(_delta: float) -> void:
	# Keep projectile moving at constant speed (counteract energy loss from bounces)
	var current_speed := linear_velocity.length()
	if current_speed > 0.1:
		linear_velocity = linear_velocity.normalized() * speed
	# Keep on ground plane
	global_position.y = 0.0
	linear_velocity.y = 0.0


func _on_body_entered(body: Node) -> void:
	if body is CaromPuck:
		# Destroy projectile after hitting the puck — physics impulse already transferred
		queue_free()


## Called by goal Area3D when this projectile enters — removes from play.
func enter_goal() -> void:
	queue_free()
