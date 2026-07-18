class_name LaunchParams
extends Resource

## Typed launch parameters passed from a game menu to a game screen.
##
## Construct one instance (or let MenuConfig.build_launch_params() build it)
## and pass it to game_scene.launch(params) to start a new game.
##
## Replaces the start_game_method / start_game_passes_option /
## start_game_passes_option_twice / start_game_meta_key matrix in MenuConfig,
## and the carom_online meta that CaromMenu set via set_meta().

## Integer option value resolved from the menu's option dropdown
## (e.g. difficulty for Sudoku, grid size for Shikaku).
## 0 when the game has no option dropdown.
@export var option_value: int = 0

## When true, launch Carom in online multiplayer mode.
## Replaces the "carom_online" metadata key.
@export var online: bool = false

## Rule-set index for games that support variant rules (e.g. Sudoku Anti-Knight/Anti-King).
## 0 = standard rules; non-zero values are game-defined.
## Defaults to 0 so existing callers that do not set it get standard behaviour.
@export var rule_set: int = 0
