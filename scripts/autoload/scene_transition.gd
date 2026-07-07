extends CanvasLayer

## Fade-to-black scene transition overlay.
## Usage:
##   SceneTransition.transition_to("res://scenes/main_menu.tscn")
##   SceneTransition.transition_with_callback(func(): ... )

var _overlay: ColorRect
var _tween: Tween
const FADE_DURATION := 0.15
var _transitioning := false


func _ready() -> void:
	layer = 100
	_overlay = ColorRect.new()
	# Start fully opaque so the first scene fades in cleanly
	_overlay.color = _get_fade_color(1.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _update_overlay_color())
	# Fade in after the first scene has had time to render
	get_tree().process_frame.connect(func() -> void:
		get_tree().process_frame.connect(_fade_in, CONNECT_ONE_SHOT)
	, CONNECT_ONE_SHOT)


## Fade out, change scene, fade in.
func transition_to(scene_path: String) -> void:
	transition_with_callback(func() -> void:
		get_tree().change_scene_to_file(scene_path)
	)


## Fade out, run a callback (for manual instantiate patterns), fade in.
## After the callback runs, the last non-autoload child of root is set as
## current_scene so that future change_scene_to_file calls free it properly.
func transition_with_callback(callback: Callable) -> void:
	if _transitioning:
		return
	_transitioning = true
	HapticManager.stop()
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.color = _get_fade_color(0.0)
	if _tween and _tween.is_valid():
		_tween.kill()
	# Fade to background color
	_tween = create_tween()
	_tween.tween_property(_overlay, "color:a", 1.0, FADE_DURATION)
	_tween.tween_callback(func() -> void:
		callback.call()
		_update_current_scene()
		# Wait two frames so the new scene fully initialises and renders behind the overlay
		get_tree().process_frame.connect(func() -> void:
			get_tree().process_frame.connect(_fade_in, CONNECT_ONE_SHOT)
		, CONNECT_ONE_SHOT)
	)


func _fade_in() -> void:
	_auto_apply_safe_area()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_overlay, "color:a", 0.0, FADE_DURATION)
	_tween.tween_callback(func() -> void:
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_transitioning = false
	)


## Auto-apply safe area to every scene root under the tree root.
## Skips nodes that set the "skip_safe_area" metadata flag to true.
## Safe to call on autoloads — they simply won't have a MarginContainer child.
func _auto_apply_safe_area() -> void:
	for child in get_tree().root.get_children():
		SafeAreaManager.apply_to_scene_root(child)


func _get_fade_color(alpha: float) -> Color:
	var bg := AppTheme.get_color("background")
	bg.a = alpha
	return bg


func _update_overlay_color() -> void:
	var a := _overlay.color.a
	_overlay.color = _get_fade_color(a)


## Set the last non-autoload child of root as current_scene so
## change_scene_to_file properly frees it on the next transition.
func _update_current_scene() -> void:
	var root := get_tree().root
	for i in range(root.get_child_count() - 1, -1, -1):
		var child := root.get_child(i)
		if child is CanvasLayer:
			continue
		if child == self:
			continue
		get_tree().current_scene = child
		return
