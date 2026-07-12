class_name CaromMenu
extends GameMenu

## Carom menu — config-driven via assets/menu/carom_menu.tres
##
## Carom has no save support and uses a NewGameButton.
## The online button launches the arena in online mode by passing
## LaunchParams(online=true) to CaromArena.launch().

func _init() -> void:
	config = preload("res://assets/menu/carom_menu.tres")


func _ready() -> void:
	super._ready()
	var online_btn := get_node_or_null("MarginContainer/VBoxContainer/OnlineButton") as Button
	if online_btn:
		online_btn.pressed.connect(_on_online_pressed)


func _on_online_pressed() -> void:
	var params := LaunchParams.new()
	params.online = true
	SceneTransition.transition_with_callback(func() -> void:
		var arena_scene: Node = load(Scenes.CAROM_ARENA).instantiate()
		get_tree().root.add_child(arena_scene)
		arena_scene.launch(params)
		queue_free()
	)
