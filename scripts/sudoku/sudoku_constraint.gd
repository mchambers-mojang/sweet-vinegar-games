class_name SudokuConstraint
extends RefCounted

## Base class for Sudoku variant constraints.
##
## Subclasses implement one rule set (Anti-Knight, Anti-King, …).
## All methods are safe to call on an instance of this base class;
## the defaults are identity (always valid, no affected cells, empty id).


## Returns false when placing value at index would violate this constraint
## given the current grid state.  Called BEFORE the value is stored in the
## grid, so grid[index] is still 0 (or the previous value) at call time.
func is_valid(grid: Array[int], index: int, value: int) -> bool:
	return true


## Returns all cell indices that are constrained relative to index.
## Used for error-highlighting: after a placement at index the caller
## checks whether any of these cells already hold the same value.
func get_affected_indices(index: int) -> Array[int]:
	return []


## Unique string identifier used for serialisation (e.g. "anti_king").
func get_id() -> String:
	return ""
