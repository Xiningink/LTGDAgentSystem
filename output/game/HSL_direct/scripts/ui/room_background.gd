extends Control
## The operator's room: wall gradient, panelled seams, desk edge, console glow,
## drifting dust and a darkness that deepens as the presence grows.

var presence := 0.0
var power_dim := 1.0
var jam := 0.0

var _t := 0.0
var _motes: Array = []
var _glow_tex: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_tex = UIKit.tex("res://assets/fx/glow.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 80:
		_motes.append({
			"p": Vector2(rng.randf(), rng.randf()),
			"s": rng.randf_range(0.5, 1.8),
			"v": rng.randf_range(0.002, 0.014),
			"a": rng.randf_range(0.05, 0.28),
			"ph": rng.randf_range(0.0, TAU),
		})


func _process(delta: float) -> void:
	_t += delta
	for m in _motes:
		m["p"].y -= m["v"] * delta
		m["p"].x += sin(_t * 0.4 + m["ph"]) * 0.00012
		if m["p"].y < -0.02:
			m["p"].y = 1.02
			m["p"].x = fmod(m["p"].x + 0.37, 1.0)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var steps := 56
	for i in steps:
		var f := float(i) / float(steps)
		var c: Color = Palette.ROOM_DEEP.lerp(Palette.ROOM_WALL, smoothstep(0.0, 0.9, f))
		draw_rect(Rect2(0.0, h * f, w, h / float(steps) + 1.5), c)

	# Ceiling shadow.
	draw_rect(Rect2(0, 0, w, h * 0.07), Color(0, 0, 0, 0.5))

	# Wall seams and rivets.
	for i in range(1, 7):
		var x := w * float(i) / 7.0
		draw_rect(Rect2(x - 1.0, 0, 2.0, h * 0.8), Color(0, 0, 0, 0.28))
		draw_rect(Rect2(x + 1.0, 0, 1.0, h * 0.8), Color(1, 1, 1, 0.02))
	draw_line(Vector2(0, h * 0.06), Vector2(w, h * 0.06), Color(0, 0, 0, 0.35), 2.0)

	# Console glow behind the radio desk.
	var glow_col := Color(0.32, 0.95, 0.7, 0.10 * (0.35 + power_dim * 0.65))
	draw_texture_rect(_glow_tex, Rect2(w * 0.52 - 420.0, h * 0.28 - 220.0, 940.0, 620.0), false, glow_col)
	# Warm map lamp.
	draw_texture_rect(_glow_tex, Rect2(w * 0.08 - 120.0, h * 0.34 - 160.0, 620.0, 520.0), false, Color(1.0, 0.72, 0.38, 0.055))

	# Desk.
	var desk_y := h * 0.80
	draw_rect(Rect2(0, desk_y, w, h - desk_y), Color("0b1114"))
	draw_rect(Rect2(0, desk_y, w, 3.0), Color(0.45, 0.62, 0.55, 0.30))
	draw_rect(Rect2(0, desk_y + 3.0, w, 1.0), Color(0, 0, 0, 0.6))
	for i in range(0, int(w), 48):
		draw_line(Vector2(float(i), desk_y + 6.0), Vector2(float(i), h), Color(0, 0, 0, 0.18), 1.0)

	# Dust motes.
	for m in _motes:
		var p: Vector2 = Vector2(m["p"].x * w, m["p"].y * h)
		var a: float = m["a"] * (0.4 + 0.6 * power_dim) * (0.6 + 0.4 * sin(_t * 1.6 + m["ph"]))
		draw_circle(p, m["s"], Color(1.0, 0.98, 0.9, a * 0.35))

	# Presence creeps in at the edges.
	var pr := clampf(presence / 100.0, 0.0, 1.0)
	if pr > 0.01:
		var vig := Color(0, 0, 0, 0.25 + pr * 0.45)
		draw_rect(Rect2(0, 0, w, 40.0 + pr * 60.0), Color(0, 0, 0, pr * 0.4))
		draw_rect(Rect2(0, h - 30.0, w, 30.0), vig * Color(1, 1, 1, 0.4))
	if jam > 0.01:
		draw_rect(Rect2(0, 0, w, h), Color(0.6, 1.0, 0.8, 0.02 * jam))
