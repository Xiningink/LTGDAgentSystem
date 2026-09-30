extends Control
# Hand drawn operator room: wall, door, window frame, shelf, desk and the
# radio console chassis. Every colour is scaled by the current light level so
# the whole room dims when the operator throttles the power.

var light := 1.0
var flicker := 0.0
var escalation := 0
var corruption := 0.0
var entity := 0.0
var door_alarm := 0.0
var jam := 0.0

const WINDOW_VIEW := Rect2(120, 84, 330, 150)
const WINDOW_FRAME := Rect2(106, 70, 358, 178)
const DOOR := Rect2(26, 88, 64, 176)
const RADIO := Rect2(24, 268, 508, 296)

var _font: Font
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/fonts/KenneyFutureNarrow.ttf")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _col(r: float, g: float, b: float, a: float = 1.0) -> Color:
	var amb := Color(0.014, 0.018, 0.026)
	var c := Color(r, g, b)
	var out := amb + c * light
	if corruption > 0.02:
		out = out.lerp(Color(0.10, 0.30, 0.22), corruption * 0.10 * (0.5 + 0.5 * sin(_t * 7.0)))
	return Color(out.r, out.g, out.b, a)


func _draw() -> void:
	var w := 1280.0
	var h := 720.0

	# ---------------- wall ----------------
	draw_rect(Rect2(0, 0, w, h), _col(0.055, 0.058, 0.066))
	var bands := 26
	for i in range(bands):
		var t := float(i) / float(bands)
		var y := 56.0 + t * 620.0
		var c := _col(0.085 - t * 0.035, 0.088 - t * 0.035, 0.098 - t * 0.038)
		draw_rect(Rect2(0, y, w, 620.0 / float(bands) + 1.0), c)

	# wall panel seams on the left column
	var seam := _col(0.13, 0.135, 0.145, 0.55)
	draw_line(Vector2(100, 60), Vector2(100, 640), seam, 1.0)
	draw_line(Vector2(540, 60), Vector2(540, 640), seam, 1.0)
	draw_line(Vector2(560, 60), Vector2(560, 700), seam, 1.0)
	draw_line(Vector2(1000, 60), Vector2(1000, 700), seam, 1.0)
	draw_line(Vector2(1010, 60), Vector2(1010, 700), seam, 1.0)

	# ---------------- door ----------------
	draw_rect(Rect2(DOOR.position.x - 6, DOOR.position.y - 6, DOOR.size.x + 12, DOOR.size.y + 12), _col(0.14, 0.15, 0.16))
	draw_rect(DOOR, _col(0.075, 0.082, 0.092))
	draw_rect(Rect2(DOOR.position.x + 8, DOOR.position.y + 10, DOOR.size.x - 16, DOOR.size.y - 20), _col(0.10, 0.11, 0.12), false, 2.0)
	# porthole
	var port := Vector2(DOOR.position.x + DOOR.size.x * 0.5, DOOR.position.y + 46)
	draw_circle(port, 16.0, _col(0.03, 0.035, 0.045))
	draw_arc(port, 16.0, 0.0, TAU, 28, _col(0.28, 0.30, 0.32), 2.0)
	# handle
	draw_rect(Rect2(DOOR.position.x + DOOR.size.x - 18, DOOR.position.y + 110, 8, 26), _col(0.35, 0.36, 0.34))
	# keypad + lock light
	var kp := Rect2(DOOR.position.x + 14, DOOR.position.y + 136, 36, 28)
	draw_rect(kp, _col(0.06, 0.07, 0.08))
	draw_rect(kp, _col(0.30, 0.34, 0.34), false, 1.0)
	for r in range(3):
		for c2 in range(3):
			draw_rect(Rect2(kp.position.x + 5 + c2 * 9, kp.position.y + 5 + r * 7, 5, 4), _col(0.35, 0.40, 0.40, 0.8))
	var lock_col := Color(0.95, 0.22, 0.18) if door_alarm <= 0.0 else Color(1.0, 0.5, 0.2)
	var blink := 0.55 + 0.45 * sin(_t * 2.4)
	draw_circle(Vector2(DOOR.position.x + DOOR.size.x - 14, DOOR.position.y + 16), 4.0, Color(lock_col.r, lock_col.g, lock_col.b, blink))

	# ---------------- window ----------------
	var f := WINDOW_FRAME
	var v := WINDOW_VIEW
	var frame_col := _col(0.20, 0.21, 0.215)
	draw_rect(Rect2(f.position.x, f.position.y, f.size.x, v.position.y - f.position.y), frame_col)
	draw_rect(Rect2(f.position.x, v.end.y, f.size.x, f.end.y - v.end.y), frame_col)
	draw_rect(Rect2(f.position.x, v.position.y, v.position.x - f.position.x, v.size.y), frame_col)
	draw_rect(Rect2(v.end.x, v.position.y, f.end.x - v.end.x, v.size.y), frame_col)
	# mullions
	draw_rect(Rect2(v.position.x + v.size.x * 0.5 - 3, v.position.y, 6, v.size.y), frame_col)
	draw_rect(Rect2(v.position.x, v.position.y + v.size.y * 0.5 - 2, v.size.x, 4), frame_col)
	# sill
	draw_rect(Rect2(f.position.x - 8, f.end.y, f.size.x + 16, 12), _col(0.24, 0.25, 0.26))
	draw_rect(Rect2(f.position.x - 8, f.end.y + 12, f.size.x + 16, 4), _col(0.10, 0.11, 0.12))

	# ---------------- shelf ----------------
	var sh := Rect2(470, 168, 74, 10)
	draw_rect(sh, _col(0.22, 0.22, 0.21))
	draw_rect(Rect2(sh.position.x, sh.position.y + 10, sh.size.x, 4), _col(0.10, 0.10, 0.10))
	# dead lantern
	draw_rect(Rect2(484, 140, 20, 28), _col(0.16, 0.17, 0.16))
	draw_rect(Rect2(484, 140, 20, 28), _col(0.30, 0.30, 0.27), false, 1.5)
	draw_arc(Vector2(494, 140), 9.0, PI, TAU, 14, _col(0.30, 0.30, 0.27), 1.5)
	# mug
	draw_rect(Rect2(514, 152, 16, 16), _col(0.20, 0.19, 0.18))
	draw_arc(Vector2(531, 160), 5.0, -PI * 0.5, PI * 0.5, 12, _col(0.20, 0.19, 0.18), 2.0)
	# pinned photograph
	draw_rect(Rect2(476, 186, 26, 32), _col(0.30, 0.29, 0.26))
	draw_rect(Rect2(479, 189, 20, 26), _col(0.08, 0.09, 0.10))
	if escalation >= 3:
		draw_rect(Rect2(479, 189, 20, 26), Color(0.05, 0.05, 0.05, 0.5 + 0.2 * sin(_t * 1.4)))

	# ---------------- desk ----------------
	draw_rect(Rect2(0, 564, 560, 96), _col(0.115, 0.105, 0.095))
	draw_rect(Rect2(0, 564, 560, 6), _col(0.20, 0.19, 0.17))
	draw_rect(Rect2(0, 656, 560, 64), _col(0.03, 0.032, 0.036))
	# cable
	for i in range(10):
		var t2 := float(i) / 9.0
		draw_circle(Vector2(300 + t2 * 180, 566 + sin(t2 * 4.0) * 6.0), 2.0, _col(0.06, 0.06, 0.07))

	# ---------------- radio console ----------------
	draw_rect(Rect2(RADIO.position.x - 4, RADIO.position.y - 4, RADIO.size.x + 8, RADIO.size.y + 8), _col(0.055, 0.06, 0.068))
	draw_rect(RADIO, _col(0.145, 0.150, 0.155))
	draw_rect(Rect2(RADIO.position.x, RADIO.position.y, RADIO.size.x, 4), _col(0.24, 0.25, 0.25))
	draw_rect(Rect2(RADIO.position.x, RADIO.end.y - 4, RADIO.size.x, 4), _col(0.07, 0.075, 0.08))
	# corner screws
	for sx in [RADIO.position.x + 12, RADIO.end.x - 12]:
		for sy in [RADIO.position.y + 12, RADIO.end.y - 12]:
			draw_circle(Vector2(sx, sy), 3.0, _col(0.36, 0.37, 0.36))
			draw_line(Vector2(sx - 2, sy), Vector2(sx + 2, sy), _col(0.10, 0.10, 0.10), 1.0)

	# LCD bezel
	draw_rect(Rect2(44, 286, 210, 56), _col(0.03, 0.035, 0.04))
	draw_rect(Rect2(44, 286, 210, 56), _col(0.30, 0.34, 0.33), false, 1.5)
	# scope bezel
	draw_rect(Rect2(266, 284, 248, 92), _col(0.03, 0.035, 0.04))
	draw_rect(Rect2(266, 284, 248, 92), _col(0.30, 0.34, 0.33), false, 1.5)
	# dial slot
	draw_rect(Rect2(44, 386, 468, 60), _col(0.04, 0.045, 0.05))
	# lock meter trough
	draw_rect(Rect2(44, 452, 468, 14), _col(0.03, 0.035, 0.04))
	# brand plate
	if _font != null:
		draw_string(_font, Vector2(44, 281), "SIGNAL LOST  //  RX-7", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, _col(0.42, 0.60, 0.55))

	# ---------------- something in the room ----------------
	if entity > 0.001:
		var cx := 300.0
		var scale := 0.55 + entity * 1.9
		var top := 640.0 - 250.0 * scale
		var halfw := 42.0 * scale
		var col := Color(0.0, 0.0, 0.0, clampf(entity * 1.4, 0.0, 0.97))
		# torso
		var body := PackedVector2Array([
			Vector2(cx - halfw, 660.0),
			Vector2(cx - halfw * 0.9, top + 70.0 * scale),
			Vector2(cx - halfw * 0.4, top + 20.0 * scale),
			Vector2(cx, top),
			Vector2(cx + halfw * 0.4, top + 20.0 * scale),
			Vector2(cx + halfw * 0.9, top + 70.0 * scale),
			Vector2(cx + halfw, 660.0)
		])
		draw_colored_polygon(body, col)
		# head
		draw_circle(Vector2(cx, top + 4.0 * scale), 22.0 * scale, col)
		# arms
		for sgn in [-1.0, 1.0]:
			var ax: float = cx + sgn * halfw * 0.95
			draw_line(Vector2(ax, top + 72.0 * scale), Vector2(ax + sgn * 30.0 * scale, 700.0), col, 12.0 * scale)
		# faint rim
		draw_arc(Vector2(cx, top + 4.0 * scale), 22.0 * scale, 0.0, TAU, 28, Color(0.55, 0.10, 0.08, 0.35 * entity), 2.0)

	if jam > 0.01:
		draw_rect(Rect2(0, 0, 560, 720), Color(0.75, 0.10, 0.08, 0.06 * jam))
