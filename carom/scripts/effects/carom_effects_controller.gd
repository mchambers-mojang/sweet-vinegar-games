class_name CaromEffectsController
extends Node

## Wires up all visual effects for a Carom match.
## Add as child of CaromArena. Listens for turret fire events and projectile collisions.

const ShotEffectsScript := preload("res://carom/scripts/effects/shot_effects.gd")
const GoalEffectsScript := preload("res://carom/scripts/effects/goal_effects.gd")
const CameraEffectsScript := preload("res://carom/scripts/effects/camera_effects.gd")

const GOAL_FRAGMENT_Y_OFFSET: float = GoalEffectsScript.GOAL_FRAGMENT_Y_OFFSET

var _screen_shake: CaromScreenShake = null
var _impact_spawner: CaromImpactSpawner = null
var _arena: CaromArena = null
var _shot_effects = ShotEffectsScript.new()
var _goal_effects = GoalEffectsScript.new()
var _camera_effects = CameraEffectsScript.new()


func _ready() -> void:
	_arena = get_parent() as CaromArena
	if _arena == null:
		push_warning("CaromEffectsController must be a child of CaromArena")
		return

	# Create impact spawner
	_impact_spawner = CaromImpactSpawner.new()
	_impact_spawner.name = "ImpactSpawner"
	add_child(_impact_spawner)

	# Find or create screen shake on the camera
	_setup_screen_shake()

	_impact_spawner.set_screen_shake(_screen_shake)
	_configure_effects()


func _setup_screen_shake() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_screen_shake = null
		return
	# Check if shake already exists
	_screen_shake = camera.get_node_or_null("ScreenShake") as CaromScreenShake
	if _screen_shake == null:
		_screen_shake = CaromScreenShake.new()
		_screen_shake.name = "ScreenShake"
		camera.add_child(_screen_shake)


func _configure_effects() -> void:
	_shot_effects.setup(_arena, _impact_spawner, _screen_shake)
	_goal_effects.setup(_arena)
	_camera_effects.setup(get_viewport().get_camera_3d(), _screen_shake)


## Register a turret so its projectiles get trails and impact detection.
func register_turret(turret: CaromTurret) -> void:
	_shot_effects.register_turret(turret)


## Play goal celebration — lighter version for every goal (shake + quick zoom).
func play_goal_scored(
	goal_position: Vector3,
	scoring_side: StringName = StringName(),
	color: Color = Color.WHITE,
	goal_puck: CaromPuck = null,
	goal_zone: Area3D = null
) -> Node3D:
	var celebration: Node3D = null
	if _arena != null and (goal_zone != null or goal_puck != null or scoring_side != StringName()):
		var celebration_position := goal_zone.global_position if is_instance_valid(goal_zone) else goal_position
		celebration = _goal_effects.play_goal_celebration(celebration_position, scoring_side, color, goal_puck, goal_zone)

	_setup_screen_shake()
	_configure_effects()
	_camera_effects.play_goal_camera(goal_position)
	return celebration


func play_goal_celebration(
	goal_position: Vector3,
	scoring_side: StringName,
	color: Color,
	goal_puck: CaromPuck = null,
	goal_zone: Area3D = null
) -> Node3D:
	return _goal_effects.play_goal_celebration(goal_position, scoring_side, color, goal_puck, goal_zone)


func play_match_win(goal_position: Vector3) -> void:
	_setup_screen_shake()
	_configure_effects()
	_camera_effects.play_match_win(goal_position)
