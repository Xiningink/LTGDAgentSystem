class_name IvoryUI
extends CanvasLayer
## All menus, HUD and result presentation for Ivory Beats.

signal mode_selected(mode: String)
signal retry_pressed()
signal menu_pressed()

const W := 1280.0
const H := 720.0

const COL_WHITE := Color("f4f4fa")
const COL_DIM := Color("8b8b9e")
const COL_FAINT := Color("4a4a5c")
const COL_ACCENT := Color("3ef2ff")
const COL_ACCENT2 := Color("ff3bd0")
const COL_FAULT := Color("ff3557")
const COL_WARN := Color("ffb038")
const COL_PANEL := Color("0d0d15")

const MODE_INFO := {
	"endless": {"name": "ENDLESS", "sub": "SURVIVE THE ACCELERATION"},
	"sprint": {"name": "SPRINT", "sub": "CLEAR 40 TILES"},
	"blitz": {"name": "BLITZ", "sub": "30 SECOND FRENZY"},
}

const REASONS := {
	"MISTAP": {"title": "MISTAP", "sub": "WRONG LANE", "color": COL_FAULT},
	"ESCAPED": {"title": "ESCAPED", "sub": "A TILE GOT THROUGH", "color": Color("ff7a45")},
	"TIME": {"title": "TIME UP", "sub": "THE CLOCK WON", "color": COL_WARN},
	"VICTORY": {"title": "CLEARED", "sub": "TARGET SHATTERED", "color": COL_ACCENT},
}

var state := "title"

var _font_title: Font
var _font_mono: Font

var _root: Control
var _backdrop: Control
var _title_root: Control
var _ready_root: Control
var _hud_root: Control
var _results_root: Control
var _flash_rect: ColorRect

# Title widgets.
var _best_labels: Dictionary = {}
var _title_accent: ColorRect
var _title_pulse := 0.0

# HUD widgets.
var _hud_mode: Label
var _hud_target: Label
var _hud_score: Label
var _hud_timer: Label
var _hud_best: Label

# Ready widgets.
var _ready_mode: Label
var _ready_sub: Label
var _ready_prompt: Label

# Results widgets.
var _slide: Control
var _reason_title: Label
var _reason_sub: Label
var _res_mode: Label
var _res_score: Label
var _res_best: Label
var _res_record: Label
var _res_stats: Label
var _panel: PanelContainer

var _time := 0.0
var _flash_alpha := 0.0
var _flash_color := Color.WHITE


func _ready() -> void:
	layer = 10
	_font_title = load("res://assets/fonts/Kenney Future.ttf")
	_font_mono = load("res://assets/fonts/Kenney Mini Square Mono.ttf")
	_build()


func _process(delta: float) -> void:
	_time += delta
	if _flash_alpha > 0.0:
		_flash_alpha = max(0.0, _flash_alpha - delta * 2.8)
		_flash_rect.color = Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash_alpha)

	if state == "ready":
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		_ready_prompt.modulate.a = 0.35 + 0.65 * pulse
		_ready_prompt.scale = Vector2.ONE * (1.0 + 0.04 * pulse)
	elif state == "title":
		var pulse2 := 0.5 + 0.5 * sin(_time * 3.0)
		_title_accent.color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.35 + 0.5 * pulse2)


func screen_flash(color: Color, strength: float) -> void:
	_flash_color = color
	_flash_alpha = max(_flash_alpha, strength)
	_flash_rect.color = Color(color.r, color.g, color.b, _flash_alpha)


# --------------------------------------------------------------------------
# Screen states
# --------------------------------------------------------------------------

func show_title(best: Dictionary) -> void:
	state = "title"
	_backdrop.visible = true
	_title_root.visible = true
	_ready_root.visible = false
	_hud_root.visible = false
	_results_root.visible = false
	for mode in _best_labels.keys():
		var value: int = int(best.get(mode, 0))
		_best_labels[mode].text = "BEST  %s" % _fmt(value)


func show_ready(mode: String, cfg: Dictionary, best: Dictionary) -> void:
	state = "ready"
	_backdrop.visible = false
	_title_root.visible = false
	_results_root.visible = false
	_hud_root.visible = true
	_ready_root.visible = true
	var info: Dictionary = MODE_INFO.get(mode, MODE_INFO["endless"])
	_ready_mode.text = info.name
	_ready_sub.text = info.sub
	_ready_prompt.modulate.a = 1.0
	_set_hud_mode(mode, cfg, best)


func show_playing(mode: String, cfg: Dictionary, best: Dictionary) -> void:
	state = "playing"
	_backdrop.visible = false
	_ready_root.visible = false
	_title_root.visible = false
	_results_root.visible = false
	_hud_root.visible = true
	_set_hud_mode(mode, cfg, best)


func update_hud(mode: String, cfg: Dictionary, score: int, hits: int, time_left: float, elapsed: float, best: int) -> void:
	_hud_score.text = _fmt(score)
	if int(cfg.get("target", 0)) > 0:
		_hud_target.text = "TILES  %d / %d" % [hits, int(cfg.target)]
	else:
		_hud_target.text = "TILES  %d" % hits
	if float(cfg.get("time", 0.0)) > 0.0:
		_hud_timer.text = "%0.1f" % maxf(time_left, 0.0)
		_hud_timer.add_theme_color_override("font_color", COL_FAULT if time_left <= 5.0 else COL_WHITE)
	else:
		_hud_timer.text = _fmt_clock(elapsed)
		_hud_timer.add_theme_color_override("font_color", COL_WHITE)
	var live_best: int = maxi(best, score)
	_hud_best.text = "BEST  %s" % _fmt(live_best)


func show_results(data: Dictionary) -> void:
	state = "results"
	_results_root.visible = true
	var reason: Dictionary = REASONS.get(data.reason, REASONS["MISTAP"])
	_reason_title.text = reason.title
	_reason_title.add_theme_color_override("font_color", reason.color)
	_reason_sub.text = reason.sub
	_res_mode.text = "%s  ·  %s" % [data.mode_name, MODE_INFO.get(data.mode, MODE_INFO["endless"]).sub]
	_res_score.text = _fmt(int(data.score))
	_res_best.text = "BEST  %s" % _fmt(int(data.best))
	_res_record.visible = bool(data.new_record)
	_res_record.modulate.a = 0.0
	var acc := 0.0
	if int(data.hits) > 0:
		acc = 100.0 * float(data.perfects) / float(data.hits)
	_res_stats.text = "HITS %d     PERFECT %d     ACCURACY %0.0f%%\nTIME %s     TOP SPEED %d" % [
		int(data.hits), int(data.perfects), acc,
		("%0.1fs" % float(data.time)), int(data.speed),
	]
	# Slide the panel up over the frozen board.
	_slide.position = Vector2(0.0, 300.0)
	_slide.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_slide, "position:y", 0.0, 0.38).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(_slide, "modulate:a", 1.0, 0.24)
	tween.chain().tween_property(_res_record, "modulate:a", 1.0, 0.2)


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_backdrop()
	_build_title()
	_build_hud()
	_build_ready()
	_build_results()

	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash_rect)


func _build_backdrop() -> void:
	_backdrop = Control.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color("111120"), Color("07070c"), Color("030306")])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 256
	var backdrop := TextureRect.new()
	backdrop.texture = tex
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(backdrop)

	# Soft side vignette bars framing the play field.
	for side in [-1, 1]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.35)
		bar.position = Vector2((W + 640.0) * 0.5, 0.0) if side > 0 else Vector2(0.0, 0.0)
		bar.size = Vector2((W - 640.0) * 0.5, H)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_backdrop.add_child(bar)


func _build_title() -> void:
	_title_root = Control.new()
	_title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_title_root)

	var word_row := HBoxContainer.new()
	word_row.alignment = BoxContainer.ALIGNMENT_CENTER
	word_row.position = Vector2(0.0, 78.0)
	word_row.add_theme_constant_override("separation", 26)
	word_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	word_row.custom_minimum_size = Vector2(W, 130.0)
	_title_root.add_child(word_row)

	var ivory := _label("IVORY", 108, COL_WHITE, _font_title)
	ivory.add_theme_constant_override("outline_size", 10)
	ivory.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	word_row.add_child(ivory)

	var beats := _label("BEATS", 108, COL_ACCENT, _font_title)
	beats.add_theme_constant_override("outline_size", 10)
	beats.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	word_row.add_child(beats)

	_title_accent = ColorRect.new()
	_title_accent.color = COL_ACCENT
	_title_accent.position = Vector2(W * 0.5 - 220.0, 218.0)
	_title_accent.size = Vector2(440.0, 3.0)
	_title_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.add_child(_title_accent)

	var tagline := _label("STRIKE THE LINE  ·  CHASE THE FLOW", 24, COL_DIM, _font_mono)
	tagline.position = Vector2(0.0, 236.0)
	tagline.size = Vector2(W, 40.0)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.add_child(tagline)

	var column := VBoxContainer.new()
	column.position = Vector2(W * 0.5 - 280.0, 312.0)
	column.custom_minimum_size = Vector2(560.0, 0.0)
	column.add_theme_constant_override("separation", 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.add_child(column)

	for mode in ["endless", "sprint", "blitz"]:
		column.add_child(_make_mode_button(mode))

	var hint := _label("A S D F     ARROW KEYS     CLICK LANES        ·        PRESS 1 2 3", 17, COL_FAINT, _font_mono)
	hint.position = Vector2(0.0, 632.0)
	hint.size = Vector2(W, 30.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.add_child(hint)

	var credit := _label("v1.0  ·  A MONOCHROME REACTION ARCADE", 14, Color("2f2f3d"), _font_mono)
	credit.position = Vector2(0.0, 676.0)
	credit.size = Vector2(W, 24.0)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.add_child(credit)


func _make_mode_button(mode: String) -> Button:
	var info: Dictionary = MODE_INFO[mode]
	var button := Button.new()
	button.custom_minimum_size = Vector2(560.0, 82.0)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_mode_button(button)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)

	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_theme_constant_override("separation", 0)
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_col)

	var name_label := _label(info.name, 30, COL_WHITE, _font_title)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(name_label)

	var sub_label := _label(info.sub, 14, COL_DIM, _font_mono)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(sub_label)

	var best_label := _label("BEST  0", 20, COL_ACCENT, _font_mono)
	best_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	best_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(best_label)

	_best_labels[mode] = best_label
	button.pressed.connect(func() -> void: mode_selected.emit(mode))
	return button


func _build_hud() -> void:
	_hud_root = Control.new()
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud_root)

	_hud_mode = _label("", 30, COL_ACCENT, _font_title)
	_hud_mode.position = Vector2(40.0, 22.0)
	_hud_mode.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_hud_mode)

	_hud_target = _label("", 17, COL_DIM, _font_mono)
	_hud_target.position = Vector2(42.0, 64.0)
	_hud_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_hud_target)

	var score_caption := _label("SCORE", 13, COL_FAINT, _font_mono)
	score_caption.position = Vector2(0.0, 18.0)
	score_caption.size = Vector2(W, 20.0)
	score_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(score_caption)

	_hud_score = _label("0", 52, COL_WHITE, _font_title)
	_hud_score.position = Vector2(0.0, 34.0)
	_hud_score.size = Vector2(W, 66.0)
	_hud_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_hud_score)

	_hud_timer = _label("0.0", 40, COL_WHITE, _font_title)
	_hud_timer.position = Vector2(W - 340.0, 20.0)
	_hud_timer.size = Vector2(300.0, 54.0)
	_hud_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_hud_timer)

	_hud_best = _label("BEST  0", 17, COL_DIM, _font_mono)
	_hud_best.position = Vector2(W - 340.0, 74.0)
	_hud_best.size = Vector2(300.0, 24.0)
	_hud_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_best.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_hud_best)


func _build_ready() -> void:
	_ready_root = Control.new()
	_ready_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ready_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_ready_root)

	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.35)
	band.position = Vector2(0.0, 352.0)
	band.size = Vector2(W, 118.0)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_root.add_child(band)

	_ready_mode = _label("", 56, COL_WHITE, _font_title)
	_ready_mode.position = Vector2(0.0, 362.0)
	_ready_mode.size = Vector2(W, 66.0)
	_ready_mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_mode.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_root.add_child(_ready_mode)

	_ready_sub = _label("", 18, COL_DIM, _font_mono)
	_ready_sub.position = Vector2(0.0, 428.0)
	_ready_sub.size = Vector2(W, 30.0)
	_ready_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_root.add_child(_ready_sub)

	_ready_prompt = _label("TAP ANY LANE TO START", 30, COL_ACCENT, _font_title)
	_ready_prompt.position = Vector2(0.0, 520.0)
	_ready_prompt.size = Vector2(W, 44.0)
	_ready_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_prompt.pivot_offset = Vector2(W * 0.5, 22.0)
	_ready_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_root.add_child(_ready_prompt)

	var hint := _label("A S D F    ·    ← ↑ ↓ →    ·    CLICK THE LANE", 17, COL_FAINT, _font_mono)
	hint.position = Vector2(0.0, 572.0)
	hint.size = Vector2(W, 30.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_root.add_child(hint)


func _build_results() -> void:
	_results_root = Control.new()
	_results_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_results_root)
	_results_root.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.015, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_results_root.add_child(dim)

	_slide = Control.new()
	_slide.position = Vector2(0.0, 300.0)
	_slide.size = Vector2(W, H)
	_slide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_root.add_child(_slide)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(660.0, 0.0)
	_style_panel(_panel)
	center.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)

	_reason_title = _label("", 52, COL_WHITE, _font_title)
	_reason_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_reason_title)

	_reason_sub = _label("", 17, COL_DIM, _font_mono)
	_reason_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_reason_sub)

	column.add_child(_spacer(10.0))

	_res_mode = _label("", 16, COL_FAINT, _font_mono)
	_res_mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_res_mode)

	var score_caption := _label("SCORE", 14, COL_DIM, _font_mono)
	score_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(score_caption)

	_res_score = _label("0", 78, COL_WHITE, _font_title)
	_res_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_res_score)

	_res_best = _label("BEST  0", 22, COL_ACCENT, _font_mono)
	_res_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_res_best)

	_res_record = _label("★  NEW RECORD  ★", 20, COL_ACCENT2, _font_title)
	_res_record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_res_record)

	column.add_child(_spacer(10.0))

	var divider := ColorRect.new()
	divider.color = Color(1, 1, 1, 0.12)
	divider.custom_minimum_size = Vector2(0.0, 2.0)
	column.add_child(divider)

	column.add_child(_spacer(6.0))

	_res_stats = _label("", 17, COL_DIM, _font_mono)
	_res_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_res_stats)

	column.add_child(_spacer(16.0))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	column.add_child(buttons)

	var retry := _make_action_button("RETRY  (R)", true)
	retry.pressed.connect(func() -> void: retry_pressed.emit())
	buttons.add_child(retry)

	var menu := _make_action_button("MENU  (ESC)", false)
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(menu)


func _make_action_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(250.0, 64.0)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", _font_title)
	button.add_theme_font_size_override("font_size", 24)
	if primary:
		button.add_theme_color_override("font_color", Color("06060c"))
		button.add_theme_color_override("font_hover_color", Color("06060c"))
		button.add_theme_color_override("font_pressed_color", Color("06060c"))
		button.add_theme_stylebox_override("normal", _stylebox(COL_ACCENT, COL_ACCENT, 10, 0))
		button.add_theme_stylebox_override("hover", _stylebox(COL_WHITE, COL_WHITE, 10, 0))
		button.add_theme_stylebox_override("pressed", _stylebox(COL_ACCENT, COL_ACCENT, 10, 0))
	else:
		button.add_theme_color_override("font_color", COL_WHITE)
		button.add_theme_color_override("font_hover_color", COL_WHITE)
		button.add_theme_stylebox_override("normal", _stylebox(Color("14141d"), COL_FAINT, 10, 2))
		button.add_theme_stylebox_override("hover", _stylebox(Color("1c1c28"), COL_ACCENT, 10, 2))
		button.add_theme_stylebox_override("pressed", _stylebox(Color("101018"), COL_ACCENT, 10, 2))
	return button


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _set_hud_mode(mode: String, cfg: Dictionary, best: Dictionary) -> void:
	var info: Dictionary = MODE_INFO.get(mode, MODE_INFO["endless"])
	_hud_mode.text = info.name
	_hud_score.text = "0"
	if float(cfg.get("time", 0.0)) > 0.0:
		_hud_timer.text = "%0.1f" % float(cfg.time)
		_hud_timer.add_theme_color_override("font_color", COL_WHITE)
	else:
		_hud_timer.text = "0:00"
	_hud_best.text = "BEST  %s" % _fmt(int(best.get(mode, 0)))
	if int(cfg.get("target", 0)) > 0:
		_hud_target.text = "TILES  0 / %d" % int(cfg.target)
	else:
		_hud_target.text = "TILES  0"


func _label(text: String, size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _spacer(height: float) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0.0, height)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func _stylebox(bg: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style


func _style_mode_button(button: Button) -> void:
	button.add_theme_font_override("font", _font_title)
	button.add_theme_color_override("font_color", COL_WHITE)
	var normal := _stylebox(Color("0f0f18"), Color("3a3a4c"), 10, 2)
	normal.content_margin_left = 4.0
	var hover := _stylebox(Color("171724"), COL_ACCENT, 10, 2)
	var pressed := _stylebox(Color("0a0a12"), COL_ACCENT, 10, 2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _style_panel(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = Color(1, 1, 1, 0.16)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(34)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 24
	panel.add_theme_stylebox_override("panel", style)


func _fmt(value: int) -> String:
	var negative := value < 0
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if negative else "") + out


func _fmt_clock(seconds: float) -> String:
	var total := int(seconds)
	var minutes := total / 60
	var secs := total % 60
	return "%d:%02d" % [minutes, secs]
