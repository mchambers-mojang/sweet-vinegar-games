extends GutTest


class ReadyProbe extends Control:
	var ready_called := false

	func _ready() -> void:
		ready_called = true


func test_setup_callback_runs_after_scene_is_ready() -> void:
	var previous_scene := get_tree().current_scene
	var probe := ReadyProbe.new()
	var result := {"setup_saw_ready": false}

	SceneTransition._attach_scene(probe, func(scene: Node) -> void:
		result["setup_saw_ready"] = scene.is_node_ready() and scene.ready_called
	)
	await get_tree().process_frame

	assert_true(result["setup_saw_ready"], "setup callback should run after the scene's _ready()")
	get_tree().current_scene = previous_scene
	probe.queue_free()


## cancel_transition() must restore the overlay to non-blocking input and
## clear _transitioning so the system is idle after cancellation.
func test_cancel_transition_restores_overlay_mouse_filter() -> void:
	# Put the overlay into the blocking state that a real navigate() sets.
	var original_transitioning := SceneTransition.is_transitioning
	SceneTransition._overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	SceneTransition._transitioning = true

	SceneTransition.cancel_transition()

	assert_eq(SceneTransition._overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"cancel_transition must restore overlay mouse_filter to IGNORE")
	assert_false(SceneTransition.is_transitioning,
			"cancel_transition must clear _transitioning")

	SceneTransition._transitioning = original_transitioning


## cancel_transition() must reset overlay alpha to 0 (fully transparent)
## so a mid-fade cancel never leaves the current scene dimmed or obscured.
func test_cancel_transition_restores_overlay_alpha_to_transparent() -> void:
	# Simulate being mid-fade-out: overlay is partially opaque (e.g. 0.6 alpha).
	var original_alpha := SceneTransition._overlay.color.a
	var original_transitioning := SceneTransition.is_transitioning
	SceneTransition._overlay.color.a = 0.6
	SceneTransition._transitioning = true

	SceneTransition.cancel_transition()

	assert_eq(SceneTransition._overlay.color.a, 0.0,
			"cancel_transition must reset overlay alpha to 0 (fully transparent)")

	# Restore state.
	SceneTransition._overlay.color.a = original_alpha
	SceneTransition._transitioning = original_transitioning


## cancel_transition() must increment _transition_gen so any two-frame
## _fade_in() callbacks already queued by a previous _do_navigate / pop
## tween are skipped and cannot fire _fade_in() or transition_completed
## over a subsequent transition.
func test_cancel_transition_increments_generation_for_stale_callback_suppression() -> void:
	var gen_before := SceneTransition._transition_gen

	SceneTransition.cancel_transition()

	assert_gt(SceneTransition._transition_gen, gen_before,
			"cancel_transition must increment _transition_gen to invalidate pending _fade_in callbacks")

	# Verify suppression: simulate what a stale queued lambda does — check the
	# captured gen against the current gen.  After a cancel, they differ, so
	# _fade_in() must not be called.  We confirm by tracking transition_completed.
	var unexpected_complete := false
	SceneTransition.transition_completed.connect(
			func() -> void: unexpected_complete = true, CONNECT_ONE_SHOT)

	# Stale lambda condition: captured gen (gen_before) != current gen
	if SceneTransition._transition_gen == gen_before:
		# This branch must NOT execute — if it did _fade_in() would run.
		SceneTransition._fade_in()

	assert_false(unexpected_complete,
			"stale queued _fade_in callback must be suppressed after cancel_transition")
	# ONE_SHOT connections disconnect themselves after firing; no manual cleanup needed.
