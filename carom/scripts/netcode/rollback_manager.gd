class_name RollbackManager
extends RefCounted

const ROLLBACK_BUFFER: int = 10

var _snapshots: Array[Dictionary] = []
var _input_buffer: Array[Dictionary] = []
var _current_frame: int = 0
var _sim: SimWorld = null

var _needs_rollback_flag: bool = false
var _is_replaying: bool = false
var _last_confirmed_remote_input: int = 0
var _static_walls: Array = []
var _static_zones: Array = []


func initialize(sim: SimWorld) -> void:
	_sim = sim
	_current_frame = 0
	_needs_rollback_flag = false
	_is_replaying = false
	_last_confirmed_remote_input = 0
	_static_walls = _sim._walls.duplicate()
	_static_zones = _sim._zones.duplicate()
	_snapshots = []
	_snapshots.resize(ROLLBACK_BUFFER)
	_input_buffer = []
	_input_buffer.resize(ROLLBACK_BUFFER)


func advance_frame(local_input: int, remote_input: int, confirmed: bool) -> void:
	if _sim == null:
		return

	_store_snapshot(_current_frame, _capture_state())

	var predicted_remote_input: int = _predict_remote_input(_current_frame)
	if confirmed:
		_last_confirmed_remote_input = remote_input

	_store_input_entry(_current_frame, {
		frame = _current_frame,
		local_input = local_input,
		remote_input = remote_input,
		predicted_remote_input = predicted_remote_input,
		remote_confirmed = confirmed,
		mispredicted = false,
	})

	_sim.advance({
		local_input = local_input,
		remote_input = remote_input,
	})
	_current_frame += 1


func receive_remote_input(frame: int, input: int) -> void:
	if frame < 0:
		return
	if frame < _current_frame - ROLLBACK_BUFFER:
		return

	var entry: Dictionary = _get_input_entry(frame)
	if entry.is_empty():
		entry = {
			frame = frame,
			local_input = 0,
			remote_input = _predict_remote_input(frame),
			predicted_remote_input = _predict_remote_input(frame),
			remote_confirmed = false,
			mispredicted = false,
		}

	var simulated_remote_input: int = entry.get("remote_input", 0)
	entry["remote_confirmed"] = true
	entry["remote_input"] = input
	entry["mispredicted"] = simulated_remote_input != input
	_store_input_entry(frame, entry)

	_last_confirmed_remote_input = input
	if entry["mispredicted"]:
		_needs_rollback_flag = true


func needs_rollback() -> bool:
	return _needs_rollback_flag


func execute_rollback() -> void:
	if _sim == null or not _needs_rollback_flag or _is_replaying:
		return

	var rollback_frame: int = _find_earliest_mispredicted_frame()
	if rollback_frame < 0:
		_needs_rollback_flag = false
		return

	var state: Dictionary = _get_snapshot(rollback_frame)
	if state.is_empty():
		_needs_rollback_flag = false
		return

	_is_replaying = true
	_apply_state(state)

	var target_frame: int = _current_frame
	for frame: int in range(rollback_frame, target_frame):
		_store_snapshot(frame, _capture_state())
		var entry: Dictionary = _get_or_create_input_entry(frame)
		var remote_input: int = entry.get("remote_input", _predict_remote_input(frame))
		if not entry.get("remote_confirmed", false):
			remote_input = _predict_remote_input(frame)
			entry["remote_input"] = remote_input
			entry["predicted_remote_input"] = remote_input

		entry["mispredicted"] = false
		_store_input_entry(frame, entry)
		_sim.advance({
			local_input = entry.get("local_input", 0),
			remote_input = remote_input,
		})

	_is_replaying = false
	_needs_rollback_flag = false


func get_current_frame() -> int:
	return _current_frame


func get_confirmed_frame() -> int:
	var latest: int = -1
	var earliest_kept_frame: int = maxi(0, _current_frame - ROLLBACK_BUFFER)
	for frame: int in range(earliest_kept_frame, _current_frame):
		var entry: Dictionary = _get_input_entry(frame)
		if entry.is_empty():
			break
		if entry.get("remote_confirmed", false):
			latest = frame
		else:
			break
	return latest


func _find_earliest_mispredicted_frame() -> int:
	var earliest: int = -1
	var earliest_kept_frame: int = maxi(0, _current_frame - ROLLBACK_BUFFER)
	for frame: int in range(earliest_kept_frame, _current_frame):
		var entry: Dictionary = _get_input_entry(frame)
		if entry.is_empty():
			continue
		if entry.get("mispredicted", false):
			if earliest == -1 or frame < earliest:
				earliest = frame
	return earliest


func _predict_remote_input(frame: int) -> int:
	if frame <= 0:
		return _last_confirmed_remote_input
	var previous: Dictionary = _get_input_entry(frame - 1)
	if previous.is_empty():
		return _last_confirmed_remote_input
	return previous.get("remote_input", _last_confirmed_remote_input)


func _get_or_create_input_entry(frame: int) -> Dictionary:
	var entry: Dictionary = _get_input_entry(frame)
	if not entry.is_empty():
		return entry
	return {
		frame = frame,
		local_input = 0,
		remote_input = _predict_remote_input(frame),
		predicted_remote_input = _predict_remote_input(frame),
		remote_confirmed = false,
		mispredicted = false,
	}


func _store_snapshot(frame: int, state: Dictionary) -> void:
	var slot: int = frame % ROLLBACK_BUFFER
	_snapshots[slot] = {
		frame = frame,
		state = state.duplicate(true),
	}


func _get_snapshot(frame: int) -> Dictionary:
	if frame < 0 or _snapshots.is_empty():
		return {}
	var slot: int = frame % ROLLBACK_BUFFER
	var entry: Dictionary = _snapshots[slot]
	if entry.is_empty():
		return {}
	if entry.get("frame", -1) != frame:
		return {}
	return (entry.get("state", {}) as Dictionary).duplicate(true)


func _store_input_entry(frame: int, entry: Dictionary) -> void:
	var slot: int = frame % ROLLBACK_BUFFER
	_input_buffer[slot] = entry.duplicate(true)


func _get_input_entry(frame: int) -> Dictionary:
	if frame < 0 or _input_buffer.is_empty():
		return {}
	var slot: int = frame % ROLLBACK_BUFFER
	var entry: Dictionary = _input_buffer[slot]
	if entry.is_empty():
		return {}
	if entry.get("frame", -1) != frame:
		return {}
	return entry.duplicate(true)


func _capture_state() -> Dictionary:
	if _supports_custom_state_api():
		return (_sim.call("get_state") as Dictionary).duplicate(true)
	return (_sim.get_body_state() as Dictionary).duplicate(true)


func _apply_state(state: Dictionary) -> void:
	if _supports_custom_state_api():
		_sim.call("set_state", state.duplicate(true))
		return
	_sim.set_body_state(state.duplicate(true))
	_restore_static_geometry()


func _supports_custom_state_api() -> bool:
	if _sim == null:
		return false
	return _sim.has_method("get_state") and _sim.has_method("set_state")


func _restore_static_geometry() -> void:
	if _sim == null:
		return
	for wall: Variant in _static_walls:
		_sim.add_wall(wall)
	for zone: Variant in _static_zones:
		_sim.add_zone(zone)
