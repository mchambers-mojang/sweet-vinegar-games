class_name GameRegistry

## Central registry of all games available in the Hub.
## To add a new game: create a GameEntry .tres and add it to ENTRIES below.
## The Hub (game_picker.gd) reads ENTRIES at startup and generates buttons
## dynamically — no edits to game_picker.gd are needed.

static var ENTRIES: Array[GameEntry] = [
	preload("res://assets/menu/sudoku_entry.tres"),
	preload("res://assets/menu/shikaku_entry.tres"),
	preload("res://assets/menu/blockudoku_entry.tres"),
	preload("res://assets/menu/carom_entry.tres"),
]

