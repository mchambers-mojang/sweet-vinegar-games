class_name CaromNetwork
extends Node

## WebRTC networking layer for Carom multiplayer.
## Connects to the signaling server, exchanges SDP/ICE, and establishes
## a peer-to-peer DataChannel for unreliable input transport.

signal room_created(code: String)
signal connected
signal disconnected
signal connection_failed(reason: String)

const DEFAULT_SIGNALING_URL: String = "ws://127.0.0.1:8080"
const CHANNEL_ID: int = 0

enum State { IDLE, CREATING, JOINING, SIGNALING, CONNECTED, DISCONNECTED }

var _state: State = State.IDLE
var _ws: WebSocketPeer = null
var _rtc: WebRTCPeerConnection = null
var _channel: WebRTCDataChannel = null
var _room_code: String = ""
var _is_host: bool = false
var _input_callback: Callable = Callable()
var _signaling_url: String = DEFAULT_SIGNALING_URL

# ICE candidates queued before remote description is set
var _ice_queue: Array[Dictionary] = []
var _remote_description_set: bool = false


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
	# Create offer — the callback will send it to signaling
	_rtc.create_offer()
	_connect_signaling()
	set_process(true)


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


## Send encoded input bytes over the DataChannel.
func send_input(frame: int, encoded: PackedByteArray) -> void:
	if _channel == null or _channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return
	_channel.put_packet(encoded)


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

	# Create DataChannel: unreliable, unordered, negotiated on both sides
	var ch_config: Dictionary = {
		"negotiated": true,
		"id": CHANNEL_ID,
		"ordered": false,
		"maxRetransmits": 0,
	}
	_channel = _rtc.create_data_channel("inputs", ch_config)


func _connect_signaling() -> void:
	_ws = WebSocketPeer.new()
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

	# Handle newly-open connection: send create/join
	if _state == State.CREATING and _room_code == "":
		# Waiting for offer to be created — it'll be sent in _on_session_description
		pass
	elif _state == State.JOINING and _room_code != "":
		# We need the host's offer first, so just send join request
		_ws_send({ "type": "join", "code": _room_code, "sdp": "" })
		_state = State.SIGNALING

	# Read incoming messages
	while _ws.get_available_packet_count() > 0:
		var text := _ws.get_packet().get_string_from_utf8()
		var json := JSON.new()
		if json.parse(text) != OK:
			continue
		var msg: Dictionary = json.data
		_handle_signaling_message(msg)


func _handle_signaling_message(msg: Dictionary) -> void:
	var msg_type: String = msg.get("type", "")

	match msg_type:
		"room_created":
			_room_code = msg.get("code", "")
			room_created.emit(_room_code)

		"peer_joined":
			# Host receives joiner's answer SDP
			var sdp: String = msg.get("sdp", "")
			if sdp != "":
				_rtc.set_remote_description("answer", sdp)
				_remote_description_set = true
				_flush_ice_queue()

		"room_joined":
			# Joiner receives host's offer SDP
			var sdp: String = msg.get("sdp", "")
			if sdp != "":
				_rtc.set_remote_description("offer", sdp)
				_remote_description_set = true
				_flush_ice_queue()
				# Create answer
				_rtc.create_offer()

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
	_rtc.set_local_description(type, sdp)

	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	if _is_host and type == "offer":
		_ws_send({ "type": "create", "sdp": sdp })
	elif not _is_host and type == "answer":
		_ws_send({ "type": "join", "code": _room_code, "sdp": sdp })


func _on_ice_candidate(media: String, index: int, candidate: String) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ws_send({
		"type": "ice",
		"code": _room_code,
		"candidate": { "sdpMid": media, "sdpMLineIndex": index, "candidate": candidate }
	})


func _poll_rtc() -> void:
	if _rtc == null:
		return
	_rtc.poll()

	# Check DataChannel state
	if _channel != null:
		match _channel.get_ready_state():
			WebRTCDataChannel.STATE_OPEN:
				if _state != State.CONNECTED:
					_state = State.CONNECTED
					connected.emit()
					# Signaling no longer needed
					if _ws != null:
						_ws.close()
						_ws = null
				# Read incoming input packets
				while _channel.get_available_packet_count() > 0:
					var pkt := _channel.get_packet()
					_handle_input_packet(pkt)

			WebRTCDataChannel.STATE_CLOSED:
				if _state == State.CONNECTED:
					_state = State.DISCONNECTED
					disconnected.emit()


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
	if _channel != null:
		_channel.close()
		_channel = null
	if _rtc != null:
		_rtc.close()
		_rtc = null
	if _ws != null:
		_ws.close()
		_ws = null
	_room_code = ""
	_remote_description_set = false
	_ice_queue.clear()
	set_process(false)


func _exit_tree() -> void:
	_cleanup()
