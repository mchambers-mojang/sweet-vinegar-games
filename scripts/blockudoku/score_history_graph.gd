extends Control

var _scores: Array = []
var _best_score: int = 0
var _average_score: float = 0.0


func _ready() -> void:
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: queue_redraw())


func set_scores(scores: Array) -> void:
	_scores.clear()
	_best_score = 0
	var total := 0
	for raw_score in scores:
		var score := int(raw_score)
		_scores.append(score)
		total += score
		_best_score = maxi(_best_score, score)
	_average_score = 0.0 if _scores.is_empty() else float(total) / float(_scores.size())
	queue_redraw()


func _draw() -> void:
	var chart_rect := Rect2(16, 14, size.x - 32, size.y - 28)
	if chart_rect.size.x <= 1.0 or chart_rect.size.y <= 1.0:
		return

	var background_color := ThemeManager.get_color("cell_background")
	var border_color := ThemeManager.get_color("grid_line_thin")
	draw_rect(chart_rect, background_color)
	draw_rect(chart_rect, border_color, false, 1.0)

	if _scores.is_empty():
		return

	var line_color := ThemeManager.get_color("text_placed")
	var best_color := Color(1.0, 0.85, 0.2, 1.0)
	var average_color := Color(0.95, 0.4, 0.4, 1.0)
	var max_score := maxi(_best_score, 1)

	var average_ratio := clampf(_average_score / float(max_score), 0.0, 1.0)
	var average_y := chart_rect.position.y + chart_rect.size.y * (1.0 - average_ratio)
	draw_line(
		Vector2(chart_rect.position.x, average_y),
		Vector2(chart_rect.end.x, average_y),
		average_color,
		1.5,
		true
	)

	var points: PackedVector2Array = PackedVector2Array()
	var x_step := chart_rect.size.x / float(max(_scores.size() - 1, 1))
	for i in _scores.size():
		var score_ratio := clampf(float(_scores[i]) / float(max_score), 0.0, 1.0)
		var x := chart_rect.position.x + float(i) * x_step
		var y := chart_rect.position.y + chart_rect.size.y * (1.0 - score_ratio)
		points.append(Vector2(x, y))

	if points.size() == 1:
		draw_circle(points[0], 3.0, line_color)
	else:
		draw_polyline(points, line_color, 2.0, true)
		for point in points:
			draw_circle(point, 2.5, line_color)

	for i in _scores.size():
		if _scores[i] == _best_score:
			draw_circle(points[i], 4.5, best_color)
