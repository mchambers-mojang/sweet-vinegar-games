extends GutTest

## GUT tests for GameMenu config-driven behaviour.
##
## These tests exercise the pure-logic parts of GameMenu and MenuConfig
## (virtual-method delegation, option-value resolution, config defaults)
## without spinning up a full scene tree.


const GameMenuScript := preload("res://scripts/game_menu.gd")
const MenuConfigScript := preload("res://scripts/menu/menu_config.gd")


# ---------------------------------------------------------------------------
# MenuConfig — default values
# ---------------------------------------------------------------------------

func test_menu_config_default_game_id() -> void:
	var cfg := MenuConfigScript.new()
	assert_eq(cfg.game_id, "")


func test_menu_config_default_display_name() -> void:
	var cfg := MenuConfigScript.new()
	assert_eq(cfg.display_name, "")


func test_menu_config_default_help_topic() -> void:
	var cfg := MenuConfigScript.new()
	assert_eq(cfg.help_topic, "")


func test_menu_config_default_has_save_support_is_true() -> void:
	var cfg := MenuConfigScript.new()
	assert_true(cfg.has_save_support)


func test_menu_config_default_start_button_unique_name() -> void:
	var cfg := MenuConfigScript.new()
	assert_eq(cfg.start_button_unique_name, "NewGameButton")


func test_menu_config_default_option_values_is_empty() -> void:
	var cfg := MenuConfigScript.new()
	assert_eq(cfg.option_values.size(), 0)


func test_menu_config_default_title_color_key_is_empty() -> void:
	var cfg := MenuConfigScript.new()
	assert_eq(cfg.title_color_key, "")


func test_menu_config_default_game_rules_is_empty() -> void:
	var cfg := MenuConfigScript.new()
	assert_true(cfg.game_rules.is_empty())


# ---------------------------------------------------------------------------
# MenuConfig — property assignment
# ---------------------------------------------------------------------------

func test_menu_config_stores_game_id() -> void:
	var cfg := MenuConfigScript.new()
	cfg.game_id = "sudoku"
	assert_eq(cfg.game_id, "sudoku")


func test_menu_config_stores_display_name() -> void:
	var cfg := MenuConfigScript.new()
	cfg.display_name = "Sudoku"
	assert_eq(cfg.display_name, "Sudoku")


func test_menu_config_stores_has_save_support_false() -> void:
	var cfg := MenuConfigScript.new()
	cfg.has_save_support = false
	assert_false(cfg.has_save_support)


func test_menu_config_stores_option_values() -> void:
	var cfg := MenuConfigScript.new()
	cfg.option_values = PackedInt32Array([5, 7, 8, 10, 12, 15])
	assert_eq(cfg.option_values.size(), 6)
	assert_eq(cfg.option_values[0], 5)
	assert_eq(cfg.option_values[3], 10)
	assert_eq(cfg.option_values[5], 15)


func test_menu_config_stores_game_rules() -> void:
	var cfg := MenuConfigScript.new()
	cfg.game_rules = {"input_mode": "cell_first", "error_mode": "strict"}
	assert_eq(cfg.game_rules["input_mode"], "cell_first")
	assert_eq(cfg.game_rules["error_mode"], "strict")


# ---------------------------------------------------------------------------
# GameMenu without config — virtual method defaults
# ---------------------------------------------------------------------------

func test_game_menu_no_config_get_game_id_returns_empty() -> void:
	var menu := GameMenuScript.new()
	assert_eq(menu._get_game_id(), "")
	menu.free()


func test_game_menu_no_config_get_display_name_returns_empty() -> void:
	var menu := GameMenuScript.new()
	assert_eq(menu._get_display_name(), "")
	menu.free()


func test_game_menu_no_config_has_save_support_returns_true() -> void:
	var menu := GameMenuScript.new()
	assert_true(menu._has_save_support())
	menu.free()


func test_game_menu_no_config_get_help_topic_returns_empty() -> void:
	var menu := GameMenuScript.new()
	assert_eq(menu._get_help_topic(), "")
	menu.free()


# ---------------------------------------------------------------------------
# GameMenu with config — virtual method delegation
# ---------------------------------------------------------------------------

func test_game_menu_config_get_game_id() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.game_id = "shikaku"
	assert_eq(menu._get_game_id(), "shikaku")
	menu.free()


func test_game_menu_config_get_display_name() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.display_name = "Shikaku"
	assert_eq(menu._get_display_name(), "Shikaku")
	menu.free()


func test_game_menu_config_get_help_topic() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.help_topic = "carom"
	assert_eq(menu._get_help_topic(), "carom")
	menu.free()


func test_game_menu_config_get_menu_scene_path() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.menu_scene_path = "res://scenes/shikaku_menu.tscn"
	assert_eq(menu._get_menu_scene_path(), "res://scenes/shikaku_menu.tscn")
	menu.free()


func test_game_menu_config_get_game_scene_path() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.game_scene_path = "res://scenes/game.tscn"
	assert_eq(menu._get_game_scene_path(), "res://scenes/game.tscn")
	menu.free()


func test_game_menu_config_get_stats_scene_path() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.stats_scene_path = "res://scenes/stats.tscn"
	assert_eq(menu._get_stats_scene_path(), "res://scenes/stats.tscn")
	menu.free()


func test_game_menu_config_has_save_support_true() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.has_save_support = true
	assert_true(menu._has_save_support())
	menu.free()


func test_game_menu_config_has_save_support_false() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.has_save_support = false
	assert_false(menu._has_save_support())
	menu.free()


# ---------------------------------------------------------------------------
# GameMenu._resolve_option_value — option index-to-value mapping
# ---------------------------------------------------------------------------

func test_resolve_option_value_no_config_returns_index() -> void:
	var menu := GameMenuScript.new()
	# config is null
	assert_eq(menu._resolve_option_value(3), 3)
	menu.free()


func test_resolve_option_value_no_option_values_returns_index() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	# option_values is empty — index is returned as-is
	assert_eq(menu._resolve_option_value(2), 2)
	assert_eq(menu._resolve_option_value(0), 0)
	menu.free()


func test_resolve_option_value_with_values_array() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.option_values = PackedInt32Array([5, 7, 8, 10, 12, 15])
	assert_eq(menu._resolve_option_value(0), 5)
	assert_eq(menu._resolve_option_value(1), 7)
	assert_eq(menu._resolve_option_value(3), 10)
	assert_eq(menu._resolve_option_value(5), 15)
	menu.free()


func test_resolve_option_value_out_of_bounds_returns_index() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.option_values = PackedInt32Array([5, 7])
	# index 5 is beyond the array → return index
	assert_eq(menu._resolve_option_value(5), 5)
	menu.free()


func test_resolve_option_value_negative_index_returns_index() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.option_values = PackedInt32Array([5, 7])
	# negative idx should just be returned unchanged
	assert_eq(menu._resolve_option_value(-1), -1)
	menu.free()


# ---------------------------------------------------------------------------
# GameMenu._get_current_option_index — without a live scene
# ---------------------------------------------------------------------------

func test_get_current_option_index_no_config() -> void:
	var menu := GameMenuScript.new()
	# No config, no scene — must return 0 safely
	assert_eq(menu._get_current_option_index(), 0)
	menu.free()


func test_get_current_option_index_empty_button_name() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.option_button_unique_name = ""
	assert_eq(menu._get_current_option_index(), 0)
	menu.free()


func test_get_current_option_index_missing_node_returns_zero() -> void:
	var menu := GameMenuScript.new()
	menu.config = MenuConfigScript.new()
	menu.config.option_button_unique_name = "NonExistentButton"
	# Node not in scene — must return 0 gracefully
	assert_eq(menu._get_current_option_index(), 0)
	menu.free()


# ---------------------------------------------------------------------------
# Preloaded .tres config files — smoke-test the actual game configs
# ---------------------------------------------------------------------------

func test_sudoku_config_tres_is_valid() -> void:
	var cfg: MenuConfig = preload("res://assets/menu/sudoku_menu.tres")
	assert_not_null(cfg)
	assert_eq(cfg.game_id, "sudoku")
	assert_eq(cfg.display_name, "Sudoku")
	assert_true(cfg.has_save_support)
	assert_eq(cfg.option_button_unique_name, "DifficultyButton")
	assert_eq(cfg.option_default_index, 1)
	assert_true(cfg.start_game_passes_option)
	assert_false(cfg.start_game_passes_option_twice)
	assert_eq(cfg.abandon_stat_prefix, "abandoned_d")
	assert_eq(cfg.abandon_stat_save_key, "difficulty")
	assert_eq(cfg.title_color_key, "text_given")
	assert_false(cfg.game_rules.is_empty())


func test_shikaku_config_tres_is_valid() -> void:
	var cfg: MenuConfig = preload("res://assets/menu/shikaku_menu.tres")
	assert_not_null(cfg)
	assert_eq(cfg.game_id, "shikaku")
	assert_eq(cfg.display_name, "Shikaku")
	assert_true(cfg.has_save_support)
	assert_eq(cfg.option_button_unique_name, "SizeButton")
	assert_eq(cfg.option_default_index, 3)
	assert_eq(cfg.option_values.size(), 6)
	assert_eq(cfg.option_values[0], 5)
	assert_eq(cfg.option_values[3], 10)
	assert_true(cfg.start_game_passes_option)
	assert_true(cfg.start_game_passes_option_twice)
	assert_eq(cfg.abandon_stat_prefix, "abandoned_s")
	assert_eq(cfg.abandon_stat_save_key, "width")
	assert_eq(cfg.abandon_stat_default, 10)


func test_carom_config_tres_is_valid() -> void:
	var cfg: MenuConfig = preload("res://assets/menu/carom_menu.tres")
	assert_not_null(cfg)
	assert_eq(cfg.game_id, "carom")
	assert_eq(cfg.display_name, "Carom")
	assert_false(cfg.has_save_support)
	assert_eq(cfg.start_button_unique_name, "NewGameButton")
	assert_eq(cfg.option_button_unique_name, "DifficultyButton")
	assert_eq(cfg.option_default_index, 1)
	assert_eq(cfg.start_game_meta_key, "carom_difficulty")
	assert_eq(cfg.start_game_method, "")
	assert_false(cfg.start_game_passes_option)


func test_blockudoku_config_tres_is_valid() -> void:
	var cfg: MenuConfig = preload("res://assets/menu/blockudoku_menu.tres")
	assert_not_null(cfg)
	assert_eq(cfg.game_id, "blockudoku")
	assert_eq(cfg.display_name, "Blockudoku")
	assert_true(cfg.has_save_support)
	assert_eq(cfg.option_button_unique_name, "")
	assert_false(cfg.start_game_passes_option)
	assert_eq(cfg.start_game_method, "start_new_game")
	assert_false(cfg.game_rules.is_empty())
	assert_true(cfg.game_rules.get("pentominoes", false))


# ---------------------------------------------------------------------------
# Shikaku option-value mapping via preloaded config
# ---------------------------------------------------------------------------

func test_shikaku_resolve_option_value_index_3_gives_10() -> void:
	var menu := GameMenuScript.new()
	menu.config = preload("res://assets/menu/shikaku_menu.tres")
	assert_eq(menu._resolve_option_value(3), 10)
	menu.free()


func test_shikaku_resolve_option_value_index_0_gives_5() -> void:
	var menu := GameMenuScript.new()
	menu.config = preload("res://assets/menu/shikaku_menu.tres")
	assert_eq(menu._resolve_option_value(0), 5)
	menu.free()


func test_shikaku_resolve_option_value_index_5_gives_15() -> void:
	var menu := GameMenuScript.new()
	menu.config = preload("res://assets/menu/shikaku_menu.tres")
	assert_eq(menu._resolve_option_value(5), 15)
	menu.free()


# ---------------------------------------------------------------------------
# Sudoku option-value mapping (index == value, no option_values array)
# ---------------------------------------------------------------------------

func test_sudoku_resolve_option_value_index_is_value() -> void:
	var menu := GameMenuScript.new()
	menu.config = preload("res://assets/menu/sudoku_menu.tres")
	# option_values is empty for Sudoku — index is used directly
	for i in range(5):
		assert_eq(menu._resolve_option_value(i), i)
	menu.free()


# ---------------------------------------------------------------------------
# MenuConfig — leaderboard field defaults
# ---------------------------------------------------------------------------

func test_menu_config_default_leaderboard_modes_is_empty() -> void:
	var cfg := MenuConfigScript.new()
	assert_eq(cfg.leaderboard_modes.size(), 0)


func test_menu_config_default_leaderboard_is_time_based() -> void:
	var cfg := MenuConfigScript.new()
	assert_true(cfg.leaderboard_is_time_based)


func test_menu_config_stores_leaderboard_modes() -> void:
	var cfg := MenuConfigScript.new()
	cfg.leaderboard_modes = PackedStringArray(["easy", "medium", "hard", "expert", ""])
	assert_eq(cfg.leaderboard_modes.size(), 5)
	assert_eq(cfg.leaderboard_modes[0], "easy")
	assert_eq(cfg.leaderboard_modes[4], "")


func test_menu_config_stores_leaderboard_is_time_based_false() -> void:
	var cfg := MenuConfigScript.new()
	cfg.leaderboard_is_time_based = false
	assert_false(cfg.leaderboard_is_time_based)


# ---------------------------------------------------------------------------
# Leaderboard config in .tres files
# ---------------------------------------------------------------------------

func test_sudoku_config_leaderboard_modes() -> void:
	var cfg: MenuConfig = preload("res://assets/menu/sudoku_menu.tres")
	assert_eq(cfg.leaderboard_modes.size(), 5)
	assert_eq(cfg.leaderboard_modes[0], "easy")
	assert_eq(cfg.leaderboard_modes[1], "medium")
	assert_eq(cfg.leaderboard_modes[2], "hard")
	assert_eq(cfg.leaderboard_modes[3], "expert")
	assert_eq(cfg.leaderboard_modes[4], "")  # evil — no server leaderboard
	assert_true(cfg.leaderboard_is_time_based)


func test_shikaku_config_leaderboard_modes() -> void:
	var cfg: MenuConfig = preload("res://assets/menu/shikaku_menu.tres")
	assert_eq(cfg.leaderboard_modes.size(), 6)
	assert_eq(cfg.leaderboard_modes[0], "5")
	assert_eq(cfg.leaderboard_modes[1], "7")
	assert_eq(cfg.leaderboard_modes[2], "")   # 8×8 — no server leaderboard
	assert_eq(cfg.leaderboard_modes[3], "10")
	assert_eq(cfg.leaderboard_modes[4], "")   # 12×12 — no server leaderboard
	assert_eq(cfg.leaderboard_modes[5], "")   # 15×15 — no server leaderboard
	assert_true(cfg.leaderboard_is_time_based)


func test_blockudoku_config_leaderboard_modes() -> void:
	var cfg: MenuConfig = preload("res://assets/menu/blockudoku_menu.tres")
	assert_eq(cfg.leaderboard_modes.size(), 1)
	assert_eq(cfg.leaderboard_modes[0], "standard")
	assert_false(cfg.leaderboard_is_time_based)

