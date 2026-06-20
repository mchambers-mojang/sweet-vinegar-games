class_name CaromOnlineFlow
extends Node

## Manages the full online multiplayer flow:
##   Menu → Create/Join → Connecting → Match → Results → Menu
##
## Add this as a child of the CaromArena scene when launching online mode.
## It creates the CaromOnlineMatchController and coordinates UI overlays.

const SIGNALING_URL_DEFAULT := "ws://localhost:8080"
const CONNECTION_OVERLAY_SCENE := preload("res://carom/scenes/carom_connection_overlay.tscn")
const CONNECTED_DISPLAY_DURATION: float = 1.2
const OVERLAY_LAYER_PATH := "HUD/OverlayLayer"

signal flow_completed  ## Emitted when the player returns to menu

var _match_ctrl: CaromOnlineMatchController = null
var _signaling_url: String = SIGNALING_URL_DEFAULT
var _overlay: CaromConnectionOverlay = null
var _connected_started_at_usec: int = -1
var _pending_hide_request_id: int = 0
var _local_server: CaromLocalSignaling = null


## Start hosting a new online match. Call after this node is in the tree
## under a CaromArena.
func start_host(signaling_url: String = "") -> void:
	if signaling_url != "":
		_signaling_url = signaling_url
	_ensure_overlay()
	_ensure_match_controller()
	_match_ctrl.host(_signaling_url)


## Join an existing match by room code.
func start_join(code: String, signaling_url: String = "") -> void:
	if signaling_url != "":
		_signaling_url = signaling_url
	_ensure_overlay()
	_ensure_match_controller()
	_match_ctrl.join(code, _signaling_url)


## Local play: try to join an existing local server; if none is running, become the host.
func start_local() -> void:
	_signaling_url = "ws://127.0.0.1:%d" % CaromLocalSignaling.DEFAULT_PORT
	_ensure_overlay()

	# Probe whether a local signaling server is already running
	var probe := WebSocketPeer.new()
	var err := probe.connect_to_url(_signaling_url)
	if err != OK:
		# Can't even start connecting — become host
		_start_local_as_host()
		return

	# Poll briefly to see if we can connect
	var attempts := 0
	while attempts < 15:
		probe.poll()
		var state := probe.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			probe.close()
			# Server is already running — join as client
			_ensure_match_controller()
			_match_ctrl.join(CaromLocalSignaling.ROOM_CODE, _signaling_url)
			return
		if state == WebSocketPeer.STATE_CLOSED:
			break
		attempts += 1
		await get_tree().create_timer(0.05).timeout

	probe.close()
	# No server found — become host
	_start_local_as_host()


func _start_local_as_host() -> void:
	_local_server = CaromLocalSignaling.new()
	_local_server.name = "LocalSignaling"
	add_child(_local_server)
	_local_server.start()
	# Small delay to let the server socket bind
	await get_tree().create_timer(0.1).timeout
	_ensure_match_controller()
	_match_ctrl.host(_signaling_url)


## Returns the room code (valid after hosting and receiving room_created).
func get_room_code() -> String:
	if _match_ctrl:
		return _match_ctrl.get_room_code()
	return ""


func _ensure_match_controller() -> void:
	if _match_ctrl != null:
		return
	_match_ctrl = CaromOnlineMatchController.new()
	_match_ctrl.name = "OnlineMatchController"
	get_parent().add_child(_match_ctrl)
	_match_ctrl.connection_status_changed.connect(_on_connection_status)
	_match_ctrl.match_ended.connect(_on_match_ended)


func _ensure_overlay() -> void:
	if is_instance_valid(_overlay):
		return
	var overlay_layer := get_parent().get_node_or_null(OVERLAY_LAYER_PATH) as Control
	if overlay_layer == null:
		push_warning("CaromOnlineFlow could not find overlay layer at %s" % OVERLAY_LAYER_PATH)
		return
	_overlay = CONNECTION_OVERLAY_SCENE.instantiate() as CaromConnectionOverlay
	_overlay.name = "ConnectionOverlay"
	_overlay.back_requested.connect(_on_back_requested)
	overlay_layer.add_child(_overlay)


func _on_connection_status(status: String, message: String) -> void:
	_ensure_overlay()
	_pending_hide_request_id += 1
	if _overlay:
		match status:
			"connected":
				_connected_started_at_usec = Time.get_ticks_usec()
				_overlay.show_status(status, message)
			"playing":
				_hide_overlay_after_connected_flash(_pending_hide_request_id)
			_:
				_connected_started_at_usec = -1
				_overlay.show_status(status, message)
	if OS.is_debug_build():
		print("[CaromOnlineFlow] Status: %s — %s" % [status, message])


func _on_match_ended(won: bool, your_score: int, their_score: int, forfeit: bool) -> void:
	if OS.is_debug_build():
		var result := "WON" if won else "LOST"
		var note := " (forfeit)" if forfeit else ""
		print("[CaromOnlineFlow] Match %s%s — %d:%d" % [result, note, your_score, their_score])

	# Show the results panel
	var results := CaromMultiplayerResults.new()
	results.name = "MultiplayerResults"
	var overlay_layer := get_parent().get_node_or_null(OVERLAY_LAYER_PATH) as Control
	if overlay_layer:
		overlay_layer.add_child(results)
	else:
		get_parent().add_child(results)
	results.show_results(won, your_score, their_score, forfeit)
	results.menu_requested.connect(func() -> void:
		results.queue_free()
		shutdown()
		SceneTransition.transition_to(Scenes.CAROM_MENU)
	)


func _hide_overlay_after_connected_flash(request_id: int) -> void:
	if not is_instance_valid(_overlay):
		return
	var remaining: float = 0.0
	if _connected_started_at_usec >= 0:
		var elapsed_usec: int = Time.get_ticks_usec() - _connected_started_at_usec
		remaining = maxf(CONNECTED_DISPLAY_DURATION - (float(elapsed_usec) / 1000000.0), 0.0)
	if remaining > 0.0:
		var flow_ref: WeakRef = weakref(self)
		var timer := get_tree().create_timer(remaining, false)
		timer.timeout.connect(func() -> void:
			var flow := flow_ref.get_ref() as CaromOnlineFlow
			if flow == null:
				return
			if request_id != flow._pending_hide_request_id:
				return
			if is_instance_valid(flow._overlay):
				flow._overlay.hide()
			flow._connected_started_at_usec = -1
		)
		return
	if request_id == _pending_hide_request_id and is_instance_valid(_overlay):
		_overlay.hide()
	_connected_started_at_usec = -1


func _on_back_requested() -> void:
	shutdown()
	if is_instance_valid(_overlay):
		_overlay.hide()
	flow_completed.emit()
	SceneTransition.transition_to(Scenes.CAROM_MENU)


func shutdown() -> void:
	if _match_ctrl:
		_match_ctrl.shutdown()
	if _local_server:
		_local_server.stop()
		_local_server.queue_free()
		_local_server = null


func _exit_tree() -> void:
	shutdown()
