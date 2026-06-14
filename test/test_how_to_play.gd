extends GutTest

## Unit tests for HelpContent resource loading and structure.

const GAMES: Array[String] = ["sudoku", "shikaku", "blockudoku", "carom"]


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
