class_name SudokuConstraint
extends RefCounted

## Abstract base class for Sudoku variant constraints.
## Implement this interface to add new rule sets (e.g. Anti-Knight, Anti-King, Diagonal).
## Instances are passed to SudokuLogic and SudokuGenerator to enforce variant rules.


## Unique string identifier for this constraint (e.g. "anti_knight").
## Used to serialise/deserialise the active rule set.
func get_id() -> String:
	return ""


## Returns true when placing val at index in the given grid does not violate this constraint.
## Called before the value is written to grid[index].
## grid[index] is still 0 (or the previous value) at call time.
func is_valid(grid: Array[int], index: int, val: int) -> bool:
	return true


## Returns all cell indices that a placement at index can conflict with under this constraint.
## Used by the solver (candidate pruning) and the game screen (error highlighting):
## any returned cell that already holds the same value as the placed digit is a conflict.
func get_affected_indices(index: int) -> Array[int]:
	return []
