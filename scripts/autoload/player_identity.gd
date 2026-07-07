extends Node

## Player identity manager — device UUID, display name, leaderboard visibility.
## Persists identity to user://player_identity.cfg and device UUID to user://device_id.txt.
## Syncs profile to the server via PUT /profile on boot and on settings changes.
## Offline-safe: queues the sync and retries on the next successful connection.

const SAVE_PATH := "user://player_identity.cfg"
const DEVICE_ID_PATH := "user://device_id.txt"

## REST base URL derived from the signaling server (wss:// → https://).
const REST_BASE_URL := "https://carom-signaling-dae9dadjh0h9aqgb.westus3-01.azurewebsites.net"

## Maximum display name length enforced on client and server.
const MAX_DISPLAY_NAME_LENGTH := 20

## Unique device identifier, generated once and persisted across launches.
var device_id: String = ""

## Player-chosen display name shown on leaderboards (max 20 chars).
var display_name: String = ""

## Whether this device's scores appear on public leaderboards.
var leaderboard_visible: bool = true

## True once the player has completed the first-boot name prompt.
var is_setup_complete: bool = false

var _pending_sync: bool = false
var _sync_in_flight: bool = false
var _http: HTTPRequest = null


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_sync_completed)
	_load()
	# Retry any queued sync from a previous offline session.
	if is_setup_complete and _pending_sync:
		sync_profile()


## Called by the name prompt screen to finalise first-boot setup.
func complete_setup(name: String, visible: bool) -> void:
	display_name = name.strip_edges().substr(0, MAX_DISPLAY_NAME_LENGTH)
	leaderboard_visible = visible
	is_setup_complete = true
	_pending_sync = true
	_save()


## Sync the current profile to the server.
## Safe to call at any time — queues for retry if offline or a request is already in flight.
func sync_profile() -> void:
	if not is_setup_complete:
		return
	_pending_sync = true
	_save()
	if _http == null or _sync_in_flight:
		return
	_sync_in_flight = true
	var body := JSON.stringify({
		"device_id": device_id,
		"display_name": display_name,
		"visible": leaderboard_visible,
	})
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _http.request(REST_BASE_URL + "/profile", headers, HTTPClient.METHOD_PUT, body)
	if err != OK:
		_sync_in_flight = false
		# _pending_sync remains true; will retry on next launch.


func _on_sync_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_sync_in_flight = false
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		_pending_sync = false
		_save()


func _load() -> void:
	# Load or generate the device UUID.
	if FileAccess.file_exists(DEVICE_ID_PATH):
		var file := FileAccess.open(DEVICE_ID_PATH, FileAccess.READ)
		if file:
			device_id = file.get_as_text().strip_edges()
	if device_id.is_empty():
		device_id = _generate_uuid_v4()
		_save_device_id()

	# Load identity settings.
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	display_name = config.get_value("profile", "display_name", "")
	leaderboard_visible = config.get_value("profile", "visible", true)
	is_setup_complete = config.get_value("profile", "setup_complete", false)
	_pending_sync = config.get_value("profile", "pending_sync", false)


func _save() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("profile", "display_name", display_name)
	config.set_value("profile", "visible", leaderboard_visible)
	config.set_value("profile", "setup_complete", is_setup_complete)
	config.set_value("profile", "pending_sync", _pending_sync)
	config.save(SAVE_PATH)


func _save_device_id() -> void:
	var file := FileAccess.open(DEVICE_ID_PATH, FileAccess.WRITE)
	if file:
		file.store_string(device_id)


## Generates a random UUID v4 string.
func _generate_uuid_v4() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var b: Array[int] = []
	for i in range(16):
		b.append(rng.randi() % 256)
	b[6] = (b[6] & 0x0f) | 0x40  # version 4
	b[8] = (b[8] & 0x3f) | 0x80  # variant bits
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
		b[0], b[1], b[2], b[3],
		b[4], b[5],
		b[6], b[7],
		b[8], b[9],
		b[10], b[11], b[12], b[13], b[14], b[15]
	]
