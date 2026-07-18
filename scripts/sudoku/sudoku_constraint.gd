class_name SudokuConstraint
extends RefCounted

## Base class for composable Sudoku variant constraints.
## Subclass and override the three methods to implement any variant rule
## (Anti-Knight, Anti-King, Killer, etc.).
## An empty constraints array reproduces standard Sudoku behaviour exactly.


## Returns whether placing value at index is legal under this constraint.
## grid contains the current board state (0 for empty cells); index is the
## target cell; value is the candidate digit (1–9).
func is_valid(grid: Array[int], index: int, value: int) -> bool:
	return true


## Returns the indices that this constraint links to index.
## Used by the UI for error-highlighting when a violation is detected.
func get_affected_indices(index: int) -> Array[int]:
	return []


## Unique string identifier used for serialisation.
func get_id() -> String:
	return ""
