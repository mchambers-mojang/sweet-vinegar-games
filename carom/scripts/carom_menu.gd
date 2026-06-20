class_name CaromMenu
extends GameMenu

## Carom menu — config-driven via assets/menu/carom_menu.tres
##
## Carom has no save support and uses a PlayButton instead of NewGameButton.
## It passes difficulty via set_meta("carom_difficulty", …) instead of a
## start_new_game() method.  All of this is expressed in the MenuConfig resource.

func _init() -> void:
	config = preload("res://assets/menu/carom_menu.tres")


func _ready() -> void:
	super._ready()
	var online_btn := get_node_or_null("MarginContainer/VBoxContainer/OnlineButton") as Button
	if online_btn:
		online_btn.pressed.connect(_on_online_pressed)


func _on_online_pressed() -> void:
	# Launch the arena in online mode.
	# The arena scene loads CaromOnlineMatchController instead of the
	# normal CaromMatchController when "carom_online" meta is set.
	SceneTransition.transition_with_callback(func() -> void:
		var arena_scene: Node = load(Scenes.CAROM_ARENA).instantiate()
		arena_scene.set_meta("carom_online", true)
		get_tree().root.add_child(arena_scene)
		queue_free()
	)
