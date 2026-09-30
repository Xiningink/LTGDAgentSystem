extends Control
class_name LevelSelect

## Chamber select: one card per chamber with lock state and star rating.

signal level_chosen(index: int)
signal back_requested()

const Ui := preload("res://scripts/ui_kit.gd")
const AssetLib := preload("res://scripts/assets.gd")
const SfxLib := preload("res://scripts/sfx.gd")
const BackdropScript := preload("res://scripts/backdrop.gd")
const StarStripScript := preload("res://scripts/star_strip.gd")
const LevelsDataScript := preload("res://scripts/levels.gd")

var unlocked := 1
var best: Array = []

var _grid: GridContainer
var _star_label: Label
var _built := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Ui.theme()
	var backdrop = BackdropScript.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_build()


func setup(unlocked_count: int, best_moves: Array) -> void:
	unlocked = unlocked_count
	best = best_moves
	if _built:
		_refresh()


func stars_for(index: int) -> int:
	if index >= best.size():
		return 0
	var m: int = best[index]
	if m < 0:
		return 0
	var par: int = LevelsDataScript.get_level(index).solution.size()
	if m <= par:
		return 3
	if m <= int(ceil(float(par) * 1.4)):
		return 2
	return 1


func _build() -> void:
	var header := MarginContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 96.0
	header.add_theme_constant_override("margin_left", 34)
	header.add_theme_constant_override("margin_right", 34)
	header.add_theme_constant_override("margin_top", 22)
	add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	header.add_child(row)
	var back := Ui.button("BACK", Color(0.68, 0.76, 0.86), 130.0)
	back.pressed.connect(func() -> void: back_requested.emit())
	row.add_child(back)
	var heading := Ui.heading("CHAMBER SELECT", 40, Ui.ACCENT)
	row.add_child(heading)
	row.add_child(Ui.spacer())
	_star_label = Ui.label("", 22, Ui.AMBER)
	row.add_child(_star_label)

	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 104.0
	center.offset_bottom = -26.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.add_child(_grid)
	_built = true
	_refresh()


func _refresh() -> void:
	for child in _grid.get_children():
		child.queue_free()
	var total_stars := 0
	for i in LevelsDataScript.count():
		var stars := stars_for(i)
		total_stars += stars
		_grid.add_child(_card(i, stars))
	_star_label.text = "STARS  %d / %d" % [total_stars, LevelsDataScript.count() * 3]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			back_requested.emit()


func _card(index: int, stars: int) -> Button:
	var data: Dictionary = LevelsDataScript.get_level(index)
	var open: bool = index < unlocked
	var cleared: bool = stars > 0
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(224, 168)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if open else Control.CURSOR_ARROW
	var tint := Color(0.72, 0.8, 0.9) if open else Color(0.34, 0.38, 0.44)
	card.add_theme_stylebox_override("normal", Ui.flat_box(
		Color(0.075, 0.10, 0.145, 0.95), 14,
		Color(Ui.GOOD.r, Ui.GOOD.g, Ui.GOOD.b, 0.55) if cleared else Color(Ui.PANEL_EDGE.r, Ui.PANEL_EDGE.g, Ui.PANEL_EDGE.b, 0.7), 2))
	card.add_theme_stylebox_override("hover", Ui.flat_box(
		Color(0.11, 0.15, 0.21, 0.98), 14, Color(Ui.ACCENT.r, Ui.ACCENT.g, Ui.ACCENT.b, 0.8), 2))
	card.add_theme_stylebox_override("pressed", Ui.flat_box(
		Color(0.06, 0.09, 0.13, 1.0), 14, Color(Ui.ACCENT.r, Ui.ACCENT.g, Ui.ACCENT.b, 0.9), 2))
	card.add_theme_stylebox_override("disabled", Ui.flat_box(
		Color(0.055, 0.07, 0.10, 0.9), 14, Color(0.2, 0.24, 0.3, 0.7), 2))
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.disabled = not open
	if open:
		card.pressed.connect(func() -> void: level_chosen.emit(index))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var num := Ui.label("%02d" % (index + 1), 40, tint if open else Color(0.4, 0.45, 0.52))
	num.add_theme_font_override("font", AssetLib.font(AssetLib.FONT_TITLE))
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(num)

	var name_label := Ui.label(String(data.name).to_upper() if open else "LOCKED", 16,
		Ui.TEXT if open else Ui.MUTED)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_label)

	col.add_child(Ui.spacer())
	var strip = StarStripScript.new()
	strip.custom_minimum_size = Vector2(0, 30)
	strip.star_radius = 9.0
	strip.set_stars(stars if open else 0, 3)
	col.add_child(strip)

	var footer := Ui.label(_footer_text(index, open, stars), 14, Ui.MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(footer)
	return card


func _footer_text(index: int, open: bool, stars: int) -> String:
	if not open:
		return "CLEAR CHAMBER %02d" % index
	var par: int = LevelsDataScript.get_level(index).solution.size()
	if stars > 0 and index < best.size() and best[index] >= 0:
		return "BEST %d  -  PAR %d" % [best[index], par]
	return "PAR %d" % par
