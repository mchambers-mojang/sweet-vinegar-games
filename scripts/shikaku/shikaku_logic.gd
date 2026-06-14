class_name ShikakuLogic
extends RefCounted

const LEGACY_SEED_HASH_INITIAL := 23
const LEGACY_SEED_HASH_MULTIPLIER := 31
const LEGACY_SEED_HASH_X_FACTOR := 7
const LEGACY_SEED_HASH_Y_FACTOR := 13
const MAX_HINTS_ALLOWED := 1

var grid_width: int = 0
var grid_height: int = 0
var numbers: Dictionary = {}  # Vector2i -> int
var solution: Array[Rect2i] = []
var placed_rects: Array[Rect2i] = []
var is_completed: bool = false
var hints_used: int = 0
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var random_seed: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


class PlaceRectResult:
	var rect: Dictionary = {}
	var game_won: bool = false
	var valid: bool = false


class RemoveRectResult:
	var rect: Dictionary = {}
	var was_present: bool = false


class HintResult:
	var rect: Dictionary = {}
	var game_won: bool = false


class UndoRedoResult:
	var action_type: String = ""
	var rect: Dictionary = {}


func init_new_game(width: int, height: int, seed_value: int) -> void:
	grid_width = width
	grid_height = height
	random_seed = seed_value
	_rng.seed = seed_value
	var generated: Dictionary = ShikakuGenerator.generate(width, height, seed_value)
	numbers = generated.get("numbers", {})
	solution = generated.get("solution", [] as Array[Rect2i])
	placed_rects.clear()
	is_completed = false
	hints_used = 0
	undo_stack.clear()
	redo_stack.clear()


func init_from_save(data: Dictionary) -> void:
	grid_width = int(data.get("width", 10))
	grid_height = int(data.get("height", 10))
	numbers = _deserialize_numbers(data.get("numbers", {}))
	solution = _deserialize_rects(data.get("solution", []))
	placed_rects = _deserialize_rects(data.get("placed_rects", []))
	hints_used = int(data.get("hints_used", 0))
	undo_stack = _deserialize_action_stack(data.get("undo_stack", []))
	redo_stack = _deserialize_action_stack(data.get("redo_stack", []))
	random_seed = int(data.get("random_seed", 0))
	if random_seed == 0:
		random_seed = _derive_seed_from_numbers(numbers)
	_rng.seed = random_seed
	_recompute_completion()


func serialize() -> Dictionary:
	return {
		"width": grid_width,
		"height": grid_height,
		"numbers": _serialize_numbers(numbers),
		"solution": _serialize_rects(solution),
		"placed_rects": _serialize_rects(placed_rects),
		"hints_used": hints_used,
		"is_completed": is_completed,
		"undo_stack": _serialize_action_stack(undo_stack),
		"redo_stack": _serialize_action_stack(redo_stack),
		"random_seed": random_seed,
	}


func place_rectangle(x: int, y: int, w: int, h: int) -> PlaceRectResult:
	var result: PlaceRectResult = PlaceRectResult.new()
	var rect := Rect2i(x, y, w, h)
	result.rect = _rect_to_dict(rect)
	if not _is_valid_placement(rect):
		return result
	placed_rects.append(rect)
	undo_stack.append({"action": "place", "rect": result.rect.duplicate()})
	redo_stack.clear()
	result.valid = true
	_recompute_completion()
	result.game_won = is_completed
	return result


func remove_rectangle(x: int, y: int, w: int, h: int) -> RemoveRectResult:
	var result: RemoveRectResult = RemoveRectResult.new()
	var rect := Rect2i(x, y, w, h)
	result.rect = _rect_to_dict(rect)
	for i in range(placed_rects.size() - 1, -1, -1):
		if placed_rects[i] == rect:
			placed_rects.remove_at(i)
			undo_stack.append({"action": "remove", "rect": result.rect.duplicate()})
			redo_stack.clear()
			result.was_present = true
			break
	_recompute_completion()
	return result


func use_hint() -> HintResult:
	var result: HintResult = HintResult.new()
	if is_completed or hints_used >= MAX_HINTS_ALLOWED or solution.is_empty():
		return result
	var candidates: Array[Rect2i] = []
	for rect in solution:
		if not _has_rect(rect):
			candidates.append(rect)
	if candidates.is_empty():
		return result
	var picked: Rect2i = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var place_result: PlaceRectResult = place_rectangle(picked.position.x, picked.position.y, picked.size.x, picked.size.y)
	if not place_result.valid:
		return result
	hints_used += 1
	result.rect = place_result.rect
	result.game_won = place_result.game_won
	return result


func undo() -> UndoRedoResult:
	var result: UndoRedoResult = UndoRedoResult.new()
	if undo_stack.is_empty():
		return result
	var entry: Dictionary = undo_stack.pop_back()
	var action_type := str(entry.get("action", ""))
	var rect_data: Dictionary = entry.get("rect", {})
	var rect: Rect2i = _dict_to_rect(rect_data)
	if action_type == "place":
		_remove_last_matching(rect)
	elif action_type == "remove":
		placed_rects.append(rect)
	else:
		return result
	redo_stack.append({"action": action_type, "rect": rect_data.duplicate()})
	_recompute_completion()
	result.action_type = action_type
	result.rect = rect_data.duplicate()
	return result


func redo() -> UndoRedoResult:
	var result: UndoRedoResult = UndoRedoResult.new()
	if redo_stack.is_empty():
		return result
	var entry: Dictionary = redo_stack.pop_back()
	var action_type := str(entry.get("action", ""))
	var rect_data: Dictionary = entry.get("rect", {})
	var rect: Rect2i = _dict_to_rect(rect_data)
	if action_type == "place":
		placed_rects.append(rect)
	elif action_type == "remove":
		_remove_last_matching(rect)
	else:
		return result
	undo_stack.append({"action": action_type, "rect": rect_data.duplicate()})
	_recompute_completion()
	result.action_type = action_type
	result.rect = rect_data.duplicate()
	return result


func is_fully_covered() -> bool:
	if grid_width <= 0 or grid_height <= 0:
		return false
	for y in range(grid_height):
		for x in range(grid_width):
			if get_coverage_at(x, y) == 0:
				return false
	return true


func get_coverage_at(x: int, y: int) -> int:
	var count: int = 0
	var point := Vector2i(x, y)
	for rect in placed_rects:
		if rect.has_point(point):
			count += 1
	return count


func _is_valid_placement(rect: Rect2i) -> bool:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	if rect.position.x < 0 or rect.position.y < 0:
		return false
	if rect.position.x + rect.size.x > grid_width or rect.position.y + rect.size.y > grid_height:
		return false
	if _has_rect(rect):
		return false
	for row in range(rect.position.y, rect.position.y + rect.size.y):
		for col in range(rect.position.x, rect.position.x + rect.size.x):
			if get_coverage_at(col, row) > 0:
				return false
	var area := rect.size.x * rect.size.y
	var number_count: int = 0
	for row in range(rect.position.y, rect.position.y + rect.size.y):
		for col in range(rect.position.x, rect.position.x + rect.size.x):
			var pos := Vector2i(col, row)
			if numbers.has(pos):
				number_count += 1
				if int(numbers[pos]) != area:
					return false
	if number_count != 1:
		return false
	return true


func _has_rect(target: Rect2i) -> bool:
	for rect in placed_rects:
		if rect == target:
			return true
	return false


func _remove_last_matching(target: Rect2i) -> void:
	for i in range(placed_rects.size() - 1, -1, -1):
		if placed_rects[i] == target:
			placed_rects.remove_at(i)
			return


func _recompute_completion() -> void:
	is_completed = is_fully_covered() and ShikakuSolver.validate(grid_width, grid_height, numbers, placed_rects)


func _rect_to_dict(rect: Rect2i) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}


func _dict_to_rect(data: Dictionary) -> Rect2i:
	return Rect2i(int(data.get("x", 0)), int(data.get("y", 0)), int(data.get("w", 1)), int(data.get("h", 1)))


func _serialize_numbers(nums: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for pos in nums.keys():
		var cell: Vector2i = pos
		result["%d,%d" % [cell.x, cell.y]] = int(nums[pos])
	return result


func _deserialize_numbers(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in data.keys():
		if key is Vector2i:
			result[key] = int(data[key])
			continue
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() == 2:
			result[Vector2i(int(parts[0]), int(parts[1]))] = int(data[key])
	return result


func _serialize_rects(rects: Array[Rect2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rect in rects:
		result.append(_rect_to_dict(rect))
	return result


func _deserialize_rects(data: Variant) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	if data is Array:
		for entry in data:
			if entry is Rect2i:
				result.append(entry)
			elif entry is Dictionary:
				result.append(_dict_to_rect(entry))
	return result


func _serialize_action_stack(stack: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in stack:
		var rect_data: Dictionary = entry.get("rect", {})
		result.append({
			"action": str(entry.get("action", "")),
			"rect": rect_data.duplicate(),
		})
	return result


func _deserialize_action_stack(data: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				var rect_data: Dictionary = entry.get("rect", {})
				result.append({
					"action": str(entry.get("action", "")),
					"rect": rect_data.duplicate(),
				})
	return result


func _derive_seed_from_numbers(nums: Dictionary) -> int:
	var keys: Array[Vector2i] = []
	for key in nums.keys():
		keys.append(key)
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y
	)
	var seed := LEGACY_SEED_HASH_INITIAL
	for key in keys:
		var pos: Vector2i = key
		seed = int((seed * LEGACY_SEED_HASH_MULTIPLIER + pos.x * LEGACY_SEED_HASH_X_FACTOR + pos.y * LEGACY_SEED_HASH_Y_FACTOR + int(nums[pos])) & 0x7fffffff)
	return seed
