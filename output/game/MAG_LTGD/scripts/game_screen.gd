extends Control
class_name GameScreen

## The puzzle chamber screen: HUD, board view, result overlays and turn input.

signal solved(level_index: int, moves: int)
signal next_requested(level_index: int)
signal retry_requested(level_index: int)
signal levels_requested()

const Ui := preload("res://scripts/ui_kit.gd")
const AssetLib := preload("res://scripts/assets.gd")
const SfxLib := preload("res://scripts/sfx.gd")
const BoardScript := preload("res://scripts/board.gd")
const BoardViewScript := preload("res://scripts/board_view.gd")
const LevelsDataScript := preload("res://scripts/levels.gd")
const BackdropScript := preload("res://scripts/backdrop.gd")
const StarStripScript := preload("res://scripts/star_strip.gd")
const PolChipScript := preload("res://scripts/pol_chip.gd")

const TOP_H := 84.0
const BOTTOM_H := 94.0

var board = null
var level_index := 0
var best_moves := -1
var instant := false

var _view = null
var _board_area: Control
var _tag: Label
var _name_label: Label
var _chip = null
var _field_label: Label
var _plates_label: Label
var _moves_label: Label
var _hint_label: Label
var _warn_label: Label
var _undo_button: Button
var _sound_button: Button
var _overlay: Control
var _overlay_body: VBoxContainer
var _overlay_open := false
var _pending_result := ""
var _pending_timer := 0.0
var _par := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Ui.theme()
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_top()
	_build_board_area()
	_build_bottom()
	_build_overlay()
	set_process_unhandled_input(true)


# ------------------------------------------------------------------ building --

func _build_top() -> void:
	var top := ColorRect.new()
	top.color = Color(0.043, 0.063, 0.09, 0.95)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = TOP_H
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	var edge := ColorRect.new()
	edge.color = Color(Ui.ACCENT.r, Ui.ACCENT.g, Ui.ACCENT.b, 0.30)
	edge.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	edge.offset_top = TOP_H - 2.0
	edge.offset_bottom = TOP_H
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edge)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.offset_bottom = TOP_H
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", -2)
	_tag = Ui.label("CHAMBER 01", 15, Ui.ACCENT)
	_name_label = Ui.label("CALIBRATION BAY", 26, Ui.TEXT)
	_name_label.add_theme_font_override("font", AssetLib.font(AssetLib.FONT_TITLE))
	title_box.add_child(_tag)
	title_box.add_child(_name_label)
	row.add_child(title_box)
	row.add_child(Ui.spacer())

	var pol_box := PanelContainer.new()
	pol_box.add_theme_stylebox_override("panel", _chip_box())
	var pol_row := HBoxContainer.new()
	pol_row.add_theme_constant_override("separation", 10)
	pol_box.add_child(pol_row)
	_chip = PolChipScript.new()
	pol_row.add_child(_chip)
	var pol_text := VBoxContainer.new()
	pol_text.add_theme_constant_override("separation", -2)
	pol_text.add_child(Ui.label("CORE FIELD", 14, Ui.MUTED))
	_field_label = Ui.label("POSITIVE", 20, Ui.POS)
	pol_text.add_child(_field_label)
	pol_row.add_child(pol_text)
	row.add_child(pol_box)

	_plates_label = Ui.label("0 / 0", 20, Ui.TEXT)
	row.add_child(_stat_chip("PLATES", _plates_label))
	_moves_label = Ui.label("0 / 0", 20, Ui.TEXT)
	row.add_child(_stat_chip("TURNS", _moves_label))


func _chip_box() -> StyleBoxFlat:
	return Ui.flat_box(Color(0.09, 0.12, 0.17, 0.92), 12,
		Color(Ui.PANEL_EDGE.r, Ui.PANEL_EDGE.g, Ui.PANEL_EDGE.b, 0.6), 2)


func _stat_chip(caption: String, value: Label) -> PanelContainer:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _chip_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.custom_minimum_size.x = 96
	col.add_child(Ui.label(caption, 14, Ui.MUTED))
	col.add_child(value)
	box.add_child(col)
	return box


func _build_board_area() -> void:
	_board_area = Control.new()
	_board_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_area.offset_top = TOP_H
	_board_area.offset_bottom = -BOTTOM_H
	_board_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board_area)
	_view = BoardViewScript.new()
	_board_area.add_child(_view)
	_board_area.resized.connect(_on_area_resized)


func _build_bottom() -> void:
	var bar := ColorRect.new()
	bar.color = Color(0.043, 0.063, 0.09, 0.95)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -BOTTOM_H
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	var edge := ColorRect.new()
	edge.color = Color(Ui.ACCENT.r, Ui.ACCENT.g, Ui.ACCENT.b, 0.22)
	edge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	edge.offset_top = -BOTTOM_H
	edge.offset_bottom = -BOTTOM_H + 2.0
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edge)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	margin.offset_top = -BOTTOM_H
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 2)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hint_label = Ui.label("", 18, Ui.MUTED)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warn_label = Ui.label("", 16, Ui.AMBER)
	text_box.add_child(_hint_label)
	text_box.add_child(_warn_label)
	row.add_child(text_box)

	_undo_button = Ui.button("UNDO  Z", Color(0.72, 0.78, 0.88))
	_undo_button.pressed.connect(_on_undo)
	row.add_child(_undo_button)
	var reset_button := Ui.button("RESET  R", Color(1.0, 0.78, 0.5))
	reset_button.pressed.connect(_on_reset)
	row.add_child(reset_button)
	_sound_button = Ui.button("SOUND", Color(0.62, 0.9, 0.85))
	_sound_button.pressed.connect(_on_sound)
	row.add_child(_sound_button)
	var levels_button := Ui.button("CHAMBERS  ESC", Color(0.62, 0.78, 1.0))
	levels_button.pressed.connect(func() -> void: levels_requested.emit())
	row.add_child(levels_button)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.03, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Ui.card_box())
	center.add_child(card)
	_overlay_body = VBoxContainer.new()
	_overlay_body.add_theme_constant_override("separation", 12)
	_overlay_body.custom_minimum_size.x = 620
	card.add_child(_overlay_body)


# -------------------------------------------------------------------- levels --

func load_level(index: int) -> void:
	level_index = clampi(index, 0, LevelsDataScript.count() - 1)
	var data: Dictionary = LevelsDataScript.get_level(level_index)
	_par = data.solution.size()
	board = BoardScript.new()
	board.load_level(data.rows, level_index)
	_view.setup(board)
	_view.fit(_board_area.size)
	_tag.text = "CHAMBER %02d / %02d" % [level_index + 1, LevelsDataScript.count()]
	_name_label.text = String(data.name).to_upper()
	_hint_label.text = String(data.hint)
	_pending_result = ""
	_pending_timer = 0.0
	_hide_overlay()
	_refresh_hud()


func play_solution(count: int = -1) -> void:
	var data: Dictionary = LevelsDataScript.get_level(level_index)
	var moves: Array = data.solution
	var n: int = moves.size() if count < 0 else mini(count, moves.size())
	for i in n:
		var dir := _dir_from_name(String(moves[i]))
		var ev: Dictionary = board.try_move(dir)
		_view.apply_events(ev)
		if ev.get("death", false):
			break
	_refresh_hud()
	if bool(board.won):
		_complete_level()
	elif bool(board.dead):
		_show_result("fail")


func _dir_from_name(name: String) -> Vector2i:
	match name:
		"up":
			return Vector2i(0, -1)
		"down":
			return Vector2i(0, 1)
		"left":
			return Vector2i(-1, 0)
		_:
			return Vector2i(1, 0)


func _on_area_resized() -> void:
	if _view != null:
		_view.fit(_board_area.size)


# --------------------------------------------------------------------- input --

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).physical_keycode
	if _overlay_open:
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
			_activate_overlay_primary()
		elif key == KEY_ESCAPE:
			levels_requested.emit()
		return
	var dir := Vector2i.ZERO
	match key:
		KEY_UP, KEY_W:
			dir = Vector2i(0, -1)
		KEY_DOWN, KEY_S:
			dir = Vector2i(0, 1)
		KEY_LEFT, KEY_A:
			dir = Vector2i(-1, 0)
		KEY_RIGHT, KEY_D:
			dir = Vector2i(1, 0)
		KEY_Z, KEY_BACKSPACE:
			_on_undo()
			return
		KEY_R:
			_on_reset()
			return
		KEY_ESCAPE:
			levels_requested.emit()
			return
		KEY_M:
			_on_sound()
			return
	if dir != Vector2i.ZERO:
		_try_move(dir)


func _try_move(dir: Vector2i) -> void:
	if board == null or board.dead or board.won:
		return
	var ev: Dictionary = board.try_move(dir)
	if not bool(ev.get("ok", false)) and not bool(ev.get("bump", false)):
		return
	if bool(ev.get("ok", false)) and int(ev.get("push", 0)) == 0 and not bool(ev.get("pull", false)):
		SfxLib.play("step", -8.0, randf_range(0.95, 1.05))
	_view.apply_events(ev)
	_refresh_hud()
	if bool(ev.get("death", false)):
		_pending_result = "fail"
		_pending_timer = 0.55 if not instant else 0.0
	elif bool(ev.get("win", false)):
		_complete_level()


func _complete_level() -> void:
	if best_moves < 0 or board.move_count < best_moves:
		best_moves = board.move_count
	if level_index >= LevelsDataScript.count() - 1:
		SfxLib.play("fanfare", 1.0)
	solved.emit(level_index, board.move_count)
	_pending_result = "final" if level_index >= LevelsDataScript.count() - 1 else "complete"
	_pending_timer = 0.6 if not instant else 0.0
	if instant:
		_show_result(_pending_result)


func _process(delta: float) -> void:
	if _pending_timer > 0.0:
		_pending_timer -= delta
		if _pending_timer <= 0.0 and _pending_result != "":
			_show_result(_pending_result)
			_pending_result = ""


func _on_undo() -> void:
	if board == null or not board.can_undo():
		return
	board.undo()
	_pending_result = ""
	_pending_timer = 0.0
	_hide_overlay()
	_refresh_hud()
	SfxLib.play("undo", -3.0)


func _on_reset() -> void:
	if board == null:
		return
	board.reset_level()
	_pending_result = ""
	_pending_timer = 0.0
	_hide_overlay()
	_view.setup(board)
	_view.fit(_board_area.size)
	_refresh_hud()
	SfxLib.play("reset", -2.0)


func _on_sound() -> void:
	SfxLib.enabled = not SfxLib.enabled
	if SfxLib.enabled:
		SfxLib.play("click")
	_refresh_hud()


# ----------------------------------------------------------------------- hud --

func _refresh_hud() -> void:
	if board == null:
		return
	_chip.set_pol(board.player_pol)
	_field_label.text = Ui.pol_name(board.player_pol)
	_field_label.add_theme_color_override("font_color", Ui.pol_color(board.player_pol))
	if board.plates_total() == 0:
		_plates_label.text = "LIVE"
	else:
		_plates_label.text = "%d / %d" % [board.plates_loaded(), board.plates_total()]
	_plates_label.add_theme_color_override("font_color",
		Ui.GOOD if board.is_powered() else Ui.TEXT)
	_moves_label.text = "%d / %d" % [board.move_count, _par]
	_undo_button.disabled = not board.can_undo()
	_sound_button.text = "SOUND ON" if SfxLib.enabled else "SOUND OFF"
	if board.unsolvable():
		_warn_label.text = "CRATE LOST - THIS CHAMBER CAN NO LONGER BE SOLVED. UNDO (Z) OR RESET (R)."
	else:
		_warn_label.text = ""


## Used by --scenario fail so the defeat panel can be reviewed directly.
func force_fail() -> void:
	if board == null:
		return
	board.dead = true
	_show_result("fail")


# ------------------------------------------------------------------- overlay --

func overlay_open() -> bool:
	return _overlay_open


func _hide_overlay() -> void:
	_overlay_open = false
	_overlay.visible = false
	for child in _overlay_body.get_children():
		child.queue_free()


func _overlay_heading(text: String, color: Color) -> void:
	var l := Ui.heading(text, 40, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_FILL
	_overlay_body.add_child(l)


func _overlay_text(text: String, size: int = 19, color: Color = Ui.MUTED) -> void:
	var l := Ui.label(text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_body.add_child(l)


func _overlay_buttons(entries: Array) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for e in entries:
		var b := Ui.button(e.text, e.tone, 168.0)
		var action: Callable = e.action
		b.pressed.connect(action)
		row.add_child(b)
	if row.get_child_count() > 0:
		_overlay_body.add_child(row)
		_overlay_body.add_child(Ui.vspace(4))


func _activate_overlay_primary() -> void:
	for child in _overlay_body.get_children():
		if child is HBoxContainer:
			for b in child.get_children():
				if b is Button and not b.disabled:
					b.emit_signal("pressed")
					return


func _stars_for(moves: int) -> int:
	if _par <= 0:
		return 3
	if moves <= _par:
		return 3
	if moves <= int(ceil(float(_par) * 1.4)):
		return 2
	return 1


func _show_result(kind: String) -> void:
	_overlay_open = true
	_overlay.visible = true
	for child in _overlay_body.get_children():
		child.queue_free()
	var data: Dictionary = LevelsDataScript.get_level(level_index)
	if kind == "fail":
		_overlay_heading("CORE DESTROYED", Ui.POS)
		_overlay_text("The plasma vent consumed the core before it could be extracted.")
		_overlay_text("Undo the last turn, or restart the chamber and plan a safer route.", 17, Ui.MUTED)
		_overlay_buttons([
			{"text": "UNDO TURN", "tone": Color(1.0, 0.8, 0.45), "action": _on_undo},
			{"text": "RESTART", "tone": Color(0.72, 0.8, 0.9), "action": _on_reset},
			{"text": "CHAMBERS", "tone": Color(0.62, 0.78, 1.0),
				"action": func() -> void: levels_requested.emit()},
		])
		return

	var is_final: bool = kind == "final"
	if is_final:
		_overlay_heading("ALL CHAMBERS SOLVED", Ui.GOOD)
		_overlay_text("The containment core is stable and every extraction pad is live.", 20, Ui.TEXT)
	else:
		_overlay_heading("CHAMBER CLEARED", Ui.GOOD)
		_overlay_text(String(data.name).to_upper() + "  -  EXTRACTION COMPLETE", 20, Ui.TEXT)
	var stars := _stars_for(board.move_count)
	var strip = StarStripScript.new()
	strip.custom_minimum_size = Vector2(0, 54)
	strip.star_radius = 15.0
	strip.gap = 12.0
	strip.set_stars(stars, 3)
	_overlay_body.add_child(strip)
	var best_text := ""
	if best_moves >= 0 and best_moves <= board.move_count:
		best_text = "   BEST %d" % best_moves
	_overlay_text("TURNS %d   -   PAR %d%s" % [board.move_count, _par, best_text], 19, Ui.MUTED)
	if not is_final:
		_overlay_buttons([
			{"text": "NEXT CHAMBER", "tone": Color(0.55, 0.85, 1.0),
				"action": func() -> void: next_requested.emit(level_index)},
			{"text": "REPLAY", "tone": Color(0.72, 0.8, 0.9), "action": _on_reset},
			{"text": "CHAMBERS", "tone": Color(0.62, 0.78, 1.0),
				"action": func() -> void: levels_requested.emit()},
		])
	else:
		_overlay_buttons([
			{"text": "CHAMBER SELECT", "tone": Color(0.55, 0.85, 1.0),
				"action": func() -> void: levels_requested.emit()},
			{"text": "REPLAY FINAL", "tone": Color(0.72, 0.8, 0.9), "action": _on_reset},
		])
