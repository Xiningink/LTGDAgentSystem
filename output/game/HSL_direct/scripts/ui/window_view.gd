extends Control
## The window. Black sea, fading stars and something that gets closer as the
## presence climbs.

var presence := 0.0
var chapter := 1
var battery := 100.0
var jam := 0.0

var _t := 0.0
var _stars: Array = []
var _blink := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for i in 46:
		_stars.append({
			"p": Vector2(rng.randf(), rng.randf_range(0.05, 0.55)),
			"r": rng.randf_range(0.6, 1.7),
			"b": rng.randf_range(0.15, 0.75),
			"ph": rng.randf_range(0.0, TAU),
		})


func _process(delta: float) -> void:
	_t += delta
	_blink = maxf(0.0, _blink - delta)
	if _blink <= 0.0 and randf() < 0.004:
		_blink = 0.12
	queue_redraw()


func _glass_rect() -> Rect2:
	return Rect2(12, 12, size.x - 24, size.y - 24)


func _draw() -> void:
	# Frame.
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d1619"))
	var glass := _glass_rect()
	# Outside: sky gradient then sea.
	var steps := 30
	for i in steps:
		var f := float(i) / float(steps)
		var c: Color = Color("03060c").lerp(Color("0a1420"), f)
		draw_rect(Rect2(glass.position.x, glass.position.y + glass.size.y * f, glass.size.x, glass.size.y / float(steps) + 1.0), c)
	# Moon and cloud.
	var moon := glass.position + Vector2(glass.size.x * 0.74, glass.size.y * 0.20)
	draw_circle(moon, 40.0, Color(0.5, 0.66, 0.78, 0.10))
	draw_circle(moon, 24.0, Color(0.75, 0.85, 0.92, 0.45))
	draw_circle(moon + Vector2(8, 5), 22.0, Color(0.04, 0.07, 0.11, 0.92))
	var horizon := glass.position.y + glass.size.y * 0.62
	draw_rect(Rect2(glass.position.x, horizon, glass.size.x, glass.size.y - (horizon - glass.position.y)), Color("061019"))
	# Distant water glow so anything standing out there reads as a silhouette.
	for i in 20:
		var f := float(i) / 20.0
		draw_rect(Rect2(glass.position.x, horizon + f * 46.0, glass.size.x, 46.0 / 20.0 + 1.0), Color(0.28, 0.46, 0.55, 0.13 * (1.0 - f)))
	for i in 14:
		var rf := float(i) / 14.0
		draw_rect(Rect2(moon.x - 18.0 + rf * 4.0, horizon + rf * 46.0, 36.0 - rf * 8.0, 46.0 / 14.0 + 1.0), Color(0.55, 0.72, 0.88, 0.075 * (1.0 - rf)))
	draw_line(Vector2(glass.position.x, horizon), Vector2(glass.end.x, horizon), Color(0.45, 0.62, 0.7, 0.7), 1.0)
	# Faint sea glints.
	for i in 7:
		var y := horizon + 6.0 + float(i) * 7.0
		var gl := 0.05 + 0.05 * sin(_t * 0.7 + float(i))
		draw_line(Vector2(glass.position.x + 20.0 + float(i) * 12.0, y), Vector2(glass.end.x - 30.0 - float(i) * 9.0, y), Color(0.3, 0.55, 0.6, gl), 1.0)

	# Stars.
	for s in _stars:
		var p: Vector2 = glass.position + Vector2(s["p"].x * glass.size.x, s["p"].y * glass.size.y)
		var tw: float = s["b"] * (0.55 + 0.45 * sin(_t * 1.3 + s["ph"]))
		draw_circle(p, s["r"], Color(0.8, 0.88, 1.0, tw))

	# Something outside: silhouette that grows with the presence.
	var vis := clampf((presence - 8.0) / 74.0, 0.0, 1.0)
	if vis > 0.002:
		_draw_entity(glass, horizon, vis)
	# Secondary shapes drift past in later chapters.
	if chapter >= 2:
		_draw_drifter(glass, horizon)

	# Rain / condensation streaks on the glass.
	for i in 9:
		var x := glass.position.x + fmod(float(i) * 79.0 + _t * (6.0 + float(i)), glass.size.x)
		draw_line(Vector2(x, glass.position.y + 6.0), Vector2(x - 8.0, glass.position.y + 46.0 + float(i) * 6.0), Color(0.6, 0.75, 0.8, 0.05), 1.0)

	# Glass sheen.
	draw_line(glass.position + Vector2(10, 8), glass.end - Vector2(30, 24), Color(1, 1, 1, 0.028), 14.0)

	# Mullions.
	var mid_x := glass.position.x + glass.size.x * 0.5
	draw_rect(Rect2(mid_x - 4.0, glass.position.y, 8.0, glass.size.y), Color("0d1619"))
	draw_rect(Rect2(glass.position.x, glass.position.y + glass.size.y * 0.34, glass.size.x, 7.0), Color("0d1619"))

	# Frame edges.
	draw_rect(Rect2(Vector2.ZERO, size), Color("18262a"), false, 3.0)
	draw_rect(glass, Color(0, 0, 0, 0.55), false, 2.0)
	UIKit.draw_corner_ticks(self, Rect2(4, 4, size.x - 8, size.y - 8), Color(0.35, 0.6, 0.55, 0.35), 14.0, 2.0)

	if jam > 0.01:
		draw_rect(glass, Color(0.7, 1.0, 0.85, 0.05 * jam))
	if battery < 18.0:
		var f := 1.0 - battery / 18.0
		draw_rect(glass, Color(0, 0, 0, 0.25 * f))


func _draw_entity(glass: Rect2, horizon: float, vis: float) -> void:
	var cx := glass.position.x + glass.size.x * (0.42 + 0.07 * sin(_t * 0.19))
	var base_y := horizon + 6.0
	var h := glass.size.y * (0.30 + 0.95 * vis)
	var w := h * 0.34
	var breathe := 1.0 + 0.02 * sin(_t * 0.8)
	h *= breathe
	var pts := PackedVector2Array([
		Vector2(cx - w * 0.52, base_y),
		Vector2(cx - w * 0.50, base_y - h * 0.50),
		Vector2(cx - w * 0.30, base_y - h * 0.70),
		Vector2(cx - w * 0.17, base_y - h * 0.79),
		Vector2(cx - w * 0.19, base_y - h * 0.92),
		Vector2(cx - w * 0.06, base_y - h * 0.99),
		Vector2(cx + w * 0.06, base_y - h * 0.99),
		Vector2(cx + w * 0.19, base_y - h * 0.92),
		Vector2(cx + w * 0.17, base_y - h * 0.79),
		Vector2(cx + w * 0.30, base_y - h * 0.70),
		Vector2(cx + w * 0.50, base_y - h * 0.50),
		Vector2(cx + w * 0.52, base_y),
	])
	var alpha := 0.55 + 0.45 * vis
	draw_colored_polygon(pts, Color(0, 0, 0, alpha))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.35, 0.55, 0.62, 0.35 * vis), 1.0)
	# Eyes.
	if vis > 0.55:
		var ey := base_y - h * 0.90
		var sep := w * 0.10
		var blink := 1.0 if _blink <= 0.0 else 0.15
		draw_circle(Vector2(cx - sep, ey), 1.8 + 1.6 * vis, Color(0.85, 0.95, 1.0, 0.75 * blink))
		draw_circle(Vector2(cx + sep, ey), 1.8 + 1.6 * vis, Color(0.85, 0.95, 1.0, 0.75 * blink))


func _draw_drifter(glass: Rect2, horizon: float) -> void:
	var speed := 9.0 + float(chapter) * 4.0
	var x := glass.position.x + fposmod(_t * speed, glass.size.x + 200.0) - 100.0
	var y := horizon - 14.0 - 6.0 * sin(_t * 0.6)
	var s := 9.0 + float(chapter) * 3.0
	var pts := PackedVector2Array([
		Vector2(x - s, y + s * 0.4),
		Vector2(x - s * 0.4, y - s),
		Vector2(x + s * 0.5, y - s * 0.7),
		Vector2(x + s, y + s * 0.5),
		Vector2(x, y + s * 0.2),
	])
	draw_colored_polygon(pts, Color(0, 0, 0, 0.65))
