extends Control

const CATEGORY_ORDER: Array[String] = ["General", "Sudoku", "Blockudoku", "Shikaku"]
const TIER_ORDER := {"Bronze": 0, "Silver": 1, "Gold": 2}

@onready var back_button: Button = %BackButton
@onready var achievements_list: VBoxContainer = %AchievementsList

var _category_expanded: Dictionary = {
	"General": true,
	"Sudoku": true,
	"Blockudoku": true,
	"Shikaku": true,
}


func _ready() -> void:
	back_button.pressed.connect(func() -> void:
		SceneTransition.transition_to(Scenes.GAME_PICKER)
	)
	_build_ui()
	_apply_theme()
	AppTheme.theme_changed.connect(func(_dark: bool) -> void:
		_build_ui()
		_apply_theme()
	)
	AchievementManager.achievement_unlocked.connect(func(_achievement_id: String, _definition: Dictionary) -> void:
		_build_ui()
	)

	var margin: MarginContainer = get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		SafeAreaManager.apply(margin)


func _build_ui() -> void:
	for child in achievements_list.get_children():
		child.queue_free()

	var all_achievements: Array[Dictionary] = AchievementManager.get_achievement_snapshot()
	for category in CATEGORY_ORDER:
		var category_achievements: Array[Dictionary] = _get_category_achievements(all_achievements, category)
		if category_achievements.is_empty():
			continue
		_sort_achievements(category_achievements)
		_add_category_section(category, category_achievements)


func _get_category_achievements(all_achievements: Array[Dictionary], category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for achievement in all_achievements:
		if str(achievement.get("category", "General")) == category:
			result.append(achievement)
	return result


func _sort_achievements(achievements: Array[Dictionary]) -> void:
	achievements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var tier_a: int = int(TIER_ORDER.get(str(a.get("tier", "Bronze")), 0))
		var tier_b: int = int(TIER_ORDER.get(str(b.get("tier", "Bronze")), 0))
		if tier_a != tier_b:
			return tier_a < tier_b
		return str(a.get("id", "")) < str(b.get("id", ""))
	)


func _add_category_section(category: String, category_achievements: Array[Dictionary]) -> void:
	var unlocked_count: int = 0
	for achievement in category_achievements:
		if bool(achievement.get("unlocked", false)):
			unlocked_count += 1

	var expanded: bool = bool(_category_expanded.get(category, true))
	var header: Button = Button.new()
	header.text = "%s %s (%d/%d)" % ["▼" if expanded else "▶", category, unlocked_count, category_achievements.size()]
	header.flat = true
	header.custom_minimum_size = Vector2(0, 40)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", AppTheme.get_color("text_given"))
	header.pressed.connect(func() -> void:
		_toggle_category(category)
	)
	achievements_list.add_child(header)

	var section_margin: MarginContainer = MarginContainer.new()
	section_margin.add_theme_constant_override("margin_left", 10)
	section_margin.add_theme_constant_override("margin_bottom", 12)
	section_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	section_margin.visible = expanded
	achievements_list.add_child(section_margin)

	var section: VBoxContainer = VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	section.mouse_filter = Control.MOUSE_FILTER_PASS
	section_margin.add_child(section)

	for achievement in category_achievements:
		_add_achievement_row(section, achievement)


func _toggle_category(category: String) -> void:
	_category_expanded[category] = not bool(_category_expanded.get(category, true))
	_build_ui()


func _add_achievement_row(parent: VBoxContainer, achievement: Dictionary) -> void:
	var is_visible: bool = bool(achievement.get("is_visible", false))
	var unlocked: bool = bool(achievement.get("unlocked", false))
	var title_text: String = str(achievement.get("title", "")) if is_visible else "Hidden Achievement"
	var desc_text: String = str(achievement.get("description", "")) if is_visible else "Keep playing to reveal this achievement."
	var current: int = int(achievement.get("current_value", 0))
	var target: int = int(achievement.get("target_value", 1))

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 94)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(margin)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(content)

	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(header_row)

	var title: Label = Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	header_row.add_child(title)

	var badge: Label = Label.new()
	badge.text = "✓" if unlocked else str(achievement.get("tier", "Bronze"))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.add_theme_font_size_override("font_size", 14)
	badge.mouse_filter = Control.MOUSE_FILTER_PASS
	if unlocked:
		badge.add_theme_color_override("font_color", Color(0.3, 0.9, 0.45))
	header_row.add_child(badge)

	var desc: Label = Label.new()
	desc.text = desc_text
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 14)
	desc.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(desc)

	if unlocked:
		var unlocked_at: int = int(achievement.get("unlocked_at", 0))
		if unlocked_at > 0:
			var dt: Dictionary = Time.get_datetime_dict_from_unix_time(unlocked_at)
			var date_label: Label = Label.new()
			date_label.text = "%02d/%02d/%02d" % [
				int(dt.get("month", 1)),
				int(dt.get("day", 1)),
				int(dt.get("year", 2026)) % 100,
			]
			date_label.add_theme_font_size_override("font_size", 12)
			date_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			date_label.mouse_filter = Control.MOUSE_FILTER_PASS
			content.add_child(date_label)
	else:
		var progress: Label = Label.new()
		progress.text = "%d / %d" % [current, target]
		progress.add_theme_font_size_override("font_size", 12)
		progress.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		progress.mouse_filter = Control.MOUSE_FILTER_PASS
		content.add_child(progress)

	var reward_type: String = str(achievement.get("reward_type", ""))
	var reward_id: String = str(achievement.get("reward_id", ""))
	if reward_type != "" and reward_id != "":
		var reward: Label = Label.new()
		reward.text = "Reward: %s (%s)" % [reward_type, reward_id]
		reward.add_theme_color_override("font_color", AppTheme.get_color("timer_text"))
		reward.mouse_filter = Control.MOUSE_FILTER_PASS
		content.add_child(reward)


func _apply_theme() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = AppTheme.get_color("background")
	add_theme_stylebox_override("panel", style)
