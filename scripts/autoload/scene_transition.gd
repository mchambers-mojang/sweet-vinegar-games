extends CanvasLayer

## Fade-to-black scene transition overlay.
## Usage:
##   SceneTransition.navigate("res://scenes/main_menu.tscn")
##   SceneTransition.navigate("res://scenes/game.tscn", func(s): s.start_new_game())
##   SceneTransition.push("res://scenes/settings.tscn")  # caller stays on stack
##   SceneTransition.pop()                               # restores previous scene

var _overlay: ColorRect
var _tween: Tween
const FADE_DURATION := 0.15
var _transitioning := false
var _initial_fade_pending := true

## Navigation stack — Node instances held alive off the scene tree.
var _nav_stack: Array[Node] = []


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
		get_tree().process_frame.connect(_initial_fade_in, CONNECT_ONE_SHOT)
	, CONNECT_ONE_SHOT)


## Navigate to target_path, fully replacing the current scene.
## SceneTransition always owns instantiation and scene lifecycle.
## The optional setup Callable receives the new scene instance before add_child,
## so any metadata set there is visible to _ready() on the new scene.
## Clears the navigation stack, freeing any stacked scenes.
func navigate(target_path: String, setup: Callable = Callable()) -> void:
	_do_navigate(func() -> Node: return load(target_path).instantiate(), setup, true)


## Push the current scene onto the navigation stack and navigate to target_path.
## The displaced scene is kept alive off the scene tree and restored by pop().
func push(target_path: String) -> void:
	_do_navigate(func() -> Node: return load(target_path).instantiate(), Callable(), false)


## Return to the previous scene on the navigation stack.
## Frees the current scene and re-attaches the scene at the top of the stack.
func pop() -> void:
	if _nav_stack.is_empty():
		push_warning("SceneTransition.pop() called with an empty navigation stack")
		return
	if _transitioning:
		return
	AppTheme.clear_screen_shake()
	_transitioning = true
	FeedbackManager.stop()
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.color = _get_fade_color(0.0)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_overlay, "color:a", 1.0, FADE_DURATION)
	_tween.tween_callback(func() -> void:
		var current := get_tree().current_scene
		var previous: Node = _nav_stack.pop_back()
		get_tree().root.add_child(previous)
		get_tree().current_scene = previous
		if current:
			current.queue_free()
		# Wait two frames so the restored scene fully renders behind the overlay
		get_tree().process_frame.connect(func() -> void:
			get_tree().process_frame.connect(_fade_in, CONNECT_ONE_SHOT)
		, CONNECT_ONE_SHOT)
	)


## Initial fade-in from _ready — skipped if a transition already started (e.g., first-boot redirect).
func _initial_fade_in() -> void:
	_initial_fade_pending = false
	if _transitioning:
		return
	_fade_in()


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


## Internal: fade out, swap scenes, fade in.
## factory creates the new scene Node; setup (optional) is called with the new
## Node before add_child so that metadata is visible to _ready(); free_old
## controls whether the old scene is freed (navigate) or pushed onto the
## navigation stack (push).
func _do_navigate(factory: Callable, setup: Callable, free_old: bool) -> void:
	if _transitioning:
		return
	AppTheme.clear_screen_shake()
	_transitioning = true
	HapticManager.stop()
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.color = _get_fade_color(0.0)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_overlay, "color:a", 1.0, FADE_DURATION)
	_tween.tween_callback(func() -> void:
		var old_scene := get_tree().current_scene
		var new_scene: Node = factory.call()
		if setup.is_valid():
			setup.call(new_scene)
		get_tree().root.add_child(new_scene)
		get_tree().current_scene = new_scene
		if free_old:
			for stacked in _nav_stack:
				stacked.queue_free()
			_nav_stack.clear()
			if old_scene:
				old_scene.queue_free()
		else:
			if old_scene:
				get_tree().root.remove_child(old_scene)
				_nav_stack.push_back(old_scene)
		# Wait two frames so the new scene fully initialises and renders behind the overlay
		get_tree().process_frame.connect(func() -> void:
			get_tree().process_frame.connect(_fade_in, CONNECT_ONE_SHOT)
		, CONNECT_ONE_SHOT)
	)
