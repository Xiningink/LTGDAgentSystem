extends Control
class_name TitleScreen

## Title + mode select. Emits `mode_selected` with a mode key.

signal mode_selected(mode_key: String)

const FONT_DISPLAY := preload("res://assets/fonts/KenneyFuture.ttf")
const FONT_NARROW := preload("res://assets/fonts/KenneyFutureNarrow.ttf")
const FONT_MONO := preload("res://assets/fonts/KenneyMiniSquare.ttf")

const MODE_ORDER := ["sprint", "endless", "blitz"]

var _modes: Dictionary = {}
var _best: Dictionary = {}
var _index := 0

var _card_buttons: Array[Button] = []
var _card_name: Array[Label] = []
var _card_best: Array[Label] = []
var _card_status: Array[Label] = []
var _t := 0.0
var _built := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _build() -> void:
	var title := _make_label("IVORY BEATS", FONT_DISPLAY, 110, Palette.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 76)
	title.size = Vector2(1280, 130)
	add_child(title)

	var subtitle := _make_label(
		"R H Y T H M    ·    R E A C T I O N    ·    S U R V I V E",
		FONT_NARROW, 24, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER
	)
	subtitle.position = Vector2(0, 206)
	subtitle.size = Vector2(1280, 34)
	add_child(subtitle)

	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.14)
	rule.position = Vector2(430, 256)
	rule.size = Vector2(420, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)

	var row := HBoxContainer.new()
	row.position = Vector2(150, 300)
	row.size = Vector2(980, 268)
	row.add_theme_constant_override("separation", 30)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	for i in range(MODE_ORDER.size()):
		var card := _make_card(i)
		row.add_child(card)

	var footer := _make_label(
		"↑ ↓  SELECT     ENTER  START     A S D F  PLAY",
		FONT_NARROW, 18, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER
	)
	footer.position = Vector2(0, 632)
	footer.size = Vector2(1280, 28)
	add_child(footer)

	var credit := _make_label(
		"Kenney CC0 type & sound   ·   Godot 4",
		FONT_NARROW, 14, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER
	)
	credit.position = Vector2(0, 682)
	credit.size = Vector2(1280, 22)
	add_child(credit)


func _make_card(index: int) -> Button:
	var accent: Color = Palette.NEON[index % Palette.NEON.size()]
	var b := Button.new()
	b.custom_minimum_size = Vector2(300, 268)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", _card_style(false, accent))
	b.add_theme_stylebox_override("hover", _card_style(true, accent))
	b.add_theme_stylebox_override("pressed", _card_style(true, accent))
	b.add_theme_stylebox_override("focus", _card_style(false, accent))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 26)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vb)

	var mode_key: String = MODE_ORDER[index]
	var cfg: Dictionary = _modes.get(mode_key, {})

	var name_label := _make_label(str(cfg.get("name", mode_key.to_upper())), FONT_DISPLAY, 34, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(name_label)
	_card_name.append(name_label)

	var detail := _make_label(str(cfg.get("detail", "")), FONT_NARROW, 15, accent, HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(detail)

	var tag := _make_label(str(cfg.get("tagline", "")), FONT_NARROW, 17, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size = Vector2(0, 84)
	vb.add_child(tag)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(spacer)

	var best_cap := _make_label("PERSONAL BEST", FONT_NARROW, 13, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(best_cap)

	var best_value := _make_label("0", FONT_DISPLAY, 30, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(best_value)
	_card_best.append(best_value)

	var status := _make_label("SELECT", FONT_NARROW, 14, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(status)
	_card_status.append(status)

	b.pressed.connect(_activate.bind(index))
	b.mouse_entered.connect(_select.bind(index))
	_card_buttons.append(b)
	return b


func _card_style(highlighted: bool, accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL if not highlighted else Color(0.085, 0.085, 0.115, 0.96)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.border_width_left = 3 if highlighted else 1
	sb.border_width_top = 3 if highlighted else 1
	sb.border_width_right = 3 if highlighted else 1
	sb.border_width_bottom = 3 if highlighted else 1
	sb.border_color = accent if highlighted else Palette.PANEL_EDGE
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.35 if highlighted else 0.0)
	sb.shadow_size = 18 if highlighted else 0
	sb.content_margin_left = 6
	sb.content_margin_right = 6
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


func setup(modes: Dictionary, best: Dictionary) -> void:
	_modes = modes
	_best = best
	if not _built:
		_build()
		_built = true
	_refresh_cards()


func move_selection(delta: int) -> void:
	_index = wrapi(_index + delta, 0, MODE_ORDER.size())
	AudioManager.play_click()
	_refresh_cards()


func activate_selected() -> void:
	_activate(_index)


func _select(index: int) -> void:
	if index == _index:
		return
	_index = index
	AudioManager.play_click()
	_refresh_cards()


func _activate(index: int) -> void:
	_index = index
	_refresh_cards()
	AudioManager.play_select()
	emit_signal("mode_selected", MODE_ORDER[index])


func _refresh_cards() -> void:
	for i in range(_card_buttons.size()):
		if i >= MODE_ORDER.size():
			continue
		var mode_key: String = MODE_ORDER[i]
		var accent: Color = Palette.NEON[i % Palette.NEON.size()]
		var selected := i == _index
		_card_buttons[i].add_theme_stylebox_override("normal", _card_style(selected, accent))
		_card_name[i].add_theme_color_override("font_color", accent if selected else Palette.TEXT)
		_card_best[i].text = str(int(_best.get(mode_key, 0)))
		_card_status[i].text = "▶  PLAY" if selected else "SELECT"
		_card_status[i].add_theme_color_override("font_color", accent if selected else Palette.TEXT_FAINT)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Palette.BG)
	# Faint cental lane silhouette.
	for i in range(Board.LANES + 1):
		var x := Board.BOARD_LEFT + i * Board.LANE_W
		draw_line(Vector2(x, 0), Vector2(x, 720), Color(1, 1, 1, 0.035), 2.0 if (i == 0 or i == Board.LANES) else 1.0)
	var drift := fmod(_t * 26.0, Board.SPACING)
	var y := drift - Board.SPACING
	while y < 720.0:
		draw_line(Vector2(Board.BOARD_LEFT, y), Vector2(Board.BOARD_RIGHT, y), Color(1, 1, 1, 0.02), 1.0)
		y += Board.SPACING
	# Vignette bars.
	draw_rect(Rect2(0, 0, 1280, 8), Palette.BG, true)
	draw_rect(Rect2(0, 712, 1280, 8), Palette.BG, true)
