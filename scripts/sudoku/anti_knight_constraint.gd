class_name AntiKnightConstraint
extends SudokuConstraint

## Anti-Knight constraint: cells a chess knight's move apart cannot share
## the same digit.  The eight knight-move offsets are (±1,±2) and (±2,±1).

const KNIGHT_OFFSETS: Array[Vector2i] = [
	Vector2i(-2, -1), Vector2i(-2, 1),
	Vector2i(-1, -2), Vector2i(-1, 2),
	Vector2i(1,  -2), Vector2i(1,  2),
	Vector2i(2,  -1), Vector2i(2,  1),
]


func is_valid(grid: Array[int], index: int, value: int) -> bool:
	var row := index / 9
	var col := index % 9
	for offset in KNIGHT_OFFSETS:
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
	for offset in KNIGHT_OFFSETS:
		var nr := row + offset.x
		var nc := col + offset.y
		if nr >= 0 and nr < 9 and nc >= 0 and nc < 9:
			result.append(nr * 9 + nc)
	return result


func get_id() -> String:
	return "anti_knight"
