extends Control

## First-boot screen asking the player to choose a leaderboard display name.
## Shown once, before the Hub, when no display name has been saved.
## On completion, delegates to PlayerIdentity.complete_setup() and navigates to the Hub.

@onready var name_field: LineEdit = %NameField
@onready var visible_toggle: CheckButton = %VisibleToggle
@onready var continue_button: Button = %ContinueButton


func _ready() -> void:
	name_field.max_length = 20
	name_field.text_changed.connect(_on_name_changed)
	name_field.text_submitted.connect(func(_t: String) -> void: _on_continue())
	visible_toggle.button_pressed = true
	continue_button.disabled = true
	continue_button.pressed.connect(_on_continue)
	_apply_theme()
	AppTheme.theme_changed.connect(func(_d: bool) -> void: _apply_theme())


func _on_name_changed(text: String) -> void:
	continue_button.disabled = text.strip_edges().is_empty()


func _on_continue() -> void:
	var name_text := name_field.text.strip_edges()
	if name_text.is_empty():
		return
	PlayerIdentity.complete_setup(name_text, visible_toggle.button_pressed)
	PlayerIdentity.sync_profile()
	SceneTransition.transition_to(Scenes.GAME_PICKER)


func _apply_theme() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)
