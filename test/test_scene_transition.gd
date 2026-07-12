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
