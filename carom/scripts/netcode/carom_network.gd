class_name CaromNetwork
extends Node

## WebRTC networking layer for Carom multiplayer.
## Connects to the signaling server, exchanges SDP/ICE, and establishes
## a peer-to-peer DataChannel for unreliable input transport.
## Also maintains a reliable ordered channel for sync/control messages.

signal room_created(code: String)
signal connected
signal disconnected
signal connection_failed(reason: String)
signal sync_received  ## Emitted when remote peer's sync packet arrives
signal queued  ## Emitted when server confirms we're in the matchmaking queue
signal rematch_requested  ## Remote peer wants a rematch
signal rematch_accepted  ## Remote peer agreed to rematch

const DEFAULT_SIGNALING_URL: String = "wss://carom-signaling-dae9dadjh0h9aqgb.westus3-01.azurewebsites.net"
const INPUT_CHANNEL_ID: int = 0
const SYNC_CHANNEL_ID: int = 1

enum State { IDLE, CREATING, JOINING, SIGNALING, CONNECTED, DISCONNECTED }

var _state: State = State.IDLE
var _ws: WebSocketPeer = null
var _rtc: WebRTCPeerConnection = null
var _input_channel: WebRTCDataChannel = null
var _sync_channel: WebRTCDataChannel = null
var _room_code: String = ""
var _is_host: bool = false
var _input_callback: Callable = Callable()
var _signaling_url: String = DEFAULT_SIGNALING_URL

# ICE candidates queued before remote description is set
var _ice_queue: Array[Dictionary] = []
# ICE candidates queued before room code is known (host) or before WS open
var _ice_send_queue: Array[Dictionary] = []
var _remote_description_set: bool = false
# Buffer local SDP until signaling WebSocket is open
var _pending_local_sdp: Dictionary = {}  # { type: String, sdp: String }
var _ws_open_handled: bool = false


func _ready() -> void:
	set_process(false)


## Configure the signaling server URL (call before create/join).
func set_signaling_url(url: String) -> void:
	_signaling_url = url


## Create a room as host. Emits room_created(code) on success.
func create_room() -> void:
	if _state != State.IDLE:
		connection_failed.emit("Already active")
		return
	_is_host = true
	_state = State.CREATING
	_setup_rtc()
	_connect_signaling()
	set_process(true)
	# Don't create offer yet — wait until WS is open so SDP isn't lost


## Join an existing room by code. Emits connected() on success.
func join_room(code: String) -> void:
	if _state != State.IDLE:
		connection_failed.emit("Already active")
		return
	_is_host = false
	_room_code = code.to_upper()
	_state = State.JOINING
	_setup_rtc()
	_connect_signaling()
	set_process(true)


## Enter the matchmaking queue. Server will pair with another queued player.
## Emits connected() when matched and WebRTC is established.
func matchmake() -> void:
	if _state != State.IDLE:
		connection_failed.emit("Already active")
		return
	_state = State.CREATING  # Re-use CREATING state until matched
	_is_host = false  # Will be assigned by server
	_connect_signaling()
	set_process(true)


## Send encoded input bytes over the unreliable DataChannel.
func send_input(frame: int, encoded: PackedByteArray) -> void:
	if _input_channel == null or _input_channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return
	_input_channel.put_packet(encoded)


## Send a sync packet over the reliable channel.
func send_sync() -> void:
	if _sync_channel == null or _sync_channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return
	var buf := PackedByteArray()
	buf.resize(1)
	buf[0] = 0x01  # SYNC byte
	_sync_channel.put_packet(buf)


## Request a rematch from the remote peer.
func send_rematch_request() -> void:
	if _sync_channel == null or _sync_channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return
	var buf := PackedByteArray()
	buf.resize(1)
	buf[0] = 0x02  # REMATCH_REQUEST
	_sync_channel.put_packet(buf)


## Accept the remote peer's rematch request.
func send_rematch_accept() -> void:
	if _sync_channel == null or _sync_channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return
	var buf := PackedByteArray()
	buf.resize(1)
	buf[0] = 0x03  # REMATCH_ACCEPT
	_sync_channel.put_packet(buf)


## Register a callback for received remote inputs: fn(frame: int, input_packed: int)
func set_input_callback(callable: Callable) -> void:
	_input_callback = callable


## Close everything and return to idle.
func close() -> void:
	_cleanup()
	_state = State.IDLE


func is_connected_to_peer() -> bool:
	return _state == State.CONNECTED


func is_host() -> bool:
	return _is_host


func get_room_code() -> String:
	return _room_code


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_poll_websocket()
	_poll_rtc()


func _setup_rtc() -> void:
	_rtc = WebRTCPeerConnection.new()
	var config: Dictionary = {
		"iceServers": [{ "urls": ["stun:stun.l.google.com:19302"] }]
	}
	_rtc.initialize(config)
	_rtc.session_description_created.connect(_on_session_description)
	_rtc.ice_candidate_created.connect(_on_ice_candidate)

	# Input channel: unreliable, unordered, negotiated on both sides
	var input_config: Dictionary = {
		"negotiated": true,
		"id": INPUT_CHANNEL_ID,
		"ordered": false,
		"maxRetransmits": 0,
	}
	_input_channel = _rtc.create_data_channel("inputs", input_config)

	# Sync channel: reliable, ordered, negotiated — for handshake/control
	var sync_config: Dictionary = {
		"negotiated": true,
		"id": SYNC_CHANNEL_ID,
		"ordered": true,
	}
	_sync_channel = _rtc.create_data_channel("sync", sync_config)


func _connect_signaling() -> void:
	_ws = WebSocketPeer.new()
	_ws_open_handled = false
	var err := _ws.connect_to_url(_signaling_url)
	if err != OK:
		_state = State.IDLE
		connection_failed.emit("WebSocket connect failed: %d" % err)
		set_process(false)


func _poll_websocket() -> void:
	if _ws == null:
		return
	_ws.poll()
	var ws_state := _ws.get_ready_state()

	if ws_state == WebSocketPeer.STATE_CLOSED:
		if _state != State.CONNECTED and _state != State.IDLE:
			connection_failed.emit("Signaling connection closed")
			_cleanup()
		_ws = null
		return

	if ws_state != WebSocketPeer.STATE_OPEN:
		return

	# Handle the moment WS becomes open (once)
	if not _ws_open_handled:
		_ws_open_handled = true
		_on_ws_open()

	# Read incoming messages
	while _ws != null and _ws.get_available_packet_count() > 0:
		var text := _ws.get_packet().get_string_from_utf8()
		var json := JSON.new()
		if json.parse(text) != OK:
			continue
		var msg: Dictionary = json.data
		_handle_signaling_message(msg)


func _on_ws_open() -> void:
	if _state == State.CREATING:
		if _room_code == "" and not _is_host:
			# Matchmaking mode — send matchmake request
			_ws_send({ "type": "matchmake" })
		else:
			# Manual room creation — create the offer
			_rtc.create_offer()
	elif _state == State.JOINING:
		# Send join without SDP — server replies with room_joined + host's offer
		_ws_send({ "type": "join", "code": _room_code })
		_state = State.SIGNALING

	# Flush any buffered local SDP (shouldn't happen now but defensive)
	if not _pending_local_sdp.is_empty():
		_send_local_sdp(_pending_local_sdp.type, _pending_local_sdp.sdp)
		_pending_local_sdp = {}

	# Flush any buffered ICE candidates
	for ice_msg in _ice_send_queue:
		_ws_send(ice_msg)
	_ice_send_queue.clear()


func _handle_signaling_message(msg: Dictionary) -> void:
	var msg_type: String = msg.get("type", "")

	match msg_type:
		"room_created":
			_room_code = msg.get("code", "")
			room_created.emit(_room_code)
			# Flush any ICE candidates that were waiting for room code
			for ice_msg in _ice_send_queue:
				ice_msg["code"] = _room_code
				_ws_send(ice_msg)
			_ice_send_queue.clear()

		"queued":
			# Acknowledged in matchmaking queue — wait for match
			queued.emit()

		"matched":
			# Server paired us with an opponent
			_room_code = msg.get("code", "")
			var role: String = msg.get("role", "")
			_is_host = (role == "host")
			print("[CaromNetwork] Matched! role=%s code=%s" % [role, _room_code])
			_setup_rtc()
			if _is_host:
				# Host creates the offer and sends it via "offer" message
				_state = State.SIGNALING
				print("[CaromNetwork] Creating RTC offer...")
				_rtc.create_offer()
			else:
				# Joiner waits for host's offer (arrives as room_joined)
				_state = State.SIGNALING
				print("[CaromNetwork] Waiting for host offer...")

		"peer_joined":
			# Host receives joiner's answer SDP
			print("[CaromNetwork] Received peer answer SDP")
			var sdp: String = msg.get("sdp", "")
			if sdp != "":
				_rtc.set_remote_description("answer", sdp)
				_remote_description_set = true
				_flush_ice_queue()

		"room_joined":
			# Joiner receives host's offer SDP — set_remote_description
			# will trigger session_description_created with type "answer"
			print("[CaromNetwork] Received host offer SDP")
			var sdp: String = msg.get("sdp", "")
			if sdp != "":
				_rtc.set_remote_description("offer", sdp)
				_remote_description_set = true
				_flush_ice_queue()

		"ice":
			var candidate: Dictionary = msg.get("candidate", {})
			if candidate.size() > 0:
				var media: String = candidate.get("sdpMid", "")
				var index: int = candidate.get("sdpMLineIndex", 0)
				var cand_str: String = candidate.get("candidate", "")
				if _remote_description_set:
					_rtc.add_ice_candidate(media, index, cand_str)
				else:
					_ice_queue.append({ "media": media, "index": index, "candidate": cand_str })

		"error":
			connection_failed.emit(msg.get("message", "Unknown signaling error"))
			_cleanup()


func _flush_ice_queue() -> void:
	for entry in _ice_queue:
		_rtc.add_ice_candidate(entry.media, entry.index, entry.candidate)
	_ice_queue.clear()


func _on_session_description(type: String, sdp: String) -> void:
	print("[CaromNetwork] Session description created: type=%s len=%d" % [type, sdp.length()])
	_rtc.set_local_description(type, sdp)

	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		# Buffer until WS is ready
		_pending_local_sdp = { "type": type, "sdp": sdp }
		return

	_send_local_sdp(type, sdp)


func _send_local_sdp(type: String, sdp: String) -> void:
	if _is_host and type == "offer":
		if _room_code != "":
			# Matchmade — use "offer" message (room already exists on server)
			_ws_send({ "type": "offer", "code": _room_code, "sdp": sdp })
		else:
			# Manual room creation — use "create" message
			_ws_send({ "type": "create", "sdp": sdp })
	elif not _is_host and type == "answer":
		_ws_send({ "type": "answer", "code": _room_code, "sdp": sdp })


func _on_ice_candidate(media: String, index: int, candidate: String) -> void:
	var ice_msg: Dictionary = {
		"type": "ice",
		"code": _room_code,
		"candidate": { "sdpMid": media, "sdpMLineIndex": index, "candidate": candidate }
	}

	# Buffer if WS not open or room code not yet known (host before room_created)
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN or _room_code == "":
		_ice_send_queue.append(ice_msg)
		return

	_ws_send(ice_msg)


func _poll_rtc() -> void:
	if _rtc == null:
		return
	_rtc.poll()

	# Check if both channels are open before emitting connected
	var input_open: bool = _input_channel != null and _input_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN
	var sync_open: bool = _sync_channel != null and _sync_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN

	if input_open and sync_open:
		if _state != State.CONNECTED:
			print("[CaromNetwork] WebRTC connected! Both channels open.")
			_state = State.CONNECTED
			connected.emit()
			# Signaling no longer needed
			if _ws != null:
				_ws.close()
				_ws = null

	if _input_channel != null:
		match _input_channel.get_ready_state():
			WebRTCDataChannel.STATE_OPEN:
				# Read incoming input packets
				while _input_channel.get_available_packet_count() > 0:
					var pkt := _input_channel.get_packet()
					_handle_input_packet(pkt)

			WebRTCDataChannel.STATE_CLOSED:
				if _state == State.CONNECTED:
					_state = State.DISCONNECTED
					disconnected.emit()

	# Check sync DataChannel for control messages
	if sync_open:
		while _sync_channel.get_available_packet_count() > 0:
			var pkt := _sync_channel.get_packet()
			if pkt.size() >= 1:
				match pkt[0]:
					0x01: sync_received.emit()
					0x02: rematch_requested.emit()
					0x03: rematch_accepted.emit()


func _handle_input_packet(data: PackedByteArray) -> void:
	if data.size() < 4 or not _input_callback.is_valid():
		return
	var decoded: Dictionary = InputCodec.decode(data)
	if decoded.is_empty():
		return
	var packed_input: int = InputCodec.pack_input(decoded.aim, decoded.fire, decoded.reload)
	_input_callback.call(decoded.frame, packed_input)


func _ws_send(msg: Dictionary) -> void:
	if _ws == null:
		return
	_ws.send_text(JSON.stringify(msg))


func _cleanup() -> void:
	if _input_channel != null:
		_input_channel.close()
		_input_channel = null
	if _sync_channel != null:
		_sync_channel.close()
		_sync_channel = null
	if _rtc != null:
		_rtc.close()
		_rtc = null
	if _ws != null:
		_ws.close()
		_ws = null
	_room_code = ""
	_remote_description_set = false
	_ws_open_handled = false
	_ice_queue.clear()
	_ice_send_queue.clear()
	_pending_local_sdp = {}
	_state = State.IDLE
	set_process(false)


func _exit_tree() -> void:
	_cleanup()
