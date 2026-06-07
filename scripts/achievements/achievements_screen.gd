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
    header.mouse_filter = Control.MOUSE_FILTER_PASS
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
    header_row.mouse_filter = Control.MOUSE_FILTER_PASS
    content.add_child(header_row)

    var title := Label.new()
    title.text = title_text
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 18)
    title.mouse_filter = Control.MOUSE_FILTER_PASS
    header_row.add_child(title)

    var badge := Label.new()
    badge.text = "✓" if unlocked else str(achievement.get("tier", "Bronze"))
    badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    badge.add_theme_font_size_override("font_size", 14)
    badge.mouse_filter = Control.MOUSE_FILTER_PASS
    if unlocked:
        badge.add_theme_color_override("font_color", Color(0.3, 0.9, 0.45))
    header_row.add_child(badge)

    var desc := Label.new()
    desc.text = desc_text
    desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    desc.add_theme_font_size_override("font_size", 14)
    desc.mouse_filter = Control.MOUSE_FILTER_PASS
    content.add_child(desc)

    if unlocked:
        var unlocked_at := int(achievement.get("unlocked_at", 0))
        if unlocked_at > 0:
            var dt := Time.get_datetime_dict_from_unix_time(unlocked_at)
            var date_label := Label.new()
            date_label.text = "%02d/%02d/%02d" % [
                int(dt.get("month", 1)),
                int(dt.get("day", 1)),
                int(dt.get("year", 2026)) % 100
            ]
            date_label.add_theme_font_size_override("font_size", 12)
            date_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
            date_label.mouse_filter = Control.MOUSE_FILTER_PASS
            content.add_child(date_label)
    else:
        var progress := Label.new()
        progress.text = "%d / %d" % [current, target]
        progress.add_theme_font_size_override("font_size", 12)
        progress.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
        progress.mouse_filter = Control.MOUSE_FILTER_PASS
        content.add_child(progress)

    var reward_type := str(achievement.get("reward_type", ""))
    var reward_id := str(achievement.get("reward_id", ""))
    if reward_type != "" and reward_id != "":
        var reward := Label.new()
        reward.text = "Reward: %s (%s)" % [reward_type, reward_id]
        reward.add_theme_color_override("font_color", ThemeManager.get_color("timer_text"))
        reward.mouse_filter = Control.MOUSE_FILTER_PASS
        content.add_child(reward)


func _apply_theme() -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = ThemeManager.get_color("background")
    add_theme_stylebox_override("panel", style)


func _month_name(month: int) -> String:
    var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    if month >= 1 and month <= 12:
        return months[month - 1]
    return "???"
