class_name SudokuGridSpec
extends RefCounted

## Immutable grid description used by generator, solver, logic, board, save, and replay.
## All grid-size-dependent code derives its constants from this object.

## Stable string identifier for this grid specification.
var id: String

## Width and height of the grid in cells.
var size: int

## Width of each region (box) in cells.
var region_w: int

## Height of each region (box) in cells.
var region_h: int

## Minimum symbol value (always 1).
var sym_min: int

## Maximum symbol value (= size).
var sym_max: int

## Total number of cells (= size * size).
var cell_count: int


## Standard 9×9 Sudoku with 3×3 regions — the default grid.
static var STANDARD_9X9: SudokuGridSpec = _make("standard_9x9", 9, 3, 3)

## Mini 6×6 Sudoku with 2×3 regions — one row tall, three columns wide per region.
static var MINI_6X6: SudokuGridSpec = _make("mini_6x6", 6, 3, 2)


static func _make(p_id: String, p_size: int, p_region_w: int, p_region_h: int) -> SudokuGridSpec:
	var s := SudokuGridSpec.new()
	s.id = p_id
	s.size = p_size
	s.region_w = p_region_w
	s.region_h = p_region_h
	s.sym_min = 1
	s.sym_max = p_size
	s.cell_count = p_size * p_size
	return s


## Return the SudokuGridSpec for the given stable ID, or null when unrecognised.
## A null result indicates a corrupt or unknown grid spec that cannot be resumed.
static func from_id(spec_id: String) -> SudokuGridSpec:
	match spec_id:
		"standard_9x9":
			return STANDARD_9X9
		"mini_6x6":
			return MINI_6X6
	return null
