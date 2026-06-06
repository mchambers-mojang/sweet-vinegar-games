extends CanvasLayer

## Manages WorldEnvironment for 2D bloom/glow effects
## Glow activates in Neon theme, deactivates in other themes

var _world_env: WorldEnvironment
var _environment: Environment


func _ready() -> void:
	layer = -1
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_CANVAS
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES

	# Glow settings for synthwave neon bloom
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.7
	_environment.glow_strength = 1.05
	_environment.glow_bloom = 0.25
	_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_environment.glow_hdr_threshold = 0.8
	_environment.glow_hdr_scale = 2.0
	# Multi-level glow for soft, wide bloom
	_environment.set_glow_level(0, true)   # Fine detail
	_environment.set_glow_level(1, true)   # Medium spread
	_environment.set_glow_level(2, true)   # Wide glow
	_environment.set_glow_level(3, false)
	_environment.set_glow_level(4, false)
	_environment.set_glow_level(5, false)
	_environment.set_glow_level(6, false)

	_world_env = WorldEnvironment.new()
	_world_env.environment = _environment
	# Don't add to tree unless neon is active — saves ~20-40MB on mobile
	ThemeManager.theme_changed.connect(func(_d: bool) -> void: _update_glow())
	_update_glow()


func _update_glow() -> void:
	if ThemeManager.is_neon:
		if not _world_env.is_inside_tree():
			add_child(_world_env)
	else:
		if _world_env.is_inside_tree():
			remove_child(_world_env)


## Create a screen-shake / impact effect
func screen_shake(intensity: float = 4.0, duration: float = 0.15) -> void:
	if not ThemeManager.is_neon:
		return
	if not SettingsManager.screen_shake_enabled:
		return
	var viewport := get_viewport()
	if not viewport:
		return
	var original := viewport.canvas_transform
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		var shake := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity)) * (1.0 - t)
		viewport.canvas_transform = Transform2D(0, shake) * original
	, 0.0, 1.0, duration)
	tween.tween_callback(func() -> void:
		viewport.canvas_transform = original
	)
