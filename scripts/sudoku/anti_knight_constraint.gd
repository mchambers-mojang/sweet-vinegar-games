class_name AntiKnightConstraint
extends SudokuConstraint

## Anti-Knight Sudoku constraint: cells that are a chess knight's move apart
## cannot contain the same digit.
##
## A chess knight moves in an L-shape: two squares in one direction and one
## square perpendicular (or vice versa).  From any cell there are up to 8
## such reachable cells; cells near the border have fewer.

## All 8 possible knight-move (row_delta, col_delta) offsets.
const KNIGHT_OFFSETS: Array = [
	[-2, -1], [-2, 1],
	[-1, -2], [-1, 2],
	[ 1, -2], [ 1, 2],
	[ 2, -1], [ 2, 1],
]


func get_id() -> String:
	return "anti_knight"


## Returns true when no knight-reachable cell already contains val.
func is_valid(grid: Array[int], index: int, val: int) -> bool:
	for idx in get_affected_indices(index):
		if grid[idx] == val:
			return false
	return true


## Returns the (up to 8) cell indices reachable from index by a knight move.
func get_affected_indices(index: int) -> Array[int]:
	var row := index / 9
	var col := index % 9
	var result: Array[int] = []
	for offset in KNIGHT_OFFSETS:
		var nr: int = row + offset[0]
		var nc: int = col + offset[1]
		if nr >= 0 and nr < 9 and nc >= 0 and nc < 9:
			result.append(nr * 9 + nc)
	return result
