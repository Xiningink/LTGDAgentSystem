## The playable chamber: HUD, board, victory and pause overlays.
class_name GameplayScreen
extends Control

signal request_index()
signal request_level(index: int)

var _board: Board
var _level_index: int = 0
var _level: Dictionary = {}

var _title_label: Label
var _chapter_label: Label
var _moves_value: Label
var _par_value: Label
var _best_value: Label
var _hint_label: Label
var _progress_row: HBoxContainer

var _overlay_layer: Control
var _victory_panel: Control
var _pause_panel: Control
var _victory_title: Label
var _victory_stats: Label
var _victory_stars: HBoxContainer
var _victory_next: Button

var _pending_next := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_build()
	set_process_unhandled_input(true)


# --- construction ------------------------------------------------------------

func _build() -> void:
	add_child(Backdrop.new())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	vbox.add_child(_build_header())

	_board = Board.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(420, 300)
	_board.move_committed.connect(_on_move)
	_board.move_blocked.connect(_on_blocked)
	_board.solved.connect(_on_solved)
	vbox.add_child(_board)

	vbox.add_child(_build_footer())

	_build_overlays()


func _build_header() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.12, 0.20), 16.0, true))
	panel.custom_minimum_size = Vector2(0, 74)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var back := UIKit.icon_button("<  INDEX", 15)
	back.pressed.connect(func(): Sfx.play("ui_back", -10.0); request_index.emit())
	row.add_child(_vcenter(back))

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 0)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chapter_label = UIKit.label("ORIENTATION", 13, Palette.SWITCH)
	_title_label = UIKit.label("First Contact", 26, Palette.TEXT)
	name_box.add_child(_chapter_label)
	name_box.add_child(_title_label)
	row.add_child(_vcenter(name_box))

	var progress_box := VBoxContainer.new()
	progress_box.add_theme_constant_override("separation", 2)
	var progress_caption := UIKit.label("CHAMBERS TAGGED", 10, Palette.TEXT_FAINT)
	_progress_row = HBoxContainer.new()
	_progress_row.add_theme_constant_override("separation", 5)
	progress_box.add_child(progress_caption)
	progress_box.add_child(_progress_row)
	row.add_child(_vcenter(progress_box))

	row.add_child(_vcenter(_stat_block("MOVES", "0", Palette.TEXT, "par")["root"]))
	_moves_value = _last_stat_value
	row.add_child(_vcenter(_stat_block("PAR", "0", Palette.GOLD, "target")["root"]))
	_par_value = _last_stat_value
	row.add_child(_vcenter(_stat_block("BEST", "-", Palette.EXIT, "personal")["root"]))
	_best_value = _last_stat_value

	var sound := UIKit.icon_button("SOUND", 14)
	sound.pressed.connect(func():
		Save.sound_on = not Save.sound_on
		Save.save_data()
		Sfx.set_sound_on(Save.sound_on)
		if Save.sound_on:
			Sfx.play("ui_confirm", -8.0)
		sound.text = "SOUND: " + ("ON" if Save.sound_on else "OFF"))
	sound.text = "SOUND: " + ("ON" if Save.sound_on else "OFF")
	row.add_child(_vcenter(sound))

	return panel


var _last_stat_value: Label


func _stat_block(caption: String, value: String, color: Color, tag: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	box.custom_minimum_size = Vector2(84, 0)
	var cap := UIKit.label(caption, 10, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	var val := UIKit.label(value, 25, color, HORIZONTAL_ALIGNMENT_CENTER)
	var tl := UIKit.label(tag, 9, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(cap)
	box.add_child(val)
	box.add_child(tl)
	_last_stat_value = val
	return {"root": box, "value": val}


func _vcenter(node: Control) -> Control:
	var wrap := CenterContainer.new()
	wrap.add_child(node)
	return wrap


func _build_footer() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.12, 0.20), 16.0, true))
	panel.custom_minimum_size = Vector2(0, 106)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var hint_box := VBoxContainer.new()
	hint_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_box.add_theme_constant_override("separation", 2)
	var caption := UIKit.label("CHAMBER NOTE", 10, Palette.SWITCH)
	_hint_label = UIKit.label("", 15, Palette.TEXT_DIM)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(320, 40)
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hint_box.add_child(caption)
	hint_box.add_child(_hint_label)
	row.add_child(hint_box)

	var legend := _build_legend()
	row.add_child(_vcenter(legend))

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var undo := UIKit.icon_button("UNDO  (Z)", 14)
	undo.pressed.connect(func(): _board.undo(); _refresh_stats())
	var reset := UIKit.icon_button("RESET  (R)", 14)
	reset.pressed.connect(func(): _board.reset_level(); _refresh_stats())
	var help := UIKit.icon_button("RULES  (H)", 14)
	help.pressed.connect(func(): _show_pause())
	buttons.add_child(undo)
	buttons.add_child(reset)
	buttons.add_child(help)
	row.add_child(_vcenter(buttons))

	return panel


func _build_legend() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var entries := [
		["METAL CRATE", Palette.METAL],
		["N MAGNET", Palette.NORTH],
		["S MAGNET", Palette.SOUTH],
		["PLATE", Palette.PLATE],
		["HAZARD", Palette.HAZARD],
		["INVERTER", Palette.SWITCH],
	]
	for entry in entries:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 7)
		var chip := ColorRect.new()
		chip.color = entry[1]
		chip.custom_minimum_size = Vector2(11, 11)
		line.add_child(chip)
		line.add_child(UIKit.label(String(entry[0]), 11, Palette.TEXT_DIM))
		box.add_child(line)
	return box


func _build_overlays() -> void:
	_overlay_layer = Control.new()
	_overlay_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay_layer)

	# --- victory ---------------------------------------------------------
	var victory := _make_overlay_root()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.07, 0.11, 0.19), 20.0, true))
	panel.custom_minimum_size = Vector2(560, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var tag := UIKit.label("CONTAINMENT SOLVED", 13, Palette.EXIT, HORIZONTAL_ALIGNMENT_CENTER)
	_victory_title = UIKit.title("First Contact", 32, Palette.TEXT)
	_victory_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_stats = UIKit.label("", 17, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_victory_stars = HBoxContainer.new()
	_victory_stars.alignment = BoxContainer.ALIGNMENT_CENTER
	var divider := UIKit.separator(Palette.PANEL_EDGE, 1)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	_victory_next = UIKit.button("NEXT CHAMBER", 17, Palette.EXIT)
	_victory_next.pressed.connect(func(): _go_next())
	var retry := UIKit.button("RETRY", 17, Palette.SWITCH)
	retry.pressed.connect(func():
		Sfx.play("ui_click", -8.0)
		_hide_overlays()
		_board.reset_level()
		_refresh_stats())
	var index := UIKit.button("INDEX", 17, Palette.TEXT_DIM)
	index.pressed.connect(func(): Sfx.play("ui_back", -10.0); request_index.emit())
	buttons.add_child(_victory_next)
	buttons.add_child(retry)
	buttons.add_child(index)

	box.add_child(tag)
	box.add_child(_victory_title)
	box.add_child(_victory_stars)
	box.add_child(divider)
	box.add_child(_victory_stats)
	box.add_child(_spacer(6))
	box.add_child(buttons)
	victory.get_child(1).add_child(panel)
	_victory_panel = victory
	_overlay_layer.add_child(victory)


func _make_overlay_root() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.02, 0.03, 0.06, 0.80)
	root.add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	root.visible = false
	return root


func _spacer(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, px)
	return c


func _build_pause_panel() -> void:
	var pause := _make_overlay_root()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.07, 0.11, 0.19), 20.0, true))
	panel.custom_minimum_size = Vector2(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := UIKit.title("LAB NOTES", 28, Palette.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(UIKit.separator(Palette.PANEL_EDGE, 1))
	box.add_child(_rule_line("MOVE", "WASD or arrow keys. One tile per turn."))
	box.add_child(_rule_line("METAL CRATE", "Inert. Shoved one tile, chains into other crates."))
	box.add_child(_rule_line("SAME POLARITY", "You repel it: the magnet is shoved ahead of you."))
	box.add_child(_rule_line("OPPOSITE", "You attract: the two of you swap tiles."))
	box.add_child(_rule_line("HAZARD", "Your core cannot enter. Crates short it out; magnets burn."))
	box.add_child(_rule_line("INVERTER", "Flip your own polarity to change how magnets react."))
	box.add_child(_rule_line("PLATES & GATES", "Every plate marked A holds gate A open while pressed."))
	box.add_child(_spacer(4))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	var resume := UIKit.button("RESUME", 17, Palette.SWITCH)
	resume.pressed.connect(func(): Sfx.play("ui_click", -8.0); _hide_overlays())
	var restart := UIKit.button("RESTART", 17, Palette.GOLD)
	restart.pressed.connect(func():
		Sfx.play("ui_back", -8.0)
		_hide_overlays()
		_board.reset_level()
		_refresh_stats())
	var index := UIKit.button("INDEX", 17, Palette.TEXT_DIM)
	index.pressed.connect(func(): request_index.emit())
	buttons.add_child(resume)
	buttons.add_child(restart)
	buttons.add_child(index)
	box.add_child(buttons)
	pause.get_child(1).add_child(panel)
	_pause_panel = pause
	_overlay_layer.add_child(pause)


func _rule_line(key: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var k := UIKit.label(key, 12, Palette.SWITCH)
	k.custom_minimum_size = Vector2(130, 0)
	row.add_child(k)
	var t := UIKit.label(text, 13, Palette.TEXT_DIM)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(t)
	return row


# --- level lifecycle ---------------------------------------------------------

func open_level(index: int) -> void:
	if _pause_panel == null:
		_build_pause_panel()
	_level_index = clampi(index, 0, maxi(Levels.count() - 1, 0))
	_level = Levels.level_at(_level_index)
	if _level.is_empty():
		return
	_hide_overlays()
	_board.load_level(_level)
	_board.input_enabled = true

	var chapter := Levels.chapter_of(_level)
	_chapter_label.text = "%s - %s" % [String(chapter.get("code", "?")), String(chapter.get("name", ""))]
	_chapter_label.add_theme_color_override("font_color", Levels.chapter_color(_level))
	_title_label.text = "%02d   %s" % [_level_index + 1, String(_level.get("name", ""))]
	_hint_label.text = String(_level.get("hint", ""))
	_par_value.text = str(_board.par())
	_refresh_stats()
	_refresh_progress()
	_update_next_button()


func _refresh_stats() -> void:
	_moves_value.text = str(_board.moves)
	var id := String(_level.get("id", ""))
	if Save.best_moves.has(id):
		_best_value.text = str(int(Save.best_moves[id]))
	else:
		_best_value.text = "-"


func _refresh_progress() -> void:
	for child in _progress_row.get_children():
		child.queue_free()
	for i in range(Levels.count()):
		var lvl := Levels.level_at(i)
		var cleared := Save.is_cleared(String(lvl.get("id", "")))
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(11, 7)
		var col := Palette.TEXT_FAINT
		if cleared:
			col = Palette.EXIT
		elif i == _level_index:
			col = Palette.SWITCH
		else:
			col = Palette.PANEL_EDGE
		chip.color = col
		var wrap := VBoxContainer.new()
		wrap.alignment = BoxContainer.ALIGNMENT_CENTER
		wrap.add_child(chip)
		_progress_row.add_child(wrap)


func _update_next_button() -> void:
	var last := _level_index >= Levels.count() - 1
	_victory_next.text = "FINAL CHAMBER" if last else "NEXT CHAMBER"
	_victory_next.disabled = last


func _on_move(_result: Dictionary) -> void:
	_refresh_stats()


func _on_blocked(_result: Dictionary) -> void:
	pass


func _on_solved(result: Dictionary) -> void:
	_pending_next = true
	var id := String(_level.get("id", ""))
	var par := _board.par()
	var moves := _board.moves
	var is_best := Save.record_result(id, moves, _level_index, Levels.count())
	var stars := UIKit.stars_for(moves, par)
	Sfx.play("win", -5.0)
	_board.celebrate()
	_refresh_stats()
	_refresh_progress()

	_victory_title.text = String(_level.get("name", ""))
	for child in _victory_stars.get_children():
		child.queue_free()
	var row := UIKit.star_row(stars, 30.0)
	_victory_stars.add_child(row)
	var lines := [
		"CLEARED IN %d MOVES   (PAR %d)" % [moves, par],
		"PERSONAL BEST %d%s" % [int(Save.best_moves.get(id, moves)), "   NEW RECORD!" if is_best else ""],
	]
	_victory_stats.text = "\n".join(lines)
	_update_next_button()
	_show_overlay(_victory_panel)


func _go_next() -> void:
	if _level_index >= Levels.count() - 1:
		request_index.emit()
		return
	Sfx.play("ui_confirm", -8.0)
	request_level.emit(_level_index + 1)


# --- overlays ----------------------------------------------------------------

func _show_overlay(panel: Control) -> void:
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in _overlay_layer.get_children():
		child.visible = false
	panel.visible = true
	panel.modulate = Color(1, 1, 1, 0)
	var inner := panel.get_child(1).get_child(0) as Control
	if inner != null:
		inner.pivot_offset = inner.size * 0.5
		inner.scale = Vector2(0.92, 0.92)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(panel, "modulate:a", 1.0, 0.18)
		tw.tween_property(inner, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_overlays() -> void:
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in _overlay_layer.get_children():
		child.visible = false
	_pending_next = false


func _show_pause() -> void:
	if _victory_panel.visible:
		return
	if _pause_panel == null:
		_build_pause_panel()
	Sfx.play("ui_click", -10.0)
	_show_overlay(_pause_panel)


func _overlay_visible() -> bool:
	for child in _overlay_layer.get_children():
		if child.visible:
			return true
	return false


func _victory_visible() -> bool:
	return _victory_panel != null and _victory_panel.visible


# --- QA / screenshot helpers -------------------------------------------------

func debug_win() -> void:
	_board.force_win()
	_refresh_stats()


func debug_near_victory() -> void:
	var plate := Vector2i(6, 2)
	_board.force_state(Vector2i(5, 5), {plate: {"kind": "metal", "pol": ""}}, 6)
	_refresh_stats()


func debug_walk(path: String) -> void:
	_board.debug_walk(path)
	_refresh_stats()


## Capture a live hazard short-out (effects still animating).
func debug_burn() -> void:
	_board.force_state(Vector2i(2, 2), {Vector2i(3, 2): {"kind": "metal", "pol": ""}}, 1)
	_board.try_move(Vector2i(1, 0))
	_refresh_stats()


## Capture a live repulsion cascade.
func debug_cascade() -> void:
	_board.force_state(Vector2i(2, 2), {
		Vector2i(3, 2): {"kind": "magnet", "pol": "N"},
		Vector2i(5, 2): {"kind": "magnet", "pol": "N"},
	}, 1)
	_board.try_move(Vector2i(1, 0))
	_refresh_stats()


# --- input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pm_undo"):
		if _board.undo():
			_refresh_stats()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pm_reset"):
		if _overlay_visible():
			return
		Sfx.play("ui_back", -8.0)
		_board.reset_level()
		_refresh_stats()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pm_menu"):
		if _victory_visible():
			request_index.emit()
		elif _pause_panel != null and _pause_panel.visible:
			_hide_overlays()
		else:
			_show_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pm_help"):
		if not _overlay_visible():
			_show_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pm_accept"):
		if _victory_visible():
			_go_next()
			get_viewport().set_input_as_handled()
		return
	if _overlay_visible() or not _board.input_enabled:
		return
	for action in ["pm_up", "pm_down", "pm_left", "pm_right"]:
		if event.is_action_pressed(action):
			var dir: Vector2i = {
				"pm_up": Vector2i(0, -1),
				"pm_down": Vector2i(0, 1),
				"pm_left": Vector2i(-1, 0),
				"pm_right": Vector2i(1, 0),
			}[action]
			_board.try_move(dir)
			get_viewport().set_input_as_handled()
			return
