extends GutTest

## Shared integration tests for the generative logic-games collection release.
## Covers the shared registration surfaces wired for Crown Grid, Eclipse Grid,
## and Number Path (distinct Games) plus Mini Sudoku and Shikaku Shapes (Modes):
## Hub registry entries, Scenes constants, replay allowlist/factory parity,
## help resources, save coexistence, achievement trigger keys, leaderboard mode
## labels/mapping, LaunchParams backward compatibility, and legacy behavior.

const ReplayPlayerScript := preload("res://scripts/replays/replay_player.gd")
const ReplaysScreenScript := preload("res://scripts/replays/replays_screen.gd")
const SudokuStatsScreenScript := preload("res://scripts/sudoku/sudoku_stats_screen.gd")

const NEW_GAME_IDS := ["crown_grid", "eclipse_grid", "number_path"]

const MENU_CONFIGS := {
	"crown_grid": "res://assets/menu/crown_grid_menu.tres",
	"eclipse_grid": "res://assets/menu/eclipse_grid_menu.tres",
	"number_path": "res://assets/menu/number_path_menu.tres",
}

const EXPECTED_LEADERBOARD_MODES := {
	"crown_grid": ["easy", "medium", "hard", "expert"],
	"eclipse_grid": ["4", "6", "8", "10"],
	"number_path": ["easy", "medium", "hard", "expert"],
}


# ---------------------------------------------------------------------------
# GameRegistry entries and scene-path loading
# ---------------------------------------------------------------------------

func test_registry_contains_new_distinct_games() -> void:
	var ids: Array[String] = []
	for entry: GameEntry in GameRegistry.ENTRIES:
		ids.append(entry.id)
	for gid in NEW_GAME_IDS:
		assert_true(gid in ids, "GameRegistry must contain '%s'" % gid)


func test_registry_entries_have_loadable_menu_scenes() -> void:
	for entry: GameEntry in GameRegistry.ENTRIES:
		assert_false(entry.menu_scene_path.is_empty(),
			"Entry '%s' must define a menu_scene_path" % entry.id)
		assert_true(ResourceLoader.exists(entry.menu_scene_path),
			"Entry '%s' menu scene must exist: %s" % [entry.id, entry.menu_scene_path])
		var packed := ResourceLoader.load(entry.menu_scene_path) as PackedScene
		assert_not_null(packed, "Entry '%s' menu scene must load as a PackedScene" % entry.id)


func test_registry_game_ids_are_unique() -> void:
	var seen: Dictionary = {}
	for entry: GameEntry in GameRegistry.ENTRIES:
		assert_false(seen.has(entry.id), "Duplicate game id in GameRegistry: %s" % entry.id)
		seen[entry.id] = true


func test_new_games_have_no_unlock_rule() -> void:
	for entry: GameEntry in GameRegistry.ENTRIES:
		if entry.id in NEW_GAME_IDS:
			assert_eq(entry.unlock_rule, "",
				"Distinct game '%s' should always be visible in the Hub" % entry.id)


# ---------------------------------------------------------------------------
# Scenes constants
# ---------------------------------------------------------------------------

func test_scene_constants_point_to_existing_scenes() -> void:
	var paths := [
		Scenes.CROWN_GRID_MENU, Scenes.CROWN_GRID_GAME, Scenes.CROWN_GRID_STATS,
		Scenes.ECLIPSE_GRID_MENU, Scenes.ECLIPSE_GRID_GAME, Scenes.ECLIPSE_GRID_STATS,
		Scenes.NUMBER_PATH_MENU, Scenes.NUMBER_PATH_GAME, Scenes.NUMBER_PATH_STATS,
	]
	for path: String in paths:
		assert_true(ResourceLoader.exists(path), "Scene constant path must exist: %s" % path)


# ---------------------------------------------------------------------------
# MenuConfig resources: uniqueness and leaderboard modes
# ---------------------------------------------------------------------------

func test_menu_configs_load_with_matching_ids() -> void:
	for gid in MENU_CONFIGS.keys():
		var config: MenuConfig = load(MENU_CONFIGS[gid])
		assert_not_null(config, "MenuConfig must load for %s" % gid)
		assert_eq(config.game_id, gid, "MenuConfig game_id must match %s" % gid)
		assert_true(ResourceLoader.exists(config.game_scene_path),
			"%s game scene must exist" % gid)
		assert_true(ResourceLoader.exists(config.stats_scene_path),
			"%s stats scene must exist" % gid)


func test_menu_configs_have_expected_leaderboard_modes() -> void:
	for gid in EXPECTED_LEADERBOARD_MODES.keys():
		var config: MenuConfig = load(MENU_CONFIGS[gid])
		var modes: Array = []
		for m in config.leaderboard_modes:
			modes.append(m)
		assert_eq(modes, EXPECTED_LEADERBOARD_MODES[gid],
			"%s leaderboard modes must match spec" % gid)
		assert_true(config.leaderboard_is_time_based,
			"%s leaderboards are time-based" % gid)


func test_leaderboard_keys_are_unique_across_new_games() -> void:
	var seen: Dictionary = {}
	for gid in EXPECTED_LEADERBOARD_MODES.keys():
		for mode: String in EXPECTED_LEADERBOARD_MODES[gid]:
			var key := "%s:%s" % [gid, mode]
			assert_false(seen.has(key), "Duplicate leaderboard key: %s" % key)
			seen[key] = true


# ---------------------------------------------------------------------------
# Replay allowlist / factory parity
# ---------------------------------------------------------------------------

func test_replay_factory_returns_adapter_for_supported_games() -> void:
	var player := ReplayPlayerScript.new()
	var seen: Dictionary = {}
	for game_mode in ReplaysScreenScript.SUPPORTED_GAME_MODES:
		assert_false(seen.has(game_mode), "Replay allowlist contains duplicate '%s'" % game_mode)
		seen[game_mode] = true
		var adapter: GameReplayAdapter = player._create_adapter(game_mode)
		assert_not_null(adapter,
			"Replay factory must support allowlisted game '%s'" % game_mode)
	player.free()


func test_replay_factory_returns_correct_new_adapter_types() -> void:
	var player := ReplayPlayerScript.new()
	assert_true(player._create_adapter("crown_grid") is CrownGridReplayAdapter)
	assert_true(player._create_adapter("eclipse_grid") is EclipseGridReplayAdapter)
	assert_true(player._create_adapter("number_path") is NumberPathReplayAdapter)
	player.free()


func test_replay_factory_rejects_unknown_mode() -> void:
	var player := ReplayPlayerScript.new()
	assert_null(player._create_adapter("carom"),
		"Carom is not a supported puzzle replay mode")
	assert_null(player._create_adapter("does_not_exist"))
	player.free()


# ---------------------------------------------------------------------------
# Help resources
# ---------------------------------------------------------------------------

func test_help_resources_load_for_all_hub_games() -> void:
	var topics := ["sudoku", "shikaku", "blockudoku", "carom",
		"crown_grid", "eclipse_grid", "number_path",
		"sudoku_mini", "shikaku_shapes"]
	for topic: String in topics:
		var path := "res://assets/help/%s_help.tres" % topic
		assert_true(ResourceLoader.exists(path), "Help resource must exist: %s" % path)
		var content: HelpContent = load(path)
		assert_not_null(content, "Help must load for %s" % topic)
		assert_false(content.body.is_empty(), "%s help body must not be empty" % topic)


# ---------------------------------------------------------------------------
# Save coexistence across all puzzle Games
# ---------------------------------------------------------------------------

func test_save_adapters_have_distinct_game_ids() -> void:
	var adapters := {
		"sudoku": SudokuSaveAdapter.new(),
		"shikaku": ShikakuSaveAdapter.new(),
		"blockudoku": BlockudokuSaveAdapter.new(),
		"crown_grid": CrownGridSaveAdapter.new(),
		"eclipse_grid": EclipseGridSaveAdapter.new(),
		"number_path": NumberPathSaveAdapter.new(),
	}
	var seen: Dictionary = {}
	for expected_id in adapters.keys():
		var gid: String = adapters[expected_id]._get_game_id()
		assert_eq(gid, expected_id, "Save adapter id mismatch for %s" % expected_id)
		assert_false(seen.has(gid), "Duplicate save section id: %s" % gid)
		seen[gid] = true


func test_saves_coexist_in_distinct_sections() -> void:
	var test_path := "user://test_logic_games_saves.cfg"
	var original := GameSaveManager.save_path
	GameSaveManager.save_path = test_path
	GameSaveManager.clear_all()

	var adapters := {
		"sudoku": SudokuSaveAdapter.new(),
		"shikaku": ShikakuSaveAdapter.new(),
		"blockudoku": BlockudokuSaveAdapter.new(),
		"crown_grid": CrownGridSaveAdapter.new(),
		"eclipse_grid": EclipseGridSaveAdapter.new(),
		"number_path": NumberPathSaveAdapter.new(),
	}
	var sentinel := 1
	for game_id in adapters:
		adapters[game_id].save({"integration_sentinel": sentinel})
		sentinel += 1

	sentinel = 1
	for game_id in adapters:
		assert_eq(
			int(adapters[game_id].restore().get("integration_sentinel", -1)),
			sentinel,
			"%s save must remain isolated" % game_id)
		sentinel += 1

	# Clearing one must not disturb the others.
	adapters["crown_grid"].clear()
	assert_false(adapters["crown_grid"].has_save(), "Crown save cleared")
	for game_id in adapters:
		if game_id != "crown_grid":
			assert_true(adapters[game_id].has_save(),
				"%s save intact after clearing Crown" % game_id)

	GameSaveManager.clear_all()
	GameSaveManager.save_path = original
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)


# ---------------------------------------------------------------------------
# Achievement trigger keys, categories, uniqueness
# ---------------------------------------------------------------------------

func test_achievement_ids_unique_and_match_dict_key() -> void:
	for id in AchievementCatalog.DEFINITIONS.keys():
		var definition: Dictionary = AchievementCatalog.DEFINITIONS[id]
		assert_eq(str(definition.get("id", "")), id,
			"Achievement dict key must match its id field: %s" % id)


func test_new_game_achievement_categories_registered() -> void:
	for category in ["Crown Grid", "Eclipse Grid", "Number Path"]:
		assert_true(AchievementCatalog.CATEGORY_ORDER.has(category),
			"CATEGORY_ORDER must include %s" % category)


func test_achievement_categories_all_have_defined_order() -> void:
	for id in AchievementCatalog.DEFINITIONS.keys():
		var category: String = str(AchievementCatalog.DEFINITIONS[id].get("category", ""))
		assert_true(AchievementCatalog.CATEGORY_ORDER.has(category),
			"Achievement '%s' uses unordered category '%s'" % [id, category])


func test_new_game_achievements_reference_real_stat_keys() -> void:
	# The stat trigger keys must match the {game_id}.{counter} the game screens emit.
	var expected_keys := {
		"crown_grid_first_win": "crown_grid.games_won",
		"crown_grid_easy_win": "crown_grid.completed_t0",
		"crown_grid_expert_win": "crown_grid.completed_t3",
		"crown_grid_10_wins": "crown_grid.games_won",
		"crown_grid_streak_5": "crown_grid.current_streak",
		"eclipse_grid_first_win": "eclipse_grid.games_won",
		"eclipse_grid_small_win": "eclipse_grid.completed_s4",
		"eclipse_grid_large_win": "eclipse_grid.completed_s10",
		"eclipse_grid_10_wins": "eclipse_grid.games_won",
		"eclipse_grid_streak_5": "eclipse_grid.current_streak",
		"number_path_first_win": "number_path.games_won",
		"number_path_easy_win": "number_path.completed_easy",
		"number_path_expert_win": "number_path.completed_expert",
		"number_path_10_wins": "number_path.games_won",
		"number_path_streak_5": "number_path.current_streak",
		"sudoku_mini_win": "sudoku.completed_mini",
		"shikaku_shapes_win": "shikaku.completed_shapes_s5",
		"shikaku_shapes_15_win": "shikaku.completed_shapes_s15",
	}
	for id in expected_keys.keys():
		assert_true(AchievementCatalog.DEFINITIONS.has(id),
			"Missing achievement definition: %s" % id)
		var trigger: Dictionary = AchievementCatalog.DEFINITIONS[id].get("trigger", {})
		assert_eq(str(trigger.get("key", "")), expected_keys[id],
			"Achievement '%s' trigger key must be %s" % [id, expected_keys[id]])


func test_achievement_prerequisites_reference_existing_ids() -> void:
	for id in AchievementCatalog.DEFINITIONS.keys():
		var prereq: String = str(AchievementCatalog.DEFINITIONS[id].get("prerequisite_id", ""))
		if prereq != "":
			assert_true(AchievementCatalog.DEFINITIONS.has(prereq),
				"Achievement '%s' references missing prerequisite '%s'" % [id, prereq])


# ---------------------------------------------------------------------------
# LaunchParams backward compatibility
# ---------------------------------------------------------------------------

func test_launch_params_defaults_unchanged() -> void:
	var params := LaunchParams.new()
	assert_eq(params.option_value, 0)
	assert_eq(params.rule_set, 0, "Default rule_set must remain standard (0)")
	assert_false(params.online)


func test_menu_config_builds_launch_params_without_rule_set() -> void:
	# Legacy games build params via MenuConfig and never touch rule_set.
	var config: MenuConfig = load("res://assets/menu/crown_grid_menu.tres")
	var params: LaunchParams = config.build_launch_params(1)
	assert_eq(params.rule_set, 0, "MenuConfig must not set a non-standard rule_set")


# ---------------------------------------------------------------------------
# Mode labels / option-to-mode mapping and legacy Sudoku/Shikaku behavior
# ---------------------------------------------------------------------------

func test_sudoku_mini_is_a_mode_not_a_hub_game() -> void:
	for entry: GameEntry in GameRegistry.ENTRIES:
		assert_ne(entry.id, "mini", "Mini Sudoku must not be a separate Hub Game")
		assert_ne(entry.id, "sudoku_mini", "Mini Sudoku must not be a separate Hub Game")
	var menu = load("res://scripts/sudoku/sudoku_main_menu.gd").new()
	menu._rule_set_index = menu.RULE_SET_MINI
	var params: LaunchParams = menu._build_launch_params(4)
	assert_eq(params.rule_set, menu.RULE_SET_MINI)
	assert_eq(params.option_value, 0, "Mini must force its single quick-play option")
	assert_eq(Array(menu.MINI_MODES), ["mini"])
	menu.free()


func test_shikaku_shapes_is_a_mode_not_a_hub_game() -> void:
	for entry: GameEntry in GameRegistry.ENTRIES:
		assert_ne(entry.id, "shapes", "Shikaku Shapes must not be a separate Hub Game")
		assert_ne(entry.id, "shikaku_shapes", "Shikaku Shapes must not be a separate Hub Game")
	var menu = load("res://scripts/shikaku/shikaku_menu.gd").new()
	var config: MenuConfig = load("res://assets/menu/shikaku_menu.tres")
	var sizes := Array(config.option_values)
	assert_eq(sizes, [5, 7, 8, 10, 12, 15])
	menu._mode_index = menu.MODE_SHAPES
	for size in sizes:
		var params: LaunchParams = menu._build_launch_params(size)
		assert_eq(params.rule_set, menu.MODE_SHAPES)
		assert_eq(params.option_value, size)
	assert_eq(Array(menu.SHAPES_LEADERBOARD_MODES),
		["shapes_5", "shapes_7", "shapes_8", "shapes_10", "shapes_12", "shapes_15"])
	menu.free()


func test_legacy_sudoku_and_shikaku_launch_defaults_remain_standard() -> void:
	var sudoku = load("res://scripts/sudoku/sudoku_main_menu.gd").new()
	var sudoku_params: LaunchParams = sudoku._build_launch_params(3)
	assert_eq(sudoku_params.rule_set, sudoku.RULE_SET_STANDARD)
	assert_eq(sudoku_params.option_value, 3)
	sudoku.free()

	var shikaku = load("res://scripts/shikaku/shikaku_menu.gd").new()
	var shikaku_params: LaunchParams = shikaku._build_launch_params(10)
	assert_eq(shikaku_params.rule_set, shikaku.MODE_STANDARD)
	assert_eq(shikaku_params.option_value, 10)
	shikaku.free()


func test_mini_stats_history_excludes_standard_sudoku() -> void:
	var test_path := "user://test_logic_games_stats.cfg"
	var original := GameStatsManager.save_path
	GameStatsManager.save_path = test_path
	GameStatsManager.clear("sudoku")
	GameStatsManager.record("sudoku", {
		"time": 45.0,
		"difficulty": 0,
		"rule_set": 4,
	})
	GameStatsManager.record("sudoku", {
		"time": 120.0,
		"difficulty": 0,
		"rule_set": 0,
	})

	var screen := SudokuStatsScreenScript.new()
	var mini_times: Array = screen._get_time_history_for_rule_set(4)
	screen.free()
	assert_eq(mini_times, [45.0])

	GameStatsManager.save_path = original
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)


func test_crown_grid_option_values_map_to_leaderboard_modes() -> void:
	# Crown Grid tier options (0..3) map positionally to easy/medium/hard/expert.
	var config: MenuConfig = load("res://assets/menu/crown_grid_menu.tres")
	assert_eq(config.option_values.size(), config.leaderboard_modes.size(),
		"Each Crown Grid option value must map to one leaderboard mode")


func test_eclipse_grid_option_values_are_raw_sizes() -> void:
	var config: MenuConfig = load("res://assets/menu/eclipse_grid_menu.tres")
	var values: Array[int] = []
	for v in config.option_values:
		values.append(v)
	assert_eq(values, [4, 6, 8, 10], "Eclipse Grid sizes are raw 4/6/8/10")
	assert_eq(Array(config.leaderboard_modes), ["4", "6", "8", "10"])
