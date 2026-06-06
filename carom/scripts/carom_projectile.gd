class_name CaromProjectile
extends CharacterBody3D

## Straight-line projectile that imparts force to the puck and bounces off walls.
## Only leaves play when entering a goal area.

@export var speed: float = 18.0
@export var puck_impulse: float = 4.0

var direction: Vector3 = Vector3.FORWARD
var owner_side: StringName = StringName()


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING


func setup(new_direction: Vector3, new_speed: float, new_owner_side: StringName) -> void:
	direction = new_direction.normalized()
	if new_speed > 0.0:
		speed = new_speed
	owner_side = new_owner_side
	if direction.length_squared() > 0.0:
		look_at(global_position + direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	var collision: KinematicCollision3D = move_and_collide(direction * speed * delta)
	if collision:
		_handle_collision(collision)


func _handle_collision(collision: KinematicCollision3D) -> void:
	var collider := collision.get_collider()
	if collider is CaromPuck:
		var puck := collider as CaromPuck
		var impact_offset := collision.get_position() - puck.global_position
		puck.apply_impulse(direction * puck_impulse, impact_offset)
	# Bounce off everything (walls, puck, other projectiles)
	var normal := collision.get_normal()
	direction = direction.bounce(normal).normalized()


## Called by goal Area3D when this projectile enters — removes from play.
func enter_goal() -> void:
	queue_free()
