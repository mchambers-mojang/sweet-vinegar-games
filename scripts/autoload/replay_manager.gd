extends Node

## Thin facade — delegates all calls to ReplayRecorder (session lifecycle) and
## ReplayStorage (file I/O). Kept for callers that haven't migrated to the
## specific modules yet. Prefer using ReplayRecorder or ReplayStorage directly.


func set_pending_playback(replay: Dictionary) -> void:
	ReplayStorage.set_pending_playback(replay)


func get_pending_playback() -> Dictionary:
	return ReplayStorage.get_pending_playback()


func start_session(game_mode: String, seed: int, initial_state: Dictionary, settings_snapshot: Dictionary = {}) -> String:
	return ReplayRecorder.start_session(game_mode, seed, initial_state, settings_snapshot)


func has_active_session() -> bool:
	return ReplayRecorder.has_active_session()


func flush_active_replay() -> void:
	ReplayRecorder.flush_active_replay()


func record_input(elapsed_time: float, event_type: String, payload: Dictionary) -> void:
	ReplayRecorder.record_input(elapsed_time, event_type, payload)


func finish_session(outcome: String, final_score: int, duration: float, final_state: Dictionary = {}) -> void:
	var completed := ReplayRecorder.finish_session(outcome, final_score, duration, final_state)
	if not completed.is_empty():
		ReplayStorage.save_replay(completed)


func bookmark_latest_replay() -> bool:
	return ReplayStorage.bookmark_latest_replay()


func delete_replay(replay_id: String) -> bool:
	return ReplayStorage.delete_replay(replay_id)


func get_recent_replays(limit: int = 20) -> Array[Dictionary]:
	return ReplayStorage.get_recent_replays(limit)


func get_replay_by_id(replay_id: String) -> Dictionary:
	return ReplayStorage.get_replay_by_id(replay_id)


func export_replay_code(replay_id: String) -> String:
	return ReplayStorage.export_replay_code(replay_id)


func export_latest_replay_code() -> String:
	return ReplayStorage.export_latest_replay_code()


func import_replay_code(code: String) -> Dictionary:
	return ReplayStorage.import_replay_code(code)


func get_crash_recovery_payload() -> Dictionary:
	return ReplayRecorder.get_crash_recovery_payload()
