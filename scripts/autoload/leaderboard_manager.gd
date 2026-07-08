extends Node

## Platform leaderboard manager — auto-submits scores to the server on game completion.
## Subscribes to GameEvents.leaderboard_score_ready; submission is fire-and-forget.
## Requires a registered player profile (is_setup_complete + non-empty device_id and
## display_name) and leaderboard_data_enabled must be true. Silently drops on network
## failure — scores are personal bests and will be resubmitted the next time the player
## beats their record.

## REST base URL shared with PlayerIdentity.
const REST_BASE_URL := "https://carom-signaling-dae9dadjh0h9aqgb.westus3-01.azurewebsites.net"

## Live HTTPRequest nodes, one per pending submission. Freed on completion.
var _pending: Array[HTTPRequest] = []


func _ready() -> void:
	GameEvents.leaderboard_score_ready.connect(_on_leaderboard_score_ready)


## Checks profile eligibility and posts the score to the server.
func _on_leaderboard_score_ready(game_id: String, mode: String, value: float) -> void:
	if not PlayerIdentity.leaderboard_data_enabled:
		return
	if not PlayerIdentity.is_setup_complete:
		return
	if PlayerIdentity.device_id.is_empty():
		return
	if PlayerIdentity.display_name.is_empty():
		return
	_submit(game_id, mode, value)


func _submit(game_id: String, mode: String, value: float) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	_pending.append(http)
	http.request_completed.connect(_on_request_done.bind(http))

	# The server resolves display_name from the stored profile via device_id;
	# it does not need display_name in the score POST body.
	var body := JSON.stringify({
		"device_id": PlayerIdentity.device_id,
		"game": game_id,
		"mode": mode,
		"value": value,
	})
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(REST_BASE_URL + "/scores", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_cleanup(http)


func _on_request_done(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray,
	http: HTTPRequest
) -> void:
	# If the server rejected because our profile is missing (e.g. DB was wiped on
	# redeploy), trigger a profile re-sync so subsequent scores go through.
	if response_code == 404 and PlayerIdentity.is_setup_complete:
		PlayerIdentity.sync_profile()
	_cleanup(http)


func _cleanup(http: HTTPRequest) -> void:
	_pending.erase(http)
	if is_instance_valid(http):
		http.queue_free()
