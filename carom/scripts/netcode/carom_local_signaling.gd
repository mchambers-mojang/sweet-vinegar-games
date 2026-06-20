class_name CaromLocalSignaling
extends Node

## Embedded WebSocket signaling server for local multiplayer testing.
## Speaks the same protocol as the Node.js signaling server so the existing
## CaromNetwork client works unchanged.
##
## Usage:
##   var server := CaromLocalSignaling.new()
##   add_child(server)
##   server.start()  # listens on DEFAULT_PORT

const DEFAULT_PORT: int = 8080
const ROOM_CODE := "LOCAL"

signal started
signal failed(reason: String)

var _server: TCPServer = null
var _peers: Array[WebSocketPeer] = []

## Room state — at most one room with two peers.
var _creator: WebSocketPeer = null
var _creator_sdp: String = ""
var _joiner: WebSocketPeer = null
var _pending_ice_for_joiner: Array[Dictionary] = []
var _pending_ice_for_creator: Array[Dictionary] = []
var _port: int = DEFAULT_PORT


func start(port: int = DEFAULT_PORT) -> void:
	_port = port
	_server = TCPServer.new()
	var err := _server.listen(_port)
	if err != OK:
		failed.emit("Could not listen on port %d (err %d)" % [_port, err])
		return
	print("[LocalSignaling] Listening on port %d" % _port)
	started.emit()


func stop() -> void:
	for peer in _peers:
		peer.close()
	_peers.clear()
	if _server:
		_server.stop()
		_server = null
	_creator = null
	_joiner = null


func _process(_delta: float) -> void:
	if _server == null:
		return

	# Accept new TCP connections and upgrade to WebSocket
	while _server.is_connection_available():
		var tcp := _server.take_connection()
		if tcp == null:
			continue
		var ws := WebSocketPeer.new()
		ws.accept_stream(tcp)
		_peers.append(ws)

	# Poll all peers
	var to_remove: Array[int] = []
	for i in _peers.size():
		var peer := _peers[i]
		peer.poll()
		var state := peer.get_ready_state()

		if state == WebSocketPeer.STATE_CLOSED:
			to_remove.append(i)
			_on_peer_disconnected(peer)
			continue

		if state != WebSocketPeer.STATE_OPEN:
			continue

		while peer.get_available_packet_count() > 0:
			var text := peer.get_packet().get_string_from_utf8()
			var msg: Variant = JSON.parse_string(text)
			if msg is Dictionary:
				_handle_message(peer, msg)

	# Remove closed peers (reverse order to keep indices valid)
	for i in range(to_remove.size() - 1, -1, -1):
		_peers.remove_at(to_remove[i])


func _handle_message(peer: WebSocketPeer, msg: Dictionary) -> void:
	var msg_type: String = msg.get("type", "")
	match msg_type:
		"create":
			if _creator != null:
				_send(peer, { "type": "error", "message": "Room already exists" })
				return
			_creator = peer
			_creator_sdp = msg.get("sdp", "")
			_send(peer, { "type": "room_created", "code": ROOM_CODE })
			# Flush any ICE candidates buffered before create was processed
			for ice_msg in _pending_ice_for_joiner:
				_send(_joiner, ice_msg) if _joiner != null else null
			_pending_ice_for_joiner.clear()

		"join":
			if _creator == null:
				_send(peer, { "type": "error", "message": "Room not found" })
				return
			if _joiner != null:
				_send(peer, { "type": "error", "message": "Room full" })
				return
			_joiner = peer
			# Send creator's offer to joiner
			_send(peer, { "type": "room_joined", "sdp": _creator_sdp })
			# Flush buffered ICE for joiner
			for ice_msg in _pending_ice_for_joiner:
				_send(peer, ice_msg)
			_pending_ice_for_joiner.clear()

		"answer":
			if peer == _joiner and _creator != null:
				_send(_creator, {
					"type": "peer_joined",
					"sdp": msg.get("sdp", "")
				})
				# Flush buffered ICE for creator
				for ice_msg in _pending_ice_for_creator:
					_send(_creator, ice_msg)
				_pending_ice_for_creator.clear()

		"ice":
			if peer == _creator:
				if _joiner != null:
					_send(_joiner, msg)
				else:
					_pending_ice_for_joiner.append(msg)
			elif peer == _joiner:
				if _creator != null:
					_send(_creator, msg)
				else:
					_pending_ice_for_creator.append(msg)


func _on_peer_disconnected(peer: WebSocketPeer) -> void:
	if peer == _creator:
		_creator = null
		_creator_sdp = ""
	elif peer == _joiner:
		_joiner = null


func _send(peer: WebSocketPeer, msg: Dictionary) -> void:
	if peer == null:
		return
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(JSON.stringify(msg))
