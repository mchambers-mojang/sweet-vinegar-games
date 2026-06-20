class_name CaromLocalNetwork
extends Node

## Direct TCP networking for local multiplayer (same machine or LAN).
## Drop-in replacement for CaromNetwork that skips WebRTC/WebSocket entirely.
## Host listens on a TCP port; joiner connects directly.
## Inputs are exchanged as raw binary packets over the TCP stream.

signal room_created(code: String)
signal connected
signal disconnected
signal connection_failed(reason: String)
signal sync_received

const DEFAULT_PORT: int = 8081
const ROOM_CODE := "LOCAL"

## Packet type markers
const PKT_INPUT: int = 0x01
const PKT_SYNC: int = 0x02

enum State { IDLE, LISTENING, CONNECTING, CONNECTED, DISCONNECTED }

var _state: State = State.IDLE
var _is_host_flag: bool = false
var _server: TCPServer = null
var _peer: StreamPeerTCP = null
var _input_callback: Callable = Callable()
var _port: int = DEFAULT_PORT


func _ready() -> void:
	set_process(false)


## Unused — kept for API compatibility with CaromNetwork.
func set_signaling_url(_url: String) -> void:
	pass


func set_input_callback(cb: Callable) -> void:
	_input_callback = cb


## Host: start listening for a joiner connection.
func create_room() -> void:
	if _state != State.IDLE:
		connection_failed.emit("Already active")
		return
	_is_host_flag = true
	_server = TCPServer.new()
	var err := _server.listen(_port)
	if err != OK:
		connection_failed.emit("Could not listen on port %d" % _port)
		return
	_state = State.LISTENING
	set_process(true)
	print("[LocalNetwork] Host listening on port %d" % _port)
	room_created.emit(ROOM_CODE)


## Joiner: connect to the host.
func join_room(_code: String) -> void:
	if _state != State.IDLE:
		connection_failed.emit("Already active")
		return
	_is_host_flag = false
	_peer = StreamPeerTCP.new()
	var err := _peer.connect_to_host("127.0.0.1", _port)
	if err != OK:
		connection_failed.emit("Could not connect to host")
		return
	_state = State.CONNECTING
	set_process(true)
	print("[LocalNetwork] Joiner connecting to 127.0.0.1:%d" % _port)


func send_input(frame: int, encoded: PackedByteArray) -> void:
	if _peer == null or _state != State.CONNECTED:
		return
	# Header: [type:1][frame:2][length:2][data:N]
	var header := PackedByteArray()
	header.resize(5)
	header[0] = PKT_INPUT
	header[1] = frame & 0xFF
	header[2] = (frame >> 8) & 0xFF
	header[3] = encoded.size() & 0xFF
	header[4] = (encoded.size() >> 8) & 0xFF
	_peer.put_data(header)
	_peer.put_data(encoded)


func send_sync() -> void:
	if _peer == null or _state != State.CONNECTED:
		return
	var pkt := PackedByteArray()
	pkt.resize(1)
	pkt[0] = PKT_SYNC
	_peer.put_data(pkt)


func is_host() -> bool:
	return _is_host_flag


func get_room_code() -> String:
	return ROOM_CODE if _state != State.IDLE else ""


func close() -> void:
	_cleanup()


func _process(_delta: float) -> void:
	match _state:
		State.LISTENING:
			_poll_server()
		State.CONNECTING:
			_poll_connecting()
		State.CONNECTED:
			_poll_data()


func _poll_server() -> void:
	if _server == null:
		return
	if _server.is_connection_available():
		_peer = _server.take_connection()
		if _peer != null:
			_server.stop()
			_server = null
			_state = State.CONNECTED
			print("[LocalNetwork] Peer connected!")
			connected.emit()


func _poll_connecting() -> void:
	if _peer == null:
		return
	_peer.poll()
	var status := _peer.get_status()
	match status:
		StreamPeerTCP.STATUS_CONNECTED:
			_state = State.CONNECTED
			print("[LocalNetwork] Connected to host!")
			connected.emit()
		StreamPeerTCP.STATUS_ERROR:
			connection_failed.emit("TCP connection failed")
			_cleanup()
		StreamPeerTCP.STATUS_NONE:
			connection_failed.emit("TCP connection lost")
			_cleanup()


func _poll_data() -> void:
	if _peer == null:
		return
	_peer.poll()

	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_state = State.DISCONNECTED
		disconnected.emit()
		return

	while _peer.get_available_bytes() > 0:
		var type_byte := _peer.get_u8()
		match type_byte:
			PKT_INPUT:
				if _peer.get_available_bytes() < 4:
					break
				var frame_lo := _peer.get_u8()
				var frame_hi := _peer.get_u8()
				var frame := frame_lo | (frame_hi << 8)
				var len_lo := _peer.get_u8()
				var len_hi := _peer.get_u8()
				var data_len := len_lo | (len_hi << 8)
				if _peer.get_available_bytes() < data_len:
					break
				var data := _peer.get_data(data_len)
				if data[0] == OK and _input_callback.is_valid():
					_input_callback.call(frame, data[1])
			PKT_SYNC:
				sync_received.emit()
			_:
				# Unknown packet type — skip
				break


func _cleanup() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null
	if _server != null:
		_server.stop()
		_server = null
	_state = State.IDLE
	set_process(false)


func _exit_tree() -> void:
	_cleanup()
