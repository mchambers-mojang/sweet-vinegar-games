extends GutTest

const SHAKE_OVERLAP_DELAY_SEC := 0.04
const SHAKE_COMPLETION_WAIT_SEC := 0.25
const SHAKE_CANCEL_VERIFY_DELAY_SEC := 0.2

var _viewport: Viewport
var _original_mode: String
var _original_screen_shake_enabled: bool


func before_each() -> void:
	_viewport = AppTheme.get_viewport()
	_original_mode = PlatformSettings.dark_mode
	_original_screen_shake_enabled = PlatformSettings.screen_shake_enabled
	PlatformSettings.screen_shake_enabled = true
	AppTheme.set_theme_mode("neon")
	AppTheme.clear_screen_shake()


func after_each() -> void:
	AppTheme.clear_screen_shake()
	AppTheme.set_theme_mode(_original_mode)
	PlatformSettings.screen_shake_enabled = _original_screen_shake_enabled


func test_overlapping_screen_shakes_return_canvas_to_identity() -> void:
	assert_not_null(_viewport)
	AppTheme.screen_shake(5.0, 0.12)
	await get_tree().create_timer(SHAKE_OVERLAP_DELAY_SEC).timeout
	AppTheme.screen_shake(5.0, 0.12)
	await get_tree().create_timer(SHAKE_COMPLETION_WAIT_SEC).timeout
	assert_eq(_viewport.canvas_transform, Transform2D.IDENTITY)


func test_clear_screen_shake_resets_canvas_transform_to_identity() -> void:
	assert_not_null(_viewport)
	_viewport.canvas_transform = Transform2D(0, Vector2(32, -24))
	AppTheme.clear_screen_shake()
	assert_eq(_viewport.canvas_transform, Transform2D.IDENTITY)


func test_clear_screen_shake_cancels_active_shake() -> void:
	assert_not_null(_viewport)
	AppTheme.screen_shake(5.0, 0.4)
	AppTheme.clear_screen_shake()
	await get_tree().create_timer(SHAKE_CANCEL_VERIFY_DELAY_SEC).timeout
	assert_eq(_viewport.canvas_transform, Transform2D.IDENTITY)
