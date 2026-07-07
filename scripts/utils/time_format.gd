class_name TimeFormat

static func format_time(seconds: float, show_centiseconds: bool = false) -> String:
	var clamped_seconds := maxf(0.0, seconds)
	if show_centiseconds:
		var total_centiseconds := int(clamped_seconds * 100.0)
		var mins := total_centiseconds / 6000
		var secs := (total_centiseconds / 100) % 60
		var centiseconds := total_centiseconds % 100
		return "%02d:%02d.%02d" % [mins, secs, centiseconds]
	var total_seconds := int(clamped_seconds)
	var mins := total_seconds / 60
	var secs := total_seconds % 60
	return "%02d:%02d" % [mins, secs]
