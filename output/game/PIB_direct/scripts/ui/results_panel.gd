extends Control
class_name ResultsPanel

## End-of-run overlay. Slides over the frozen board and offers retry / menu.

signal retry_requested
signal menu_requested

const FONT_DISPLAY := preload("res://assets/fonts/KenneyFuture.ttf")
const FONT_NARROW := preload("res://assets/fonts/KenneyFutureNarrow.ttf")
const FONT_MONO := preload("res://assets/fonts/KenneyMiniSquare.ttf")

var _card: Panel
var _mode_label: Label
var _title_label: Label
var _sub_label: Label
var _score_value: Label
var _best_value: Label
var _new_best: Label
var _stats_label: Label
var _retry_btn: Button
var _menu_btn: Button
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.03, 0.66)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = Panel.new()
	_card.custom_minimum_size = Vector2(640, 470)
	_card.add_theme_stylebox_override("panel", _card_style())
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_card)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 46)
	margin.add_theme_constant_override("margin_right", 46)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 32)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vb)

	_mode_label = _make_label("", FONT_NARROW, 16, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(_mode_label)

	_title_label = _make_label("", FONT_DISPLAY, 58, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(_title_label)

	_sub_label = _make_label("", FONT_NARROW, 18, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(_sub_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(spacer)

	var score_row := _make_row("SCORE", FONT_DISPLAY, 64, Palette.TEXT)
	_score_value = score_row[1]

	var best_row := _make_row("BEST", FONT_DISPLAY, 30, Palette.TEXT_DIM)
	_best_value = best_row[1]

	_new_best = _make_label("", FONT_DISPLAY, 22, Palette.NEON[2], HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(_new_best)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(spacer2)

	_stats_label = _make_label("", FONT_NARROW, 18, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(_stats_label)

	var spacer3 := Control.new()
	spacer3.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(spacer3)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(buttons)

	_retry_btn = _make_button("RETRY  ⟳", true)
	_retry_btn.pressed.connect(func(): emit_signal("retry_requested"))
	buttons.add_child(_retry_btn)

	_menu_btn = _make_button("MENU", false)
	_menu_btn.pressed.connect(func(): emit_signal("menu_requested"))
	buttons.add_child(_menu_btn)


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_left = 18
	sb.corner_radius_bottom_right = 18
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Palette.PANEL_EDGE
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	return sb


func _make_label(text: String, font: Font, size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Returns [caption_label, value_label] and adds the row to the vbox.
func _make_row(caption: String, font: Font, size: int, color: Color) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parent: VBoxContainer = _title_label.get_parent()
	parent.add_child(row)

	var cap := _make_label(caption, FONT_NARROW, 15, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_LEFT)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cap)

	var val := _make_label("0", font, size, color, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(val)
	return [cap, val]


func _make_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", FONT_DISPLAY)
	b.add_theme_font_size_override("font_size", 22)
	var accent: Color = Palette.NEON[0] if primary else Palette.TEXT_DIM
	b.add_theme_color_override("font_color", Palette.BG if primary else Palette.TEXT)
	b.add_theme_color_override("font_hover_color", Palette.BG if primary else Palette.TEXT)
	b.add_theme_stylebox_override("normal", _button_style(primary, false, accent))
	b.add_theme_stylebox_override("hover", _button_style(primary, true, accent))
	b.add_theme_stylebox_override("pressed", _button_style(primary, true, accent))
	return b


func _button_style(primary: bool, hover: bool, accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent if primary else Color(1, 1, 1, 0.06 if not hover else 0.12)
	if hover and primary:
		sb.bg_color = accent.lightened(0.15)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = accent if primary else Palette.PANEL_EDGE
	return sb


func present(data: Dictionary) -> void:
	var mode_name := str(data.get("mode_name", ""))
	var reason := str(data.get("reason", ""))
	var victory := bool(data.get("victory", false))
	var accent: Color = Palette.NEON[int(data.get("accent", 0)) % Palette.NEON.size()]

	_mode_label.text = "%s MODE" % mode_name
	_mode_label.add_theme_color_override("font_color", accent)

	var look := _look_for(reason)
	_title_label.text = look[0]
	_title_label.add_theme_color_override("font_color", Palette.NEON[2] if victory else Palette.TEXT)
	_sub_label.text = look[1]

	_score_value.text = _fmt(int(data.get("score", 0)))
	_best_value.text = _fmt(int(data.get("best", 0)))
	var is_best := bool(data.get("is_best", false))
	_new_best.visible = is_best
	_new_best.text = "★  NEW PERSONAL BEST"

	var hits := int(data.get("hits", 0))
	var perfects := int(data.get("perfects", 0))
	var combo := int(data.get("best_combo", 0))
	var acc := 0.0 if hits <= 0 else float(perfects) / float(hits) * 100.0
	_stats_label.text = "HITS %d      PERFECT %d      BEST COMBO %d      ACCURACY %.0f%%" % [hits, perfects, combo, acc]

	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate = Color(1, 1, 1, 0)
	_card.pivot_offset = Vector2(320, 235)
	_card.scale = Vector2(0.94, 0.94)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.22)
	_tween.tween_property(_card, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func dismiss() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false
	modulate = Color(1, 1, 1, 1)


func _look_for(reason: String) -> Array:
	match reason:
		"VICTORY":
			return ["TARGET CLEARED", "You outran the clock."]
		"TIME":
			return ["TIME", "The clock ran out. Every tile counted."]
		"TIME UP":
			return ["TIME UP", "Too slow to reach the target."]
		"ESCAPED":
			return ["ESCAPED", "A tile slipped past the strike line."]
		"MISTAP":
			return ["MISSTEP", "Wrong lane. One tap is all it takes."]
		_:
			return ["RUN OVER", ""]


func _fmt(value: int) -> String:
	var s := str(value)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
