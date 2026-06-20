class_name CaromMultiplayerController
extends Node

## Orchestrates network ↔ rollback ↔ sim for online Carom matches.
##
## In single-player, CaromMatchController ticks the sim directly.
## In multiplayer, this controller sits between the match controller and
## the sim bridge, routing inputs through:
##   local input → encode → send over network
##   remote input → decode → RollbackManager → sim advance
##
## Add as a child of CaromArena alongside CaromMatchController.

signal match_connected
signal match_disconnected
signal room_created(code: String)

var _network: CaromNetwork = null
var _rollback: RollbackManager = null
var _bridge: CaromSimBridge = null
var _is_active: bool = false
var _local_frame: int = 0


func _ready() -> void:
	set_process(false)


## Initialize the multiplayer controller with the sim bridge's SimWorld.
func setup(bridge: CaromSimBridge) -> void:
	_bridge = bridge
	_rollback = RollbackManager.new()
	_rollback.initialize(bridge._sim)
	_network = CaromNetwork.new()
	_network.name = "CaromNetwork"
	add_child(_network)
	_network.connected.connect(_on_connected)
	_network.disconnected.connect(_on_disconnected)
	_network.connection_failed.connect(_on_connection_failed)
	_network.room_created.connect(func(code: String) -> void: room_created.emit(code))
	_network.set_input_callback(_on_remote_input)


## Host a new online match.
func host_match(signaling_url: String = "") -> void:
	if signaling_url != "":
		_network.set_signaling_url(signaling_url)
	_network.create_room()


## Join an existing online match by room code.
func join_match(code: String, signaling_url: String = "") -> void:
	if signaling_url != "":
		_network.set_signaling_url(signaling_url)
	_network.join_room(code)


## Call each sim tick instead of _sim.advance() in multiplayer mode.
## Encodes local input, sends it, and feeds both inputs to rollback.
func advance_with_input(aim_angle_rad: float, fire: bool, reload: bool) -> void:
	if not _is_active:
		return

	# Encode and send local input
	var encoded: PackedByteArray = InputCodec.encode(aim_angle_rad, fire, reload, _local_frame)
	_network.send_input(_local_frame, encoded)

	# Pack for rollback (local side)
	var aim_fp: int = _quantize_aim_to_fp(aim_angle_rad)
	var local_packed: int = InputCodec.pack_input(aim_fp, fire, reload)

	# Check if we have confirmed remote input for this frame
	var remote_input: int = 0
	var confirmed: bool = false
	# RollbackManager handles prediction internally via advance_frame
	_rollback.advance_frame(local_packed, remote_input, confirmed)
	_local_frame += 1


## Shut down the multiplayer session.
func shutdown() -> void:
	_is_active = false
	set_process(false)
	if _network != null:
		_network.close()


func is_active() -> bool:
	return _is_active


func is_host() -> bool:
	return _network != null and _network.is_host()


func get_room_code() -> String:
	return _network.get_room_code() if _network != null else ""


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _on_connected() -> void:
	_is_active = true
	_local_frame = 0
	match_connected.emit()


func _on_disconnected() -> void:
	_is_active = false
	match_disconnected.emit()


func _on_connection_failed(reason: String) -> void:
	push_warning("Multiplayer connection failed: %s" % reason)
	_is_active = false


func _on_remote_input(frame: int, packed_input: int) -> void:
	if _rollback != null:
		_rollback.receive_remote_input(frame, packed_input)
		# Check if rollback is needed after receiving confirmed input
		if _rollback.needs_rollback():
			_rollback.execute_rollback()


func _quantize_aim_to_fp(aim_rad: float) -> int:
	var norm: float = fmod(aim_rad, TAU)
	if norm < 0.0:
		norm += TAU
	var aim_q: int = clampi(roundi(norm / TAU * 1023), 0, 1023)
	return aim_q * InputCodec.FP_TWO_PI / 1023


func _exit_tree() -> void:
	shutdown()
