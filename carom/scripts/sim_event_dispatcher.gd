class_name SimEventDispatcher
extends RefCounted

## Reads zone and collision event lists from SimWorld after each tick and emits
## the appropriate signals so the match controller and effects layer can react
## without coupling to Godot physics signals.
##
## Extracted from CaromSimBridge so that signaling logic is separate from the
## sim-to-scene sync layer.  CaromSimBridge forwards these signals to its own
## identically-named signals to preserve backward compatibility.

## Emitted once per tick when the puck body centre enters a goal zone.
signal puck_zone_entered(body_id: int, zone_id: int)

## Emitted once per tick when a projectile body centre enters a goal zone.
signal projectile_zone_entered(body_id: int, zone_id: int)


## Iterate zone events from the last SimWorld.advance() and emit the matching
## signals.  puck_body_ids is used to distinguish pucks from projectiles;
## projectile_nodes maps body_id → CaromProjectile.
func dispatch_zone_events(
		zone_events: Array,
		puck_body_ids: Array[int],
		projectile_nodes: Dictionary) -> void:
	for ev: Dictionary in zone_events:
		var body_id: int = ev.body_id
		var zone_id: int = ev.zone_id
		if puck_body_ids.has(body_id):
			puck_zone_entered.emit(body_id, zone_id)
		elif projectile_nodes.has(body_id):
			projectile_zone_entered.emit(body_id, zone_id)


## Iterate collision events from the last SimWorld.advance() and forward each
## hit to the affected CaromProjectile render adapter via its impact_occurred signal.
func dispatch_collision_events(
		collision_events: Array,
		puck_body_ids: Array[int],
		projectile_nodes: Dictionary) -> void:
	for ev: Dictionary in collision_events:
		var body_id: int = ev.body_id
		if not projectile_nodes.has(body_id):
			continue
		var projectile := projectile_nodes[body_id] as CaromProjectile
		if not is_instance_valid(projectile):
			continue
		var hit_puck: bool = puck_body_ids.has(ev.other_id)
		var pos := Vector3(FP.to_float(ev.pos_x), 0.0, FP.to_float(ev.pos_y))
		projectile.impact_occurred.emit(pos, hit_puck)
