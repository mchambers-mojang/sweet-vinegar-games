extends GutTest

const TimeFormat := preload("res://scripts/utils/time_format.gd")

func test_format_time_without_centiseconds_uses_mm_ss() -> void:
	assert_eq(TimeFormat.format_time(0.0), "00:00")
	assert_eq(TimeFormat.format_time(61.9), "01:01")
	assert_eq(TimeFormat.format_time(222.17), "03:42")


func test_format_time_with_centiseconds_uses_mm_ss_cc() -> void:
	assert_eq(TimeFormat.format_time(0.0, true), "00:00.00")
	assert_eq(TimeFormat.format_time(61.9, true), "01:01.90")
	assert_eq(TimeFormat.format_time(222.17, true), "03:42.17")


func test_format_time_clamps_negative_values_to_zero() -> void:
	assert_eq(TimeFormat.format_time(-3.2), "00:00")
	assert_eq(TimeFormat.format_time(-3.2, true), "00:00.00")
