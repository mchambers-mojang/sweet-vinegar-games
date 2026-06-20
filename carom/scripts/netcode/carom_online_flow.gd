class_name CaromOnlineFlow
extends Node

## Manages the full online multiplayer flow:
##   Menu → Create/Join → Connecting → Match → Results → Menu
##
## Add this as a child of the CaromArena scene when launching online mode.
## It creates the CaromOnlineMatchController and coordinates UI overlays.

const SIGNALING_URL_DEFAULT := "ws://localhost:8080"
const CONNECTION_OVERLAY_SCENE := preload("res://carom/scenes/carom_connection_overlay.tscn")
const CONNECTED_FLASH_SECONDS: float = 1.2
const OVERLAY_LAYER_PATH := "HUD/OverlayLayer"

signal flow_completed  ## Emitted when the player returns to menu

var _match_ctrl: CaromOnlineMatchController = null
var _signaling_url: String = SIGNALING_URL_DEFAULT
var _overlay: CaromConnectionOverlay = null
var _connected_started_at_msec: int = -1
var _pending_hide_request_id: int = 0


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
				_connected_started_at_msec = Time.get_ticks_msec()
				_overlay.show_status(status, message)
			"playing":
				_hide_overlay_after_connected_flash(_pending_hide_request_id)
			_:
				_connected_started_at_msec = -1
				_overlay.show_status(status, message)
	if OS.is_debug_build():
		print("[CaromOnlineFlow] Status: %s — %s" % [status, message])


func _on_match_ended(won: bool, your_score: int, their_score: int, forfeit: bool) -> void:
	if OS.is_debug_build():
		var result := "WON" if won else "LOST"
		var note := " (forfeit)" if forfeit else ""
		print("[CaromOnlineFlow] Match %s%s — %d:%d" % [result, note, your_score, their_score])


func _hide_overlay_after_connected_flash(request_id: int) -> void:
	if not is_instance_valid(_overlay):
		return
	var remaining: float = 0.0
	if _connected_started_at_msec >= 0:
		var elapsed_msec: int = Time.get_ticks_msec() - _connected_started_at_msec
		remaining = maxf(CONNECTED_FLASH_SECONDS - (float(elapsed_msec) / 1000.0), 0.0)
	if remaining <= 0.0:
		if request_id == _pending_hide_request_id and is_instance_valid(_overlay):
			_overlay.hide()
		_connected_started_at_msec = -1
		return
	var timer := get_tree().create_timer(remaining)
	timer.timeout.connect(func() -> void:
		if request_id != _pending_hide_request_id:
			return
		if is_instance_valid(_overlay):
			_overlay.hide()
		_connected_started_at_msec = -1
	)


func _on_back_requested() -> void:
	shutdown()
	if is_instance_valid(_overlay):
		_overlay.hide()
	flow_completed.emit()
	SceneTransition.transition_to(Scenes.CAROM_MENU)


func shutdown() -> void:
	if _match_ctrl:
		_match_ctrl.shutdown()


func _exit_tree() -> void:
	shutdown()
