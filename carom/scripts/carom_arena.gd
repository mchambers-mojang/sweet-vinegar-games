class_name CaromArena
extends Node3D

## Carom arena root — provides spawn points and goal detection for the match controller.

const CaromAmbientParticlesScene := preload("res://carom/scripts/effects/carom_ambient_particles.gd")
const CAMERA_TRANSITION_SECONDS: float = 0.5
const TOP_DOWN_POSITION: Vector3 = Vector3(0.0, 20.0, 12.0)
const TOP_DOWN_ROTATION: Vector3 = Vector3(-90.0, 0.0, 0.0)
const ISOMETRIC_POSITION: Vector3 = Vector3(0.0, 16.0, 24.0)
const ISOMETRIC_ROTATION: Vector3 = Vector3(-45.0, 0.0, 0.0)

signal goal_scored(scoring_side: StringName, puck: CaromPuck)

## Flipped camera constants (joiner perspective — looking from the north end).
## Position stays the same (ortho camera framing); rotation adds 180° on Z to flip the view.
const TOP_DOWN_POSITION_FLIPPED: Vector3 = Vector3(0.0, 20.0, 12.0)
const TOP_DOWN_ROTATION_FLIPPED: Vector3 = Vector3(-90.0, 0.0, 180.0)

## Flipped isometric — camera on the north side looking south.
const ISOMETRIC_POSITION_FLIPPED: Vector3 = Vector3(0.0, 16.0, 0.0)
const ISOMETRIC_ROTATION_FLIPPED: Vector3 = Vector3(-45.0, 180.0, 0.0)

@export var arena_width: float = 20.0
@export var arena_depth: float = 12.0

var _goal_locked: bool = false
var _perspective_flipped: bool = false
var _camera_mode_tween: Tween = null

@onready var south_goal: Area3D = $SouthGoal
@onready var north_goal: Area3D = $NorthGoal
@onready var south_turret_spawn: Marker3D = $SpawnMarkers/SouthTurretSpawn
@onready var north_turret_spawn: Marker3D = $SpawnMarkers/NorthTurretSpawn
@onready var puck_spawn: Marker3D = $SpawnMarkers/PuckSpawn
@onready var puck_spawn_2: Marker3D = $SpawnMarkers/PuckSpawn2
@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_setup_ambient_particles()
	CaromSettings.ensure_loaded()
	set_camera_mode(CaromSettings.camera_mode, false)
	_apply_camera_safe_area()
	get_tree().root.size_changed.connect(_apply_camera_safe_area)

	# If launched in online mode, swap the match controller
	if has_meta("carom_online"):
		remove_meta("carom_online")
		_switch_to_online_mode()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		# F5: Toggle perspective flip (debug — test joiner view in single player)
		if key.keycode == KEY_F5:
			toggle_perspective_flip()
			print("[DEBUG] Perspective flipped: %s" % _perspective_flipped)
			get_viewport().set_input_as_handled()


func set_camera_mode(mode: String, animate: bool = true) -> void:
	if _camera == null:
		return

	var target_mode := CaromSettings.normalize_camera_mode(mode)

	var target_position := TOP_DOWN_POSITION
	var target_rotation := TOP_DOWN_ROTATION
	if target_mode == CaromSettings.CAMERA_MODE_ISOMETRIC:
		target_position = ISOMETRIC_POSITION
		target_rotation = ISOMETRIC_ROTATION

	# Apply perspective flip if active (joiner sees from the opposite end)
	if _perspective_flipped:
		if target_mode == CaromSettings.CAMERA_MODE_ISOMETRIC:
			target_position = ISOMETRIC_POSITION_FLIPPED
			target_rotation = ISOMETRIC_ROTATION_FLIPPED
		else:
			target_position = TOP_DOWN_POSITION_FLIPPED
			target_rotation = TOP_DOWN_ROTATION_FLIPPED

	if is_instance_valid(_camera_mode_tween):
		_camera_mode_tween.kill()
		_camera_mode_tween = null

	if not animate:
		_camera.position = target_position
		_camera.rotation_degrees = target_rotation
		return

	_camera_mode_tween = create_tween()
	_camera_mode_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_camera_mode_tween.tween_property(_camera, "position", target_position, CAMERA_TRANSITION_SECONDS)
	_camera_mode_tween.parallel().tween_property(_camera, "rotation_degrees", target_rotation, CAMERA_TRANSITION_SECONDS)


## Flip the camera perspective so the viewer sees from the opposite end of the arena.
## Used in online multiplayer so the joiner always sees their turret at screen bottom.
func set_perspective_flipped(flipped: bool, animate: bool = false) -> void:
	_perspective_flipped = flipped
	# Re-apply current camera mode with the new flip state
	set_camera_mode(CaromSettings.camera_mode, animate)


## Toggle perspective flip at runtime (debug shortcut).
func toggle_perspective_flip() -> void:
	set_perspective_flipped(not _perspective_flipped, true)


func _setup_ambient_particles() -> void:
	var ambient := CaromAmbientParticlesScene.new()
	ambient.name = "AmbientParticles"
	add_child(ambient)
	ambient.setup(arena_width, arena_depth)


## Adjust orthographic camera frustum offset so the playfield doesn't render
## behind the notch or home indicator. Uses frustum_offset to shift the visible
## area without moving the camera node itself.
func _apply_camera_safe_area() -> void:
	if _camera == null:
		return
	var insets := SafeAreaManager.get_insets()
	var viewport_h: float = ProjectSettings.get_setting("display/window/size/viewport_height", 844)
	var viewport_w: float = ProjectSettings.get_setting("display/window/size/viewport_width", 390)
	# Convert pixel insets to fraction of viewport.
	var top_frac: float = insets["top"] / viewport_h
	var bottom_frac: float = insets["bottom"] / viewport_h
	var left_frac: float = insets["left"] / viewport_w
	var right_frac: float = insets["right"] / viewport_w
	# Net vertical offset: push view down (positive Y in frustum) if top > bottom.
	var vert_offset: float = (top_frac - bottom_frac) * 0.5 * _camera.size
	# Net horizontal offset.
	var horiz_offset: float = (left_frac - right_frac) * 0.5 * _camera.size
	_camera.frustum_offset = Vector2(horiz_offset, vert_offset)
	# Increase camera size to add breathing room for the larger inset side.
	var inset_frac: float = maxf(top_frac + bottom_frac, left_frac + right_frac)
	_camera.size = 26.0 * (1.0 + inset_frac)


func reset_goal_lock() -> void:
	_goal_locked = false


func lock_goals() -> void:
	_goal_locked = true


func get_puck_spawn_positions() -> Array[Vector3]:
	return [puck_spawn.global_position, puck_spawn_2.global_position]


func get_puck_spawn_position() -> Vector3:
	# Legacy — returns midpoint for AI reference
	return (puck_spawn.global_position + puck_spawn_2.global_position) * 0.5


func get_turret_spawn_position(side: StringName) -> Vector3:
	if side == &"south":
		return south_turret_spawn.global_position
	return north_turret_spawn.global_position


func get_goal_targets() -> Array[Vector3]:
	return [south_goal.global_position, north_goal.global_position]


## Called by CaromMatchController when the sim reports a puck zone event.
## scoring_side is &"north" (AI scores) or &"south" (player scores).
func on_sim_puck_scored(puck: CaromPuck, scoring_side: StringName) -> void:
	if _goal_locked:
		return
	_goal_locked = true
	goal_scored.emit(scoring_side, puck)


## Replace the standard MatchController with the online multiplayer flow.
## Called from _ready() when the arena is launched with carom_online meta.
func _switch_to_online_mode() -> void:
	# Remove the single-player match controller
	var match_ctrl := get_node_or_null("MatchController")
	if match_ctrl:
		match_ctrl.queue_free()

	# Add the online flow controller
	var flow := CaromOnlineFlow.new()
	flow.name = "OnlineFlow"
	add_child(flow)

	# Show the online menu for create/join selection
	var menu: CaromOnlineMenu = preload("res://carom/scenes/carom_online_menu.tscn").instantiate()
	menu.name = "OnlineMenu"
	var overlay_layer := get_node_or_null("HUD/OverlayLayer") as Control
	if overlay_layer:
		overlay_layer.add_child(menu)

	menu.room_create_requested.connect(func() -> void:
		menu.queue_free()
		flow.start_host()
	)
	menu.room_join_requested.connect(func(code: String) -> void:
		menu.queue_free()
		flow.start_join(code)
	)
	menu.local_play_requested.connect(func() -> void:
		menu.queue_free()
		flow.start_local()
	)
	menu.cancelled.connect(func() -> void:
		menu.queue_free()
		SceneTransition.transition_to(Scenes.CAROM_MENU)
	)
