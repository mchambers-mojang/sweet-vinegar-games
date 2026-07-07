class_name MenuConfig
extends Resource

## Declarative configuration resource for GameMenu.
## Create one .tres per game and assign it to GameMenu.config.
## GameMenu reads all fields here; per-game subclasses reduce to a single
## _init() that preloads the resource.

# --- Identity ---

## Unique game identifier (matches GameSaveManager / GameStatsManager keys).
@export var game_id: String = ""

## Title shown in the menu.
@export var display_name: String = ""

## HowToPlay topic key. Empty = no How to Play button.
@export var help_topic: String = ""

# --- Scene paths ---

## Scene path for this menu (used as the Settings return target).
@export var menu_scene_path: String = ""

## Scene path for the game scene to launch.
@export var game_scene_path: String = ""

## Scene path for the stats screen. Empty = no statistics button.
@export var stats_scene_path: String = ""

# --- Save / continue flow ---

## Whether this menu offers a save-and-continue flow.
## Set false for games with no persistent save (e.g. Carom).
@export var has_save_support: bool = true

# --- Button wiring ---

## Unique-name of the start button in the scene tree.
## Defaults to "NewGameButton" (the button in scenes/components/base_menu.tscn).
## Set to "PlayButton" for menus that use a different label (e.g. Carom).
@export var start_button_unique_name: String = "NewGameButton"

# --- Option dropdown (difficulty / grid-size / etc.) ---

## Unique-name of the optional OptionButton node. Empty = no option dropdown.
@export var option_button_unique_name: String = ""

## Default selected index for the option button.
@export var option_default_index: int = 0

## Integer values mapped from the option index.
## If empty the selected index itself is used as the value.
## e.g. Shikaku grid sizes: PackedInt32Array(5, 7, 8, 10, 12, 15)
@export var option_values: PackedInt32Array = PackedInt32Array()

# --- Game-scene launch ---

## Method to call on the game scene node when starting a new game.
## Leave empty when no method call is needed (use start_game_meta_key only).
@export var start_game_method: String = "start_new_game"

## When true, the resolved option value is passed as the first argument
## to start_game_method.
@export var start_game_passes_option: bool = false

## When true, the resolved option value is passed as BOTH the first and
## second argument (used for Shikaku where width == height == grid_size).
@export var start_game_passes_option_twice: bool = false

## When non-empty, set_meta(start_game_meta_key, option_value) is called on
## the game scene before adding it to the tree.
## Used for Carom, which reads difficulty via get_meta("carom_difficulty").
@export var start_game_meta_key: String = ""

# --- Abandon stats ---

## Key looked up in the save Dictionary to obtain the game-variant identifier
## (e.g. "difficulty" for Sudoku, "width" for Shikaku).
@export var abandon_stat_save_key: String = ""

## Prefix for the abandon stat counter key.
## The full key is abandon_stat_prefix + str(variant_value).
## e.g. "abandoned_d" → "abandoned_d2" for difficulty 2.
@export var abandon_stat_prefix: String = ""

## Fallback value used when abandon_stat_save_key is absent from save data.
@export var abandon_stat_default: int = 0

# --- Theme ---

## AppTheme color key applied to the TitleLabel font color.
## Empty = no override (the label keeps its default color).
## e.g. "text_given" for the Sudoku menu.
@export var title_color_key: String = ""

# --- Game rules ---

## Default game rules registered with GameRulesRegistry on menu load.
## The registry ignores duplicate registrations, so this is safe to call
## on every menu visit.
@export var game_rules: Dictionary = {}

# --- Leaderboard ---

## Server mode strings, indexed to match the option dropdown.
## Empty string at a given index means no leaderboard for that option.
## For games with no option dropdown (e.g. Blockudoku), provide one entry.
## e.g. for Sudoku: PackedStringArray("easy", "medium", "hard", "expert", "")
@export var leaderboard_modes: PackedStringArray = PackedStringArray()

## True for time-based leaderboards (values are seconds; display as MM:SS.cc).
## False for score-based leaderboards (plain integers, descending).
@export var leaderboard_is_time_based: bool = true
