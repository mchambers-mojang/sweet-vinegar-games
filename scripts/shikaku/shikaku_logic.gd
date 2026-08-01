class_name ShikakuLogic
extends RefCounted

## Mode constants (carried through LaunchParams.rule_set)
const RULE_SET_STANDARD := 0
const RULE_SET_SHAPES := 1

## Shape constants — used in anchor dictionaries.
## SHAPE_ABSENT and SHAPE_ANY have identical validation semantics (any shape is
## accepted) but differ in presentation: ABSENT shows nothing, ANY shows "?" icon.
const SHAPE_ABSENT := 0
const SHAPE_ANY := 1
const SHAPE_SQUARE := 2  ## width == height
const SHAPE_TALL := 3    ## height > width
const SHAPE_WIDE := 4    ## width > height

const SHAPE_ICONS := {
	SHAPE_ABSENT: "",
	SHAPE_ANY: "?",
	SHAPE_SQUARE: "□",
	SHAPE_TALL: "↕",
	SHAPE_WIDE: "↔",
}

## Human-readable names for shape constants, used for accessible descriptions
## (tooltips, screen-reader text, stats, etc.).
const SHAPE_NAMES := {
	SHAPE_ABSENT: "",
	SHAPE_ANY: "Any shape",
	SHAPE_SQUARE: "Square",
	SHAPE_TALL: "Tall",
	SHAPE_WIDE: "Wide",
}

const LEGACY_SEED_HASH_INITIAL := 23
const LEGACY_SEED_HASH_MULTIPLIER := 31
const LEGACY_SEED_HASH_X_FACTOR := 7
const LEGACY_SEED_HASH_Y_FACTOR := 13
const MAX_HINTS_ALLOWED := 1

var grid_width: int = 0
var grid_height: int = 0
var mode: int = RULE_SET_STANDARD
## Primary clue storage: { Vector2i -> {area: int, shape: int} }
## area == 0: no area constraint; shape == SHAPE_ABSENT: no shape constraint.
## Every anchor must have area > 0 OR shape != SHAPE_ABSENT.
var anchors: Dictionary = {}
var solution: Array[Rect2i] = []
var placed_rects: Array[Rect2i] = []
var is_completed: bool = false
var hints_used: int = 0

var _undo_stack: UndoStack = UndoStack.new()

var undo_stack: Array[Dictionary]:
	get:
		return _undo_stack.get_undo_entries()

var redo_stack: Array[Dictionary]:
	get:
		return _undo_stack.get_redo_entries()

## Backward-compat property: returns area values for area-carrying anchors.
var numbers: Dictionary:
	get:
		var nums: Dictionary = {}
		for pos in anchors:
			var a: Dictionary = anchors[pos]
			var area: int = int(a.get("area", 0))
			if area > 0:
				nums[pos] = area
		return nums

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


func init_new_game(width: int, height: int, seed_value: int, p_mode: int = RULE_SET_STANDARD) -> void:
	grid_width = width
	grid_height = height
	mode = p_mode
	random_seed = seed_value
	_rng.seed = seed_value
	var generated: Dictionary = ShikakuGenerator.generate(width, height, seed_value, mode)
	anchors = generated.get("anchors", {})
	solution = generated.get("solution", [] as Array[Rect2i])
	placed_rects.clear()
	is_completed = false
	hints_used = 0
	_undo_stack.clear()


func init_from_save(data: Dictionary) -> void:
	grid_width = int(data.get("width", 10))
	grid_height = int(data.get("height", 10))
	mode = int(data.get("mode", RULE_SET_STANDARD))
	anchors = _deserialize_anchors(data)
	solution = _deserialize_rects(data.get("solution", []))
	placed_rects = _deserialize_rects(data.get("placed_rects", []))
	hints_used = int(data.get("hints_used", 0))
	var undo_entries := _deserialize_action_stack(data.get("undo_stack", []))
	var redo_entries := _deserialize_action_stack(data.get("redo_stack", []))
	_undo_stack.load_entries(undo_entries, redo_entries)
	random_seed = int(data.get("random_seed", 0))
	if random_seed == 0:
		random_seed = _derive_seed_from_anchors(anchors)
	_rng.seed = random_seed
	_recompute_completion()


func serialize() -> Dictionary:
	return {
		"width": grid_width,
		"height": grid_height,
		"mode": mode,
		"anchors": _serialize_anchors(anchors),
		"solution": _serialize_rects(solution),
		"placed_rects": _serialize_rects(placed_rects),
		"hints_used": hints_used,
		"is_completed": is_completed,
		"undo_stack": _serialize_action_stack(_undo_stack.get_undo_entries()),
		"redo_stack": _serialize_action_stack(_undo_stack.get_redo_entries()),
		"random_seed": random_seed,
	}


func place_rectangle(x: int, y: int, w: int, h: int) -> PlaceRectResult:
	var result: PlaceRectResult = PlaceRectResult.new()
	var rect := Rect2i(x, y, w, h)
	result.rect = _rect_to_dict(rect)
	if not _is_valid_placement(rect):
		return result
	placed_rects.append(rect)
	_undo_stack.push({"action": "place", "rect": result.rect.duplicate()})
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
			_undo_stack.push({"action": "remove", "rect": result.rect.duplicate()})
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
	if not _undo_stack.can_undo():
		return result
	var entry: Dictionary = _undo_stack.undo()
	var action_type := str(entry.get("action", ""))
	var rect_data: Dictionary = entry.get("rect", {})
	var rect: Rect2i = _dict_to_rect(rect_data)
	if action_type == "place":
		_remove_last_matching(rect)
	elif action_type == "remove":
		placed_rects.append(rect)
	else:
		return result
	_recompute_completion()
	result.action_type = action_type
	result.rect = rect_data.duplicate()
	return result


func redo() -> UndoRedoResult:
	var result: UndoRedoResult = UndoRedoResult.new()
	if not _undo_stack.can_redo():
		return result
	var entry: Dictionary = _undo_stack.redo()
	var action_type := str(entry.get("action", ""))
	var rect_data: Dictionary = entry.get("rect", {})
	var rect: Rect2i = _dict_to_rect(rect_data)
	if action_type == "place":
		placed_rects.append(rect)
	elif action_type == "remove":
		_remove_last_matching(rect)
	else:
		return result
	_recompute_completion()
	result.action_type = action_type
	result.rect = rect_data.duplicate()
	return result


func can_undo() -> bool:
	return not is_completed and _undo_stack.can_undo()


func can_redo() -> bool:
	return not is_completed and _undo_stack.can_redo()


func can_hint() -> bool:
	return not is_completed and hints_used < MAX_HINTS_ALLOWED


func get_unplaced_solution_rects() -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for rect in solution:
		if not _has_rect(rect):
			result.append(rect)
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


## Validate a candidate rectangle against anchor constraints.
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
	var anchor_count: int = 0
	for row in range(rect.position.y, rect.position.y + rect.size.y):
		for col in range(rect.position.x, rect.position.x + rect.size.x):
			var pos := Vector2i(col, row)
			if anchors.has(pos):
				anchor_count += 1
				if anchor_count > 1:
					return false
				var anchor: Dictionary = anchors[pos]
				var anchor_area: int = int(anchor.get("area", 0))
				var anchor_shape: int = int(anchor.get("shape", SHAPE_ABSENT))
				if anchor_area > 0 and anchor_area != area:
					return false
				if not _rect_matches_shape(rect, anchor_shape):
					return false
	if anchor_count != 1:
		return false
	return true


func _rect_matches_shape(rect: Rect2i, shape: int) -> bool:
	match shape:
		SHAPE_ABSENT, SHAPE_ANY:
			return true
		SHAPE_SQUARE:
			return rect.size.x == rect.size.y
		SHAPE_TALL:
			return rect.size.y > rect.size.x
		SHAPE_WIDE:
			return rect.size.x > rect.size.y
	return false


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
	is_completed = is_fully_covered() and ShikakuSolver.validate_anchors(grid_width, grid_height, anchors, placed_rects)


func _rect_to_dict(rect: Rect2i) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}


func _dict_to_rect(data: Dictionary) -> Rect2i:
	return Rect2i(int(data.get("x", 0)), int(data.get("y", 0)), int(data.get("w", 1)), int(data.get("h", 1)))


## Serialize anchors to { "col,row": {area, shape} }.
func _serialize_anchors(a: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for pos in a.keys():
		var cell: Vector2i = pos
		var anchor: Dictionary = a[pos]
		result["%d,%d" % [cell.x, cell.y]] = {
			"area": int(anchor.get("area", 0)),
			"shape": int(anchor.get("shape", SHAPE_ABSENT)),
		}
	return result


## Deserialize anchors from a save dict, supporting both new (anchors) and
## legacy (numbers) formats.
func _deserialize_anchors(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	# New format: anchors dict.
	var raw_anchors = data.get("anchors", null)
	if raw_anchors is Dictionary and not raw_anchors.is_empty():
		for key in raw_anchors.keys():
			var pos: Vector2i
			if key is Vector2i:
				pos = key
			else:
				var parts: PackedStringArray = str(key).split(",")
				if parts.size() != 2:
					continue
				pos = Vector2i(int(parts[0]), int(parts[1]))
			var entry = raw_anchors[key]
			if entry is Dictionary:
				result[pos] = {
					"area": int(entry.get("area", 0)),
					"shape": int(entry.get("shape", SHAPE_ABSENT)),
				}
			elif entry is int or entry is float:
				# Anchors dict stored as plain int (shouldn't happen, but be safe)
				result[pos] = {"area": int(entry), "shape": SHAPE_ABSENT}
		return result

	# Legacy format: numbers dict { "col,row": int }.
	var raw_numbers = data.get("numbers", null)
	if raw_numbers is Dictionary:
		for key in raw_numbers.keys():
			var pos: Vector2i
			if key is Vector2i:
				pos = key
			else:
				var parts: PackedStringArray = str(key).split(",")
				if parts.size() != 2:
					continue
				pos = Vector2i(int(parts[0]), int(parts[1]))
			result[pos] = {"area": int(raw_numbers[key]), "shape": SHAPE_ABSENT}
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


func _derive_seed_from_anchors(a: Dictionary) -> int:
	var keys: Array[Vector2i] = []
	for key in a.keys():
		keys.append(key)
	keys.sort_custom(func(av: Vector2i, bv: Vector2i) -> bool:
		if av.y == bv.y:
			return av.x < bv.x
		return av.y < bv.y
	)
	var seed := LEGACY_SEED_HASH_INITIAL
	for key in keys:
		var pos: Vector2i = key
		var anchor: Dictionary = a[pos]
		var area: int = int(anchor.get("area", 0))
		seed = int((seed * LEGACY_SEED_HASH_MULTIPLIER + pos.x * LEGACY_SEED_HASH_X_FACTOR + pos.y * LEGACY_SEED_HASH_Y_FACTOR + area) & 0x7fffffff)
	return seed
