## Field manual: illustrated rules, controls and a glossary.
class_name HelpScreen
extends Control

signal back()


const RULES := [
	{
		"kind": "move",
		"title": "ONE TILE PER TURN",
		"body": "Your core steps a single tile at a time. Nothing moves on its own - every consequence comes from the move you just made.",
	},
	{
		"kind": "crate",
		"title": "METAL CRATES",
		"body": "Inert steel with no field of its own. Shoved one tile at a time, chains into other crates, and can hold a pressure plate down.",
	},
	{
		"kind": "repel",
		"title": "LIKE REPELS LIKE",
		"body": "A red NORTH magnet matches your default field. Walk into it and it is shoved ahead of you, passing the shove on to whatever it strikes.",
	},
	{
		"kind": "attract",
		"title": "OPPOSITES ATTRACT",
		"body": "A blue SOUTH magnet pulls against your field. Walk into it and the two of you trade tiles, dropping the magnet onto the tile you just left.",
	},
	{
		"kind": "hazard",
		"title": "LIVE HAZARDS",
		"body": "Striped tiles are lethal to your core. A metal crate shorts one out and is consumed doing it; a magnet simply burns away.",
	},
	{
		"kind": "inverter",
		"title": "INVERTER PADS",
		"body": "Step on the spinning pad to flip your own polarity. Repulsion becomes attraction and back again - sometimes mid-sequence.",
	},
	{
		"kind": "plate",
		"title": "PLATES AND GATES",
		"body": "A gate is open while every plate sharing its letter is held down. Objects can hold a plate for you; you cannot be in two places.",
	},
	{
		"kind": "exit",
		"title": "THE AIRLOCK",
		"body": "Reach the green portal to tag the chamber. Solid matter is refused entry, so clear a path rather than block it.",
	},
]


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

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.12, 0.20), 16.0, true))
	panel.custom_minimum_size = Vector2(0, 78)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var back_button := UIKit.icon_button("<  BACK", 15)
	back_button.pressed.connect(func(): Sfx.play("ui_back", -10.0); back.emit())
	row.add_child(_center(back_button))
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	title_box.add_child(UIKit.label("FIELD MANUAL", 12, Palette.SWITCH))
	title_box.add_child(UIKit.title("HOW TO PLAY", 30, Palette.TEXT))
	row.add_child(_center(title_box))
	var hint := UIKit.label("WASD / ARROWS  MOVE    Z  UNDO    R  RESET    H  RULES    ESC  MENU", 13, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	hint.clip_text = true
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	column.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for rule in RULES:
		grid.add_child(_rule_card(rule))

	column.add_child(_build_glossary())


func _rule_card(rule: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.12, 0.20), 14.0, true))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var icon := RuleIcon.new(String(rule["kind"]), Vector2(150, 104))
	row.add_child(_center(icon))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	text.add_child(UIKit.label(String(rule["title"]), 18, Palette.TEXT))
	var body := UIKit.label(String(rule["body"]), 13, Palette.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(280, 0)
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text.add_child(body)
	row.add_child(_center(text))
	return panel


func _build_glossary() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.07, 0.11, 0.18), 14.0, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	panel.add_child(row)
	var entries := [
		["NORTH FIELD", Palette.NORTH, "Your core's default polarity (N)."],
		["SOUTH FIELD", Palette.SOUTH, "The opposite polarity (S), reached via an inverter."],
		["CHAIN", Palette.GOLD, "A shove that travels through several objects at once."],
		["PAR", Palette.EXIT, "The shortest known solution. Match it for three stars."],
	]
	for entry in entries:
		var line := VBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var caption := UIKit.label(String(entry[0]), 12, entry[1])
		caption.clip_text = true
		var body := UIKit.label(String(entry[2]), 12, Palette.TEXT_DIM)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(120, 0)
		line.add_child(caption)
		line.add_child(body)
		row.add_child(line)
	return panel


func _center(node: Control) -> Control:
	var wrap := CenterContainer.new()
	wrap.add_child(node)
	return wrap


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pm_menu") or event.is_action_pressed("pm_help"):
		Sfx.play("ui_back", -10.0)
		back.emit()
		get_viewport().set_input_as_handled()
