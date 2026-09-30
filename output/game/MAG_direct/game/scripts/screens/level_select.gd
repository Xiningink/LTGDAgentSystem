## Chamber index grouped by chapter, with progress and personal bests.
class_name LevelSelectScreen
extends Control

signal select_level(index: int)
signal back()

const COLUMNS := 4


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_build()
	Sfx.music("hum", -28.0)


func _build() -> void:
	add_child(Backdrop.new())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	column.add_child(_build_header())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 18)
	scroll.add_child(list)

	var chapters: Array = Levels.chapters()
	for chapter_index in range(chapters.size()):
		list.add_child(_build_chapter(chapter_index, chapters[chapter_index]))

	column.add_child(_build_footer())


func _build_header() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.12, 0.20), 16.0, true))
	panel.custom_minimum_size = Vector2(0, 78)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var back_button := UIKit.icon_button("<  TITLE", 15)
	back_button.pressed.connect(func(): Sfx.play("ui_back", -10.0); back.emit())
	row.add_child(_center(back_button))

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	title_box.add_child(UIKit.label("MAGNETICS DIVISION", 12, Palette.SWITCH))
	var title := UIKit.title("CHAMBER INDEX", 30, Palette.TEXT)
	title_box.add_child(title)
	row.add_child(_center(title_box))

	var cleared := 0
	for lvl in Levels.levels():
		if Save.is_cleared(String(lvl.get("id", ""))):
			cleared += 1
	var progress := VBoxContainer.new()
	progress.add_theme_constant_override("separation", 0)
	progress.add_child(UIKit.label("TAGGED", 11, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_RIGHT))
	progress.add_child(UIKit.label("%d / %d" % [cleared, Levels.count()], 24, Palette.EXIT, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_center(progress))

	var reset := UIKit.icon_button("WIPE SAVE", 13)
	reset.pressed.connect(func():
		Sfx.play("ui_deny", -8.0)
		Save.reset_progress()
		for child in get_children():
			child.queue_free()
		_build())
	row.add_child(_center(reset))

	return panel


func _build_chapter(chapter_index: int, chapter: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var color := Color(String(chapter.get("color", "#49e0d0")))

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	var chip := ColorRect.new()
	chip.color = color
	chip.custom_minimum_size = Vector2(38, 38)
	header.add_child(_center(chip))

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UIKit.label("CHAPTER %s" % String(chapter.get("code", "?")), 11, color))
	text.add_child(UIKit.label(String(chapter.get("name", "")), 22, Palette.TEXT))
	text.add_child(UIKit.label(String(chapter.get("blurb", "")), 12, Palette.TEXT_DIM))
	header.add_child(_center(text))

	var level_ids: Array = []
	for lvl in Levels.levels():
		if int(lvl.get("chapter", -1)) == chapter_index:
			level_ids.append(lvl)
	var done := 0
	for lvl in level_ids:
		if Save.is_cleared(String(lvl.get("id", ""))):
			done += 1
	var tally := UIKit.label("%d / %d" % [done, level_ids.size()], 18, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	tally.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tally.clip_text = true
	header.add_child(tally)
	box.add_child(header)

	var rule := ColorRect.new()
	rule.color = Color(color.r, color.g, color.b, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)

	for lvl in Levels.levels():
		if int(lvl.get("chapter", -1)) != chapter_index:
			continue
		var index := Levels.index_of_id(String(lvl.get("id", "")))
		var unlocked := Save.is_unlocked(index)
		var card := LevelCard.new()
		card.setup(index, lvl, unlocked, int(Save.best_moves.get(String(lvl.get("id", "")), -1)))
		card.pressed.connect(func():
			if unlocked:
				Sfx.play("ui_confirm", -8.0)
				select_level.emit(index)
			else:
				Sfx.play("ui_deny", -6.0))
		grid.add_child(card)

	return box


func _build_footer() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.07, 0.11, 0.18), 14.0, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)
	row.add_child(_clip(UIKit.label("STARS: CALCULATED FROM MOVES AGAINST THE CHAMBER PAR", 12, Palette.TEXT_DIM)))
	row.add_child(_clip(UIKit.label("SAME FIELD = REPEL    OPPOSITE FIELD = SWAP", 12, Palette.SWITCH)))
	row.add_child(_clip(UIKit.label("HAZARDS EAT MAGNETS - CRATES SHORT THEM OUT", 12, Palette.HAZARD)))
	return panel


func _clip(node: Label) -> Control:
	node.clip_text = true
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


func _center(node: Control) -> Control:
	var wrap := CenterContainer.new()
	wrap.add_child(node)
	return wrap


## Rebuild the whole index (cheap, and keeps progress fresh).
func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pm_menu"):
		Sfx.play("ui_back", -10.0)
		back.emit()
		get_viewport().set_input_as_handled()
