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
signal match_started  ## Emitted when frame sync is complete and play begins

var _network: CaromNetwork = null
var _rollback: RollbackManager = null
var _bridge: CaromSimBridge = null
var _is_active: bool = false
var _local_frame: int = 0

## Buffer of confirmed remote inputs received ahead of our local frame.
## Key: frame number, Value: packed input int.
var _confirmed_remote_inputs: Dictionary = {}

## Frame synchronization state.
var _sync_complete: bool = false
var _sync_sent: bool = false
var _sync_received: bool = false

## Magic bytes to distinguish sync packets from input packets.
## Sync packet: [0xFF, 0xFF, 0xFF, 0xFF] (impossible as input since aim uses top 10 bits)
const SYNC_MAGIC: int = 0xFFFFFFFF


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
	_network.set_input_callback(_on_remote_packet)


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
	if not _is_active or not _sync_complete:
		return

	# Encode and send local input
	var encoded: PackedByteArray = InputCodec.encode(aim_angle_rad, fire, reload, _local_frame)
	_network.send_input(_local_frame, encoded)

	# Pack for rollback (local side)
	var aim_fp: int = _quantize_aim_to_fp(aim_angle_rad)
	var local_packed: int = InputCodec.pack_input(aim_fp, fire, reload)

	# Check if we already have confirmed remote input for this frame
	# (received ahead of time from a faster remote peer)
	var remote_input: int = 0
	var confirmed: bool = false
	if _confirmed_remote_inputs.has(_local_frame):
		remote_input = _confirmed_remote_inputs[_local_frame]
		confirmed = true
		_confirmed_remote_inputs.erase(_local_frame)

	_rollback.advance_frame(local_packed, remote_input, confirmed)
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
	# Send sync packet to signal readiness
	_send_sync()
	match_connected.emit()


func _send_sync() -> void:
	var buf := PackedByteArray()
	buf.resize(4)
	buf.encode_u32(0, SYNC_MAGIC)
	_network.send_input(0, buf)
	_sync_sent = true
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


## Called by CaromNetwork for every received packet (both sync and input).
func _on_remote_packet(frame: int, packed_input: int) -> void:
	# Check for sync magic: SYNC_MAGIC decodes to frame=65535, and the
	# packed input matches the sync sentinel value.
	if not _sync_complete and frame == 65535 and packed_input == _unpack_sync_sentinel():
		_sync_received = true
		_check_sync_complete()
		return

	if _rollback == null or not _sync_complete:
		return

	# Store as confirmed remote input
	if frame >= _local_frame:
		# Arrived ahead — buffer it for when we reach that frame
		_confirmed_remote_inputs[frame] = packed_input
	# Always inform rollback (handles past frames + misprediction detection)
	_rollback.receive_remote_input(frame, packed_input)
	if _rollback.needs_rollback():
		_rollback.execute_rollback()


## The sync magic decoded through InputCodec produces a specific packed value.
## Pre-compute it so we can identify sync packets after decoding.
func _unpack_sync_sentinel() -> int:
	# SYNC_MAGIC = 0xFFFFFFFF as raw bytes → InputCodec.decode → pack_input
	# aim_q = (0xFFFFFFFF >> 22) & 0x3FF = 1023
	# fire = (0xFFFFFFFF >> 21) & 1 = 1
	# reload = (0xFFFFFFFF >> 20) & 1 = 1
	# frame = 0xFFFFFFFF & 0xFFFF = 65535
	# aim_fp = 1023 * 411774 / 1023 = 411774
	# pack_input(411774, true, true) = (411774 & 0xFFFF) << 16 | 2 | 1
	# = (0x489E) << 16 | 3 = 0x489E0003
	var aim_fp: int = 1023 * InputCodec.FP_TWO_PI / 1023  # = FP_TWO_PI = 411774
	return InputCodec.pack_input(aim_fp, true, true)


func _quantize_aim_to_fp(aim_rad: float) -> int:
	var norm: float = fmod(aim_rad, TAU)
	if norm < 0.0:
		norm += TAU
	var aim_q: int = clampi(roundi(norm / TAU * 1023), 0, 1023)
	return aim_q * InputCodec.FP_TWO_PI / 1023


func _exit_tree() -> void:
	shutdown()
