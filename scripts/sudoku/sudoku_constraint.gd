class_name SudokuConstraint
extends RefCounted


func is_valid(_grid: Array[int], _index: int, _value: int) -> bool:
	return true


func get_affected_indices(_index: int) -> Array[int]:
	return []


func get_id() -> String:
	return ""
