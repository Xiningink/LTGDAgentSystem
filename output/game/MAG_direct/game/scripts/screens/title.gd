## Front door: animated dipole field, logo lockup and the main menu.
class_name TitleScreen
extends Control

signal start_game(index: int)
signal open_index()
signal open_help()
signal quit_game()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_build()
	Sfx.music("hum", -26.0)


func _build() -> void:
	add_child(Backdrop.new())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 34)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	# --- hero ------------------------------------------------------------
	var hero := Control.new()
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero.custom_minimum_size = Vector2(0, 320)
	column.add_child(hero)

	var art := FieldArt.new()
	art.focus = Vector2(0.5, 0.34)
	art.pole_gap = 0.13
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	hero.add_child(art)

	var title_box := VBoxContainer.new()
	title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_box.anchor_top = 0.50
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 2)
	hero.add_child(title_box)

	var overline := UIKit.label("LTGD  MAGNETICS  DIVISION  /  CHAMBER  SERIES  I", 12, Palette.SWITCH, HORIZONTAL_ALIGNMENT_CENTER)
	overline.modulate = Color(1, 1, 1, 0.75)
	title_box.add_child(overline)

	var title := UIKit.title("PUZZLE MAGNET LAB", 62, Palette.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.09, 0.9))
	title_box.add_child(title)

	var subtitle := UIKit.label("A TURN-BASED MAGNETIC LOGIC PUZZLE", 17, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	title_box.add_child(subtitle)

	var rule := ColorRect.new()
	rule.color = Color(Palette.SWITCH.r, Palette.SWITCH.g, Palette.SWITCH.b, 0.45)
	rule.custom_minimum_size = Vector2(0, 2)
	title_box.add_child(rule)

	# --- menu ------------------------------------------------------------
	var menu := HBoxContainer.new()
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 14)
	column.add_child(menu)

	var index := _first_unfinished()
	var entering := String(Levels.level_at(index).get("name", ""))
	var start := UIKit.button("ENTER THE LAB", 20, Palette.SWITCH)
	start.custom_minimum_size = Vector2(250, 56)
	start.pressed.connect(func():
		Sfx.play("ui_confirm", -6.0)
		start_game.emit(index))
	menu.add_child(start)

	var index_button := UIKit.button("CHAMBER INDEX", 20, Palette.GOLD)
	index_button.custom_minimum_size = Vector2(230, 56)
	index_button.pressed.connect(func():
		Sfx.play("ui_click", -6.0)
		open_index.emit())
	menu.add_child(index_button)

	var help := UIKit.button("HOW TO PLAY", 20, Palette.NORTH)
	help.custom_minimum_size = Vector2(210, 56)
	help.pressed.connect(func():
		Sfx.play("ui_click", -6.0)
		open_help.emit())
	menu.add_child(help)

	var quit := UIKit.button("QUIT", 20, Palette.TEXT_DIM)
	quit.custom_minimum_size = Vector2(120, 56)
	quit.pressed.connect(func():
		Sfx.play("ui_back", -8.0)
		quit_game.emit())
	menu.add_child(quit)

	# --- footer ----------------------------------------------------------
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 22)
	var resume := UIKit.label("RESUME AT:  %02d  %s" % [index + 1, entering.to_upper()], 13, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	footer.add_child(resume)
	footer.add_child(UIKit.label("|", 13, Palette.TEXT_FAINT))
	footer.add_child(UIKit.label("16 CHAMBERS  /  4 CHAPTERS", 13, Palette.TEXT_DIM))
	footer.add_child(UIKit.label("|", 13, Palette.TEXT_FAINT))
	var cleared := 0
	for lvl in Levels.levels():
		if Save.is_cleared(String(lvl.get("id", ""))):
			cleared += 1
	footer.add_child(UIKit.label("TAGGED %d / %d" % [cleared, Levels.count()], 13, Palette.EXIT))
	column.add_child(footer)

	var credit := UIKit.label(
		"Godot 4  -  art + audio from Kenney CC0 packs  -  press WASD / arrows to move, Z to undo, R to reset",
		11, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(credit)


func _first_unfinished() -> int:
	for i in range(Levels.count()):
		var lvl := Levels.level_at(i)
		if not Save.is_cleared(String(lvl.get("id", ""))):
			return i
	return 0


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pm_accept"):
		Sfx.play("ui_confirm", -6.0)
		start_game.emit(_first_unfinished())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pm_menu"):
		quit_game.emit()
		get_viewport().set_input_as_handled()
