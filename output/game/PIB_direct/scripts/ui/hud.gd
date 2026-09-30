extends Control
class_name Hud

## Heads-up display: side panels, mode stats, prompt, and lane key hints.

const FONT_DISPLAY := preload("res://assets/fonts/KenneyFuture.ttf")
const FONT_NARROW := preload("res://assets/fonts/KenneyFutureNarrow.ttf")
const FONT_MONO := preload("res://assets/fonts/KenneyMiniSquare.ttf")

const LEFT_X := 46.0
const RIGHT_X := 940.0
const RIGHT_W := 294.0
const LANE_KEYS := ["A", "S", "D", "F"]

var _mode_label: Label
var _score_cap: Label
var _score_value: Label
var _combo_label: Label
var _speed_cap: Label
var _best_cap: Label
var _best_value: Label
var _stat_cap: Label
var _stat_value: Label
var _progress_cap: Label
var _progress_value: Label
var _meta_label: Label
var _prompt_label: Label
var _prompt_sub: Label
var _lane_labels: Array[Label] = []

var _data: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_mode_label = _make_label("", FONT_DISPLAY, 22, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_mode_label.position = Vector2(LEFT_X, 38)
	_mode_label.size = Vector2(420, 32)

	_score_cap = _make_label("SCORE", FONT_NARROW, 15, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_LEFT)
	_score_cap.position = Vector2(LEFT_X, 80)
	_score_cap.size = Vector2(300, 22)

	_score_value = _make_label("0", FONT_DISPLAY, 78, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	_score_value.position = Vector2(LEFT_X - 6, 96)
	_score_value.size = Vector2(420, 100)

	_combo_label = _make_label("", FONT_DISPLAY, 30, Palette.NEON[0], HORIZONTAL_ALIGNMENT_LEFT)
	_combo_label.position = Vector2(LEFT_X, 200)
	_combo_label.size = Vector2(420, 44)

	_speed_cap = _make_label("SCROLL", FONT_NARROW, 14, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_LEFT)
	_speed_cap.position = Vector2(LEFT_X, 614)
	_speed_cap.size = Vector2(300, 20)

	_best_cap = _make_label("BEST", FONT_NARROW, 15, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_RIGHT)
	_best_cap.position = Vector2(RIGHT_X, 40)
	_best_cap.size = Vector2(RIGHT_W, 22)

	_best_value = _make_label("0", FONT_DISPLAY, 44, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_best_value.position = Vector2(RIGHT_X, 58)
	_best_value.size = Vector2(RIGHT_W, 58)

	_stat_cap = _make_label("TIME", FONT_NARROW, 15, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_RIGHT)
	_stat_cap.position = Vector2(RIGHT_X, 142)
	_stat_cap.size = Vector2(RIGHT_W, 22)

	_stat_value = _make_label("--", FONT_DISPLAY, 58, Palette.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_stat_value.position = Vector2(RIGHT_X, 160)
	_stat_value.size = Vector2(RIGHT_W, 70)

	_progress_cap = _make_label("", FONT_NARROW, 14, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_RIGHT)
	_progress_cap.position = Vector2(RIGHT_X, 250)
	_progress_cap.size = Vector2(RIGHT_W, 20)

	_progress_value = _make_label("", FONT_MONO, 22, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_progress_value.position = Vector2(RIGHT_X, 266)
	_progress_value.size = Vector2(RIGHT_W, 32)

	_meta_label = _make_label("", FONT_NARROW, 16, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_RIGHT)
	_meta_label.position = Vector2(RIGHT_X, 614)
	_meta_label.size = Vector2(RIGHT_W, 24)

	_prompt_label = _make_label("TAP TO BEGIN", FONT_DISPLAY, 36, Palette.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_label.position = Vector2(0, 292)
	_prompt_label.size = Vector2(1280, 50)

	_prompt_sub = _make_label("press  A  S  D  F  or click a lane", FONT_NARROW, 17, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_sub.position = Vector2(0, 350)
	_prompt_sub.size = Vector2(1280, 28)

	for i in range(Board.LANES):
		var l := _make_label(LANE_KEYS[i], FONT_MONO, 18, Palette.TEXT_FAINT, HORIZONTAL_ALIGNMENT_CENTER)
		var cx := Board.BOARD_LEFT + i * Board.LANE_W + Board.LANE_W * 0.5
		l.position = Vector2(cx - 22.0, 680.0)
		l.size = Vector2(44, 28)
		_lane_labels.append(l)

	set_prompt(false)


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


func _make_label(text: String, font: Font, size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func set_prompt(visible_now: bool) -> void:
	_prompt_label.visible = visible_now
	_prompt_sub.visible = visible_now
	if not visible_now:
		_prompt_label.modulate.a = 1.0


func refresh(data: Dictionary) -> void:
	_data = data
	var cfg: Dictionary = data.get("cfg", {})
	var mode: String = data.get("mode", "endless")
	var accent: Color = Palette.NEON[int(cfg.get("accent", 0)) % Palette.NEON.size()]
	_mode_label.text = str(cfg.get("name", ""))
	_mode_label.add_theme_color_override("font_color", accent)
	_best_value.text = str(data.get("best", 0))
	_score_value.text = _fmt(int(data.get("score", 0)))

	var target := int(data.get("target", 0))
	var time_limit := float(cfg.get("time_limit", 0.0))
	if target > 0:
		_stat_cap.text = "TIME"
		var tl: float = data.get("time_left", 0.0)
		_stat_value.text = "%04.1f" % maxf(tl, 0.0)
		_stat_value.add_theme_color_override("font_color", Palette.DANGER if tl <= 5.0 and bool(data.get("playing", false)) else Palette.TEXT)
		_progress_cap.text = "CLEARED"
		_progress_value.text = "%d / %d" % [int(data.get("hits", 0)), target]
	elif time_limit > 0.0:
		_stat_cap.text = "TIME"
		var tl2: float = data.get("time_left", 0.0)
		_stat_value.text = "%04.1f" % maxf(tl2, 0.0)
		_stat_value.add_theme_color_override("font_color", Palette.DANGER if tl2 <= 5.0 and bool(data.get("playing", false)) else Palette.TEXT)
		_progress_cap.text = "HITS"
		_progress_value.text = str(int(data.get("hits", 0)))
	else:
		_stat_cap.text = "SPEED"
		var mult: float = float(data.get("speed_mult", 1.0))
		_stat_value.text = "%0.2f" % mult
		_stat_value.add_theme_color_override("font_color", Palette.TEXT)
		_progress_cap.text = "HITS"
		_progress_value.text = str(int(data.get("hits", 0)))

	var hits := int(data.get("hits", 0))
	var perfects := int(data.get("perfects", 0))
	var acc := 0.0 if hits <= 0 else float(perfects) / float(hits) * 100.0
	_meta_label.text = "PERFECT %d   ACC %.0f%%" % [perfects, acc]

	var combo := int(data.get("combo", 0))
	if combo >= 2:
		_combo_label.text = "COMBO %d" % combo
		_combo_label.add_theme_color_override("font_color", accent)
	else:
		_combo_label.text = ""

	set_prompt(bool(data.get("prompt", false)))
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _prompt_label.visible:
		var pulse := 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 4.2))
		_prompt_label.modulate.a = pulse
		_prompt_sub.modulate.a = 0.55 + 0.45 * pulse


func _draw() -> void:
	# Side panel shading to separate the HUD gutters from the patterned backdrop.
	draw_rect(Rect2(0, 0, Board.BOARD_LEFT, 720), Color(0.02, 0.02, 0.03, 0.74), true)
	draw_rect(Rect2(Board.BOARD_RIGHT, 0, 1280.0 - Board.BOARD_RIGHT, 720), Color(0.02, 0.02, 0.03, 0.74), true)
	draw_line(Vector2(Board.BOARD_LEFT, 0), Vector2(Board.BOARD_LEFT, 720), Color(1, 1, 1, 0.07), 1.0)
	draw_line(Vector2(Board.BOARD_RIGHT, 0), Vector2(Board.BOARD_RIGHT, 720), Color(1, 1, 1, 0.07), 1.0)

	# Speed bar (left panel).
	var cfg: Dictionary = _data.get("cfg", {})
	var base_speed := float(cfg.get("base_speed", 240.0))
	var max_speed := float(cfg.get("max_speed", 1000.0))
	var speed := float(_data.get("speed", base_speed))
	var frac := clampf((speed - base_speed) / maxf(max_speed - base_speed, 1.0), 0.0, 1.0)
	var speed_bg := Rect2(LEFT_X, 638, 294, 8)
	draw_rect(speed_bg, Color(1, 1, 1, 0.07), true)
	var accent: Color = Palette.NEON[int(cfg.get("accent", 0)) % Palette.NEON.size()]
	draw_rect(Rect2(speed_bg.position, Vector2(speed_bg.size.x * maxf(frac, 0.03), speed_bg.size.y)), accent, true)
	for i in range(1, 4):
		var tx := speed_bg.position.x + speed_bg.size.x * float(i) / 4.0
		draw_line(Vector2(tx, speed_bg.position.y), Vector2(tx, speed_bg.position.y + speed_bg.size.y), Color(0, 0, 0, 0.5), 2.0)

	# Target progress (right panel).
	var target := int(_data.get("target", 0))
	if target > 0:
		var pf := clampf(float(_data.get("hits", 0)) / float(target), 0.0, 1.0)
		var pb := Rect2(RIGHT_X, 296, RIGHT_W, 10)
		draw_rect(pb, Color(1, 1, 1, 0.07), true)
		draw_rect(Rect2(pb.position, Vector2(pb.size.x * pf, pb.size.y)), accent, true)

	# Lane key hint boxes.
	for i in range(Board.LANES):
		var cx := Board.BOARD_LEFT + i * Board.LANE_W + Board.LANE_W * 0.5
		var box := Rect2(cx - 20.0, 678.0, 40.0, 32.0)
		draw_rect(box, Color(1, 1, 1, 0.035), true)
		draw_rect(box, Palette.GRID_STRONG, false, 1.0)
