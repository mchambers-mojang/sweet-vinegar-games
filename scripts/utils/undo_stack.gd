class_name UndoStack
extends RefCounted

## Generic undo/redo stack using Dictionary snapshots.
## Each game's logic layer owns one instance and defines its own snapshot format.

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


## Record a snapshot for undo and clear the redo history.
func push(snapshot: Dictionary) -> void:
	_undo.append(snapshot)
	_redo.clear()


## Pop the most recent undo snapshot, move it to the redo stack, and return it.
## Returns an empty dict if the undo stack is empty.
func undo() -> Dictionary:
	if _undo.is_empty():
		return {}
	var entry: Dictionary = _undo.pop_back()
	_redo.append(entry)
	return entry


## Replace the top of the redo stack with a custom snapshot.
## Use when the redo entry must differ from the undone entry — for example when
## the current state is captured at undo time (Sudoku cell-snapshot pattern).
func replace_redo_top(snapshot: Dictionary) -> void:
	if not _redo.is_empty():
		_redo[_redo.size() - 1] = snapshot


## Pop the most recent redo snapshot, move it to the undo stack, and return it.
## Returns an empty dict if the redo stack is empty.
func redo() -> Dictionary:
	if _redo.is_empty():
		return {}
	var entry: Dictionary = _redo.pop_back()
	_undo.append(entry)
	return entry


## Replace the top of the undo stack with a custom snapshot.
## Use when the undo entry must differ from the redone entry — for example when
## the current state is captured at redo time (Sudoku cell-snapshot pattern).
func replace_undo_top(snapshot: Dictionary) -> void:
	if not _undo.is_empty():
		_undo[_undo.size() - 1] = snapshot


## True if there is at least one undo entry available.
func can_undo() -> bool:
	return not _undo.is_empty()


## True if there is at least one redo entry available.
func can_redo() -> bool:
	return not _redo.is_empty()


## Number of undo entries.
func undo_size() -> int:
	return _undo.size()


## Number of redo entries.
func redo_size() -> int:
	return _redo.size()


## Clear both stacks (e.g. on game reset or new game).
func clear() -> void:
	_undo.clear()
	_redo.clear()


## Clear only the redo stack (e.g. a game-over path that invalidates redo
## without recording a new undo entry).
func clear_redo() -> void:
	_redo.clear()


## Return the internal undo entries array (for serialization).
func get_undo_entries() -> Array[Dictionary]:
	return _undo


## Return the internal redo entries array (for serialization).
func get_redo_entries() -> Array[Dictionary]:
	return _redo


## Replace internal stacks from deserialized data.
func load_entries(undo_entries: Array[Dictionary], redo_entries: Array[Dictionary]) -> void:
	_undo = undo_entries
	_redo = redo_entries
