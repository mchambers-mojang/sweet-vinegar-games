class_name AntiKingConstraint
extends SudokuConstraint

## Anti-King constraint: cells that are diagonally adjacent (a king's move
## in chess) cannot contain the same digit.  The four diagonal offsets are
## (±1,±1) — which, combined with the standard row/column rules, covers the
## full king's-move neighbourhood.

const DIAGONAL_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(-1, 1),
	Vector2i(1,  -1), Vector2i(1,  1),
]


func is_valid(grid: Array[int], index: int, value: int) -> bool:
	var row := index / 9
	var col := index % 9
	for offset in DIAGONAL_OFFSETS:
		var nr := row + offset.x
		var nc := col + offset.y
		if nr >= 0 and nr < 9 and nc >= 0 and nc < 9:
			if grid[nr * 9 + nc] == value:
				return false
	return true


func get_affected_indices(index: int) -> Array[int]:
	var row := index / 9
	var col := index % 9
	var result: Array[int] = []
	for offset in DIAGONAL_OFFSETS:
		var nr := row + offset.x
		var nc := col + offset.y
		if nr >= 0 and nr < 9 and nc >= 0 and nc < 9:
			result.append(nr * 9 + nc)
	return result


func get_id() -> String:
	return "anti_king"
