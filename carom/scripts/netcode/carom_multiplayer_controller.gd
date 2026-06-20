class_name CaromMultiplayerController
extends Node

## Orchestrates network ↔ rollback ↔ sim for online Carom matches.
##
## In single-player, CaromMatchController ticks the sim directly.
## In multiplayer, this controller sits between the match controller and
## the sim bridge, routing inputs through:
##   local input → encode → send over network
##   remote input → decode → apply to remote turret → sim advance
##
## Add as a child of CaromArena alongside CaromMatchController.

signal match_connected
signal match_disconnected
signal room_created(code: String)
signal match_started  ## Emitted when frame sync is complete and play begins
signal connection_failed(reason: String)

var _network: Node = null  # CaromNetwork or CaromLocalNetwork
var _rollback: RollbackManager = null
var _bridge: CaromSimBridge = null
var _is_active: bool = false
var _local_frame: int = 0

## Turret references for applying network inputs.
var _local_turret: CaromTurret = null
var _remote_turret: CaromTurret = null
var _remote_input_provider: CaromNetworkInput = null

## Buffer of confirmed remote inputs received ahead of our local frame.
## Key: frame number, Value: packed input int.
var _confirmed_remote_inputs: Dictionary = {}

## Frame synchronization state.
var _sync_complete: bool = false
var _sync_sent: bool = false
var _sync_received: bool = false


func _ready() -> void:
	set_process(false)


## Initialize the multiplayer controller with the sim bridge and turrets.
## local_turret: the turret this player controls (HUMAN input)
## remote_turret: the opponent's turret (driven by network input)
func setup(bridge: CaromSimBridge, local_turret: CaromTurret = null, remote_turret: CaromTurret = null, network_override: Node = null) -> void:
	_bridge = bridge
	_local_turret = local_turret
	_remote_turret = remote_turret

	# Set up network input provider for the remote turret
	if _remote_turret != null:
		_remote_input_provider = CaromNetworkInput.new()
		_remote_turret.input = _remote_input_provider
		_remote_turret.control_mode = CaromTurret.ControlMode.AI  # Disable unhandled_input

	_rollback = RollbackManager.new()
	_rollback.initialize(bridge._sim)

	if network_override != null:
		_network = network_override
	else:
		_network = CaromNetwork.new()
	_network.name = "NetworkLayer"
	add_child(_network)
	_network.connected.connect(_on_connected)
	_network.disconnected.connect(_on_disconnected)
	_network.connection_failed.connect(_on_connection_failed)
	_network.room_created.connect(func(code: String) -> void: room_created.emit(code))
	_network.sync_received.connect(_on_sync_received)
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
## Encodes local input, sends it, applies remote input to opponent turret,
## then advances the sim via the bridge.
func advance_with_input(aim_angle_rad: float, fire: bool, reload: bool) -> void:
	if not _is_active or not _sync_complete:
		return

	# Encode and send local input
	var encoded: PackedByteArray = InputCodec.encode(aim_angle_rad, fire, reload, _local_frame)
	_network.send_input(_local_frame, encoded)

	# Pack for rollback (local side)
	var aim_fp: int = _quantize_aim_to_fp(aim_angle_rad)
	var local_packed: int = InputCodec.pack_input(aim_fp, fire, reload)

	# Check if we already have confirmed remote input for this frame
	var remote_input: int = 0
	var confirmed: bool = false
	if _confirmed_remote_inputs.has(_local_frame):
		remote_input = _confirmed_remote_inputs[_local_frame]
		confirmed = true
		_confirmed_remote_inputs.erase(_local_frame)

	# Apply remote input to the remote turret before advancing the sim
	if _remote_input_provider != null and confirmed:
		var unpacked: Dictionary = InputCodec.unpack_input(remote_input)
		_remote_input_provider.set_tick_input(
			unpacked.aim,
			unpacked.fire,
			unpacked.reload,
			_remote_turret.aim_arc_degrees
		)

	_rollback.advance_frame(local_packed, remote_input, confirmed)

	# Drive the bridge tick (advances sim + updates render state)
	if _bridge != null:
		_bridge.tick_external()

	_local_frame += 1

	# Execute any pending rollback after advancing
	if _rollback.needs_rollback():
		_rollback.execute_rollback()


## Shut down the multiplayer session.
func shutdown() -> void:
	_is_active = false
	_sync_complete = false
	_sync_sent = false
	_sync_received = false
	_confirmed_remote_inputs.clear()
	set_process(false)
	if _network != null:
		_network.close()


func is_active() -> bool:
	return _is_active


func is_host() -> bool:
	return _network != null and _network.is_host()


func is_ready_to_play() -> bool:
	return _is_active and _sync_complete


func get_room_code() -> String:
	return _network.get_room_code() if _network != null else ""


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _on_connected() -> void:
	_is_active = true
	_local_frame = 0
	_confirmed_remote_inputs.clear()
	_sync_complete = false
	_sync_sent = false
	_sync_received = false
	# Re-initialize rollback so _current_frame resets for new match
	if _rollback != null and _bridge != null:
		_rollback.initialize(_bridge._sim)
	# Send sync over the reliable channel — guaranteed delivery
	_network.send_sync()
	_sync_sent = true
	_check_sync_complete()
	match_connected.emit()


func _on_sync_received() -> void:
	_sync_received = true
	_check_sync_complete()


func _check_sync_complete() -> void:
	if _sync_sent and _sync_received and not _sync_complete:
		_sync_complete = true
		match_started.emit()


func _on_disconnected() -> void:
	_is_active = false
	_sync_complete = false
	match_disconnected.emit()


func _on_connection_failed(reason: String) -> void:
	push_warning("Multiplayer connection failed: %s" % reason)
	_is_active = false
	connection_failed.emit(reason)


## Called by CaromNetwork for every received gameplay input packet.
func _on_remote_input(frame_wire: int, packed_input: int) -> void:
	if _rollback == null or not _sync_complete:
		return

	# Reconstruct full frame from 16-bit wire value using nearest-wrap
	var frame: int = _unwrap_frame(frame_wire)

	# Buffer future frames locally — they'll be passed to advance_frame()
	# when the local tick catches up. Do NOT forward to RollbackManager
	# early, as it would overwrite active ring buffer slots.
	if frame >= _local_frame:
		if frame < _local_frame + RollbackManager.ROLLBACK_BUFFER:
			_confirmed_remote_inputs[frame] = packed_input
		return

	# Past/current frames: inform rollback for misprediction detection
	_rollback.receive_remote_input(frame, packed_input)
	if _rollback.needs_rollback():
		_rollback.execute_rollback()


## Reconstruct full frame number from 16-bit wire value.
## Uses _local_frame's high bits and picks the nearest wrap direction.
func _unwrap_frame(wire: int) -> int:
	const WRAP: int = 0x10000  # 65536
	const HALF: int = 0x8000   # 32768
	var local_low: int = _local_frame & 0xFFFF
	var high: int = _local_frame - local_low
	var candidate: int = high + wire
	if wire - local_low > HALF:
		candidate -= WRAP
	elif local_low - wire > HALF:
		candidate += WRAP
	return candidate


func _quantize_aim_to_fp(aim_rad: float) -> int:
	var norm: float = fmod(aim_rad, TAU)
	if norm < 0.0:
		norm += TAU
	var aim_q: int = clampi(roundi(norm / TAU * 1023), 0, 1023)
	return aim_q * InputCodec.FP_TWO_PI / 1023


func _exit_tree() -> void:
	shutdown()
