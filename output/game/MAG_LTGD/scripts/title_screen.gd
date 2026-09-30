extends Control
class_name TitleScreen

## Laboratory title screen: animated magnet art, main menu and the rules panel.

signal begin_requested()
signal levels_requested()

const Ui := preload("res://scripts/ui_kit.gd")
const AssetLib := preload("res://scripts/assets.gd")
const SfxLib := preload("res://scripts/sfx.gd")
const BackdropScript := preload("res://scripts/backdrop.gd")
const TitleArtScript := preload("res://scripts/title_art.gd")
const LevelsDataScript := preload("res://scripts/levels.gd")

var unlocked := 1
var best: Array = []
var resume_index := 0

var _rules: Control
var _resume_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Ui.theme()
	var backdrop = BackdropScript.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_build_menu()
	_build_rules()


func _build_menu() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	center.add_child(col)

	var art = TitleArtScript.new()
	art.custom_minimum_size = Vector2(420, 250)
	col.add_child(art)

	var title := Ui.title("PUZZLE MAGNET LAB", 66, Color(0.94, 0.98, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := Ui.label("A TURN-BASED MAGNETIC LOGIC PUZZLE", 19, Ui.ACCENT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(Ui.vspace(16))

	var begin := Ui.button("BEGIN EXPERIMENT", Color(0.55, 0.85, 1.0), 400.0)
	begin.custom_minimum_size.y = 58.0
	begin.pressed.connect(func() -> void: begin_requested.emit())
	col.add_child(begin)

	var levels := Ui.button("CHAMBER SELECT", Color(0.68, 0.76, 0.86), 400.0)
	levels.custom_minimum_size.y = 52.0
	levels.pressed.connect(func() -> void: levels_requested.emit())
	col.add_child(levels)

	var rules := Ui.button("HOW TO PLAY", Color(0.68, 0.76, 0.86), 400.0)
	rules.custom_minimum_size.y = 52.0
	rules.pressed.connect(_show_rules)
	col.add_child(rules)

	var info := Ui.label("%d chambers - push, drag, swap fields and sequence." % LevelsDataScript.count(), 16, Ui.MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(info)


func _build_rules() -> void:
	_rules = Control.new()
	_rules.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rules.visible = false
	_rules.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rules)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.03, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules.add_child(center)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Ui.card_box())
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size.x = 760
	card.add_child(col)

	var heading := Ui.heading("LAB BRIEFING", 38, Ui.ACCENT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(heading)

	var rows := [
		["MOVE", "Arrow keys or WASD step the core one tile per turn."],
		["PUSH", "Walk into a crate that shares your field polarity to shove it away."],
		["DRAG", "An opposite-polarity crate directly behind you follows while you keep walking straight."],
		["PLATES", "Every pressure plate must hold a crate before gates unseal and the extraction pad wakes."],
		["SWITCH PADS", "Crossing one inverts the field of the core or the crate that crossed it."],
		["VENT PLASMA", "Vents destroy crates and the core. A lost crate means the chamber must be undone."],
		["TIME TRAVEL", "Z undoes a turn, R restarts the chamber, M toggles sound."],
	]
	for row in rows:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 16)
		var key := Ui.label(row[0], 18, Ui.ACCENT)
		key.custom_minimum_size.x = 180
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var text := Ui.label(row[1], 18, Ui.TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.custom_minimum_size.x = 540
		hbox.add_child(key)
		hbox.add_child(text)
		col.add_child(hbox)

	col.add_child(Ui.vspace(10))
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var close := Ui.button("UNDERSTOOD", Color(0.55, 0.85, 1.0), 240.0)
	close.pressed.connect(func() -> void: _rules.visible = false)
	close_row.add_child(close)
	col.add_child(close_row)
	_rules.visible = false


func _show_rules() -> void:
	_rules.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).physical_keycode
	if _rules.visible:
		if key == KEY_ESCAPE or key == KEY_ENTER or key == KEY_SPACE:
			_rules.visible = false
		return
	if key == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
