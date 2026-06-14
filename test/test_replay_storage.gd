extends GutTest

## Unit tests for ReplayStorage — persistence, indexing, import/export, and pending playback.

const StorageScript := preload("res://scripts/replays/replay_storage.gd")

var storage: Node


func before_each() -> void:
	storage = Node.new()
	storage.set_script(StorageScript)
	add_child_autofree(storage)
	# Override internal state after _ready (avoids filesystem side-effects)
	storage._replay_index = [] as Array[Dictionary]
	storage._pending_playback = {}


# --- Helpers ---

func _make_replay(id: String, game_mode: String, timestamp: int = 0) -> Dictionary:
	return {
		"id": id,
		"header": {
			"game_mode": game_mode,
			"seed": 1,
			"timestamp": timestamp,
			"initial_state": {},
			"settings_snapshot": {},
			"version": "1.0",
		},
		"frames": [],
		"footer": {
			"final_score": 10,
			"duration": 5.0,
			"outcome": "win",
			"final_state": {},
		},
	}


# --- Tests ---

func test_save_and_retrieve_replay() -> void:
	var replay := _make_replay("abc123", "shikaku")
	var saved_id := storage.save_replay(replay)
	assert_eq(saved_id, "abc123")
	var retrieved: Dictionary = storage.get_replay_by_id("abc123")
	assert_false(retrieved.is_empty())
	assert_eq(retrieved["id"], "abc123")
	assert_eq(retrieved["header"]["game_mode"], "shikaku")


func test_recent_replays_ordered() -> void:
	storage.save_replay(_make_replay("r1", "blockudoku", 100))
	storage.save_replay(_make_replay("r2", "shikaku", 200))
	storage.save_replay(_make_replay("r3", "sudoku", 300))
	var recent: Array[Dictionary] = storage.get_recent_replays(10)
	assert_eq(recent.size(), 3)
	# get_recent_replays returns oldest-to-newest (index order)
	assert_eq(recent[0]["id"], "r1")
	assert_eq(recent[1]["id"], "r2")
	assert_eq(recent[2]["id"], "r3")


func test_delete_removes_replay() -> void:
	storage.save_replay(_make_replay("del1", "sudoku"))
	assert_false(storage.get_replay_by_id("del1").is_empty())
	var ok := storage.delete_replay("del1")
	assert_true(ok)
	assert_true(storage.get_replay_by_id("del1").is_empty())


func test_export_import_roundtrip() -> void:
	var replay := _make_replay("export1", "blockudoku")
	storage.save_replay(replay)
	var code := storage.export_replay_code("export1")
	assert_true(code.begins_with("SVG1_"))
	var imported: Dictionary = storage.import_replay_code(code)
	assert_false(imported.is_empty())
	assert_eq(imported["id"], "export1")
	assert_eq(imported["header"]["game_mode"], "blockudoku")


func test_rolling_buffer_limit() -> void:
	# Save MAX_AUTO_REPLAYS + 2 non-bookmarked replays; oldest two should be evicted
	var limit: int = storage.MAX_AUTO_REPLAYS
	for i in range(limit + 2):
		storage.save_replay(_make_replay("r%d" % i, "shikaku"))
	var remaining: Array[Dictionary] = storage.get_recent_replays(limit + 2)
	assert_eq(remaining.size(), limit)
	# r0 and r1 should have been evicted
	for entry in remaining:
		assert_ne(entry["id"], "r0")
		assert_ne(entry["id"], "r1")


func test_set_get_pending_playback() -> void:
	var replay := {"id": "pending1", "frames": []}
	storage.set_pending_playback(replay)
	var retrieved: Dictionary = storage.get_pending_playback()
	assert_eq(retrieved["id"], "pending1")


func test_get_pending_clears_after_read() -> void:
	storage.set_pending_playback({"id": "once"})
	storage.get_pending_playback()
	var second: Dictionary = storage.get_pending_playback()
	assert_true(second.is_empty())
