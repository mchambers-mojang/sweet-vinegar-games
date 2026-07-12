extends Node

## Thin facade — delegates all calls to ReplaySystem (merged replay autoload).
## Kept for callers that haven't migrated to ReplaySystem directly.
## Prefer using ReplaySystem directly for new callers.


func set_pending_playback(replay: Dictionary) -> void:
	ReplaySystem.set_pending_playback(replay)


func get_pending_playback() -> Dictionary:
	return ReplaySystem.get_pending_playback()


func start_session(game_mode: String, seed: int, initial_state: Dictionary, settings_snapshot: Dictionary = {}) -> String:
	return ReplaySystem.start_session(game_mode, seed, initial_state, settings_snapshot)


func has_active_session() -> bool:
	return ReplaySystem.has_active_session()


func flush_active_replay() -> void:
	ReplaySystem.flush_active_replay()


func record_input(elapsed_time: float, event_type: String, payload: Dictionary) -> void:
	ReplaySystem.record_input(elapsed_time, event_type, payload)


func finish_session(outcome: String, final_score: int, duration: float, final_state: Dictionary = {}) -> void:
	var completed := ReplaySystem.finish_session(outcome, final_score, duration, final_state)
	if not completed.is_empty():
		ReplaySystem.save_replay(completed)


func bookmark_latest_replay() -> bool:
	return ReplaySystem.bookmark_latest_replay()


func delete_replay(replay_id: String) -> bool:
	return ReplaySystem.delete_replay(replay_id)


func get_recent_replays(limit: int = 20) -> Array[Dictionary]:
	return ReplaySystem.get_recent_replays(limit)


func get_replay_by_id(replay_id: String) -> Dictionary:
	return ReplaySystem.get_replay_by_id(replay_id)


func export_replay_code(replay_id: String) -> String:
	return ReplaySystem.export_replay_code(replay_id)


func export_latest_replay_code() -> String:
	return ReplaySystem.export_latest_replay_code()


func import_replay_code(code: String) -> Dictionary:
	return ReplaySystem.import_replay_code(code)


func get_crash_recovery_payload() -> Dictionary:
	return ReplaySystem.get_crash_recovery_payload()
