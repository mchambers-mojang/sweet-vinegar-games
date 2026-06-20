class_name CaromOnlineFlow
extends Node

## Manages the full online multiplayer flow:
##   Menu → Create/Join → Connecting → Match → Results → Menu
##
## Add this as a child of the CaromArena scene when launching online mode.
## It creates the CaromOnlineMatchController and coordinates UI overlays.

const SIGNALING_URL_DEFAULT := "ws://localhost:8080"

signal flow_completed  ## Emitted when the player returns to menu

var _match_ctrl: CaromOnlineMatchController = null
var _signaling_url: String = SIGNALING_URL_DEFAULT


## Start hosting a new online match. Call after this node is in the tree
## under a CaromArena.
func start_host(signaling_url: String = "") -> void:
	if signaling_url != "":
		_signaling_url = signaling_url
	_ensure_match_controller()
	_match_ctrl.host(_signaling_url)


## Join an existing match by room code.
func start_join(code: String, signaling_url: String = "") -> void:
	if signaling_url != "":
		_signaling_url = signaling_url
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


func _on_connection_status(status: String, message: String) -> void:
	# UI overlays will connect to this via the match controller signal.
	# For now, just log it for debugging.
	if OS.is_debug_build():
		print("[CaromOnlineFlow] Status: %s — %s" % [status, message])


func _on_match_ended(won: bool, your_score: int, their_score: int, forfeit: bool) -> void:
	if OS.is_debug_build():
		var result := "WON" if won else "LOST"
		var note := " (forfeit)" if forfeit else ""
		print("[CaromOnlineFlow] Match %s%s — %d:%d" % [result, note, your_score, their_score])


func shutdown() -> void:
	if _match_ctrl:
		_match_ctrl.shutdown()


func _exit_tree() -> void:
	shutdown()
