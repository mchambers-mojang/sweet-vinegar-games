extends GutTest

## Unit tests for HelpContent resource loading and structure.

const GAMES: Array[String] = [
	"sudoku",
	"sudoku_anti_knight",
	"sudoku_anti_king",
	"sudoku_killer",
	"sudoku_mini",
	"shikaku",
	"shikaku_shapes",
	"blockudoku",
	"carom",
]


func _load(game_mode: String) -> HelpContent:
	return ResourceLoader.load("res://assets/help/%s_help.tres" % game_mode) as HelpContent


func test_all_help_resources_load() -> void:
	for game in GAMES:
		var content := _load(game)
		assert_not_null(content, "%s_help.tres should load as HelpContent" % game)


func test_all_help_resources_have_non_empty_title() -> void:
	for game in GAMES:
		var content := _load(game)
		assert_false(content.title.is_empty(), "%s help title should not be empty" % game)


func test_all_help_resources_have_non_empty_body() -> void:
	for game in GAMES:
		var content := _load(game)
		assert_false(content.body.is_empty(), "%s help body should not be empty" % game)


func test_sudoku_help_title_is_correct() -> void:
	assert_eq(_load("sudoku").title, "Sudoku")


func test_sudoku_variant_help_describes_special_rules() -> void:
	assert_string_contains(_load("sudoku_anti_knight").body, "knight's move")
	assert_string_contains(_load("sudoku_anti_king").body, "diagonally")
	assert_string_contains(_load("sudoku_killer").body, "cage")
	assert_string_contains(_load("sudoku_mini").body, "6×6")
	assert_string_contains(_load("shikaku_shapes").body, "shape")


func test_sudoku_menu_help_topic_tracks_selected_rule_set() -> void:
	var menu = load("res://scripts/sudoku/sudoku_main_menu.gd").new()
	menu._rule_set_index = menu.RULE_SET_ANTI_KNIGHT
	assert_eq(menu._get_help_topic(), "sudoku_anti_knight")
	menu._rule_set_index = menu.RULE_SET_ANTI_KING
	assert_eq(menu._get_help_topic(), "sudoku_anti_king")
	menu._rule_set_index = menu.RULE_SET_KILLER
	assert_eq(menu._get_help_topic(), "sudoku_killer")
	menu._rule_set_index = menu.RULE_SET_MINI
	assert_eq(menu._get_help_topic(), "sudoku_mini")
	menu.free()


func test_sudoku_game_help_topic_tracks_active_rule_set() -> void:
	var game = load("res://scripts/sudoku/sudoku_game_screen.gd").new()
	game.rule_set = game.RULE_SET_ANTI_KNIGHT
	assert_eq(game._get_help_topic(), "sudoku_anti_knight")
	game.rule_set = game.RULE_SET_ANTI_KING
	assert_eq(game._get_help_topic(), "sudoku_anti_king")
	game.rule_set = game.RULE_SET_KILLER
	assert_eq(game._get_help_topic(), "sudoku_killer")
	game.rule_set = game.RULE_SET_MINI
	assert_eq(game._get_help_topic(), "sudoku_mini")
	game.free()


func test_shikaku_help_topic_tracks_selected_mode() -> void:
	var menu = load("res://scripts/shikaku/shikaku_menu.gd").new()
	menu._mode_index = menu.MODE_STANDARD
	assert_eq(menu._get_help_topic(), "shikaku")
	menu._mode_index = menu.MODE_SHAPES
	assert_eq(menu._get_help_topic(), "shikaku_shapes")
	menu.free()

	var game = load("res://scripts/shikaku/shikaku_game_screen.gd").new()
	game.mode = ShikakuLogic.RULE_SET_SHAPES
	assert_eq(game._get_help_topic(), "shikaku_shapes")
	game.free()


func test_shikaku_help_title_is_correct() -> void:
	assert_eq(_load("shikaku").title, "Shikaku")


func test_blockudoku_help_title_is_correct() -> void:
	assert_eq(_load("blockudoku").title, "Blockudoku")


func test_carom_help_title_is_correct() -> void:
	assert_eq(_load("carom").title, "Carom")


func test_load_help_returns_null_for_unknown_game() -> void:
	var content := HowToPlay._load_help("nonexistent_game")
	assert_null(content, "Unknown game should return null")


func test_load_help_returns_content_for_known_game() -> void:
	var content := HowToPlay._load_help("sudoku")
	assert_not_null(content, "Known game should return a HelpContent resource")
