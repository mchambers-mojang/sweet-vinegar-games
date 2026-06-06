extends Control

## Draws a line graph of game completion times.
## Lower times are better — the best time is highlighted.

var _times: Array = []
var _best_time: float = 0.0
var _average_time: float = 0.0


func _ready() -> void:
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: queue_redraw())


func set_times(times: Array) -> void:
	_times.clear()
	_best_time = 0.0
	var total := 0.0
	for raw_time in times:
		var t := float(raw_time)
		_times.append(t)
		total += t
		if _best_time == 0.0 or t < _best_time:
			_best_time = t
	_average_time = 0.0 if _times.is_empty() else total / float(_times.size())
	queue_redraw()


func _draw() -> void:
	var chart_rect := Rect2(16, 14, size.x - 32, size.y - 28)
	if chart_rect.size.x <= 1.0 or chart_rect.size.y <= 1.0:
		return

	var background_color := ThemeManager.get_color("cell_background")
	var border_color := ThemeManager.get_color("grid_line_thin")
	draw_rect(chart_rect, background_color)
	draw_rect(chart_rect, border_color, false, 1.0)

	if _times.is_empty():
		return

	var line_color := ThemeManager.get_color("text_placed")
	var best_color := Color(0.3, 0.9, 0.45, 1.0)
	var average_color := Color(0.95, 0.4, 0.4, 1.0)

	# Use max time as the top of the chart
	var max_time := _best_time
	for t in _times:
		max_time = maxf(max_time, float(t))
	max_time = maxf(max_time, 1.0)

	# Draw average line
	var average_ratio := clampf(_average_time / max_time, 0.0, 1.0)
	var average_y := chart_rect.position.y + chart_rect.size.y * average_ratio
	draw_line(
		Vector2(chart_rect.position.x, average_y),
		Vector2(chart_rect.end.x, average_y),
		average_color,
		1.5,
		true
	)

	# Draw data points (lower time = lower on chart = better)
	var points: PackedVector2Array = PackedVector2Array()
	var x_step := chart_rect.size.x / float(max(_times.size() - 1, 1))
	for i in _times.size():
		var time_ratio := clampf(float(_times[i]) / max_time, 0.0, 1.0)
		var x := chart_rect.position.x + float(i) * x_step
		var y := chart_rect.position.y + chart_rect.size.y * time_ratio
		points.append(Vector2(x, y))

	if points.size() == 1:
		draw_circle(points[0], 3.0, line_color)
	else:
		draw_polyline(points, line_color, 2.0, true)
		for point in points:
			draw_circle(point, 2.5, line_color)

	# Highlight best (lowest) time
	for i in _times.size():
		if absf(float(_times[i]) - _best_time) < 0.01:
			draw_circle(points[i], 4.5, best_color)
