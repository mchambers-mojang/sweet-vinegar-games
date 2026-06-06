extends Control

@onready var back_button: Button = %BackButton
@onready var achievements_list: VBoxContainer = %AchievementsList


func _ready() -> void:
    back_button.pressed.connect(func() -> void:
        SceneTransition.transition_to("res://scenes/game_picker.tscn")
    )
    _build_ui()
    _apply_theme()
    ThemeManager.theme_changed.connect(func(_d: bool) -> void: _apply_theme())

    var margin := get_node_or_null("MarginContainer") as MarginContainer
    if margin:
        SafeAreaManager.apply(margin)


func _build_ui() -> void:
    for child in achievements_list.get_children():
        child.queue_free()

    var all_achievements: Array[Dictionary] = AchievementManager.get_achievement_snapshot()
    var last_tier := ""

    for achievement in all_achievements:
        var tier := str(achievement.get("tier", "Bronze"))
        if tier != last_tier:
            last_tier = tier
            _add_tier_header(tier)

        _add_achievement_row(achievement)


func _add_tier_header(tier: String) -> void:
    var header := Label.new()
    header.text = "%s Tier" % tier
    header.add_theme_font_size_override("font_size", 20)
    header.add_theme_color_override("font_color", ThemeManager.get_color("text_given"))
    achievements_list.add_child(header)


func _add_achievement_row(achievement: Dictionary) -> void:
    var is_visible := bool(achievement.get("is_visible", false))
    var unlocked := bool(achievement.get("unlocked", false))
    var title_text := str(achievement.get("title", "")) if is_visible else "Hidden Achievement"
    var desc_text := str(achievement.get("description", "")) if is_visible else "Keep playing to reveal this achievement."
    var current := int(achievement.get("current_value", 0))
    var target := int(achievement.get("target_value", 1))

    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(0, 94)
    panel.mouse_filter = Control.MOUSE_FILTER_PASS
    achievements_list.add_child(panel)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 12)
    margin.add_theme_constant_override("margin_top", 10)
    margin.add_theme_constant_override("margin_right", 12)
    margin.add_theme_constant_override("margin_bottom", 10)
    margin.mouse_filter = Control.MOUSE_FILTER_PASS
    panel.add_child(margin)

    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 6)
    content.mouse_filter = Control.MOUSE_FILTER_PASS
    margin.add_child(content)

    var header_row := HBoxContainer.new()
    content.add_child(header_row)

    var title := Label.new()
    title.text = title_text
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 18)
    header_row.add_child(title)

    var badge := Label.new()
    badge.text = "Unlocked" if unlocked else str(achievement.get("tier", "Bronze"))
    badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    if unlocked:
        badge.add_theme_color_override("font_color", Color(0.3, 0.9, 0.45))
    header_row.add_child(badge)

    var desc := Label.new()
    desc.text = desc_text
    desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    content.add_child(desc)

    var progress := Label.new()
    if unlocked:
        progress.text = "Complete"
    else:
        progress.text = "Progress: %d / %d" % [current, target]
    content.add_child(progress)

    var reward_type := str(achievement.get("reward_type", ""))
    var reward_id := str(achievement.get("reward_id", ""))
    if reward_type != "" and reward_id != "":
        var reward := Label.new()
        reward.text = "Reward: %s (%s)" % [reward_type, reward_id]
        reward.add_theme_color_override("font_color", ThemeManager.get_color("timer_text"))
        content.add_child(reward)


func _apply_theme() -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = ThemeManager.get_color("background")
    add_theme_stylebox_override("panel", style)
