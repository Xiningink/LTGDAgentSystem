extends Control
## Operations chart. Players plot the coordinates logged from each signal.
## Three pins per chapter pull taut and reveal the source.

signal pin_placed(index: int, offset_km: float)
signal pin_rejected()

const TOL := 0.15

const COAST := [
	Vector2(45.60, -63.86),
	Vector2(45.48, -63.70),
	Vector2(45.34, -63.60),
	Vector2(45.18, -63.50),
	Vector2(45.02, -63.44),
	Vector2(44.88, -63.32),
	Vector2(44.74, -63.24),
	Vector2(44.58, -63.17),
	Vector2(44.45, -63.07),
	Vector2(44.36, -63.13),
	Vector2(44.30, -63.19),
	Vector2(44.22, -63.15),
	Vector2(44.12, -63.12),
	Vector2(44.02, -63.20),
	Vector2(43.92, -63.31),
	Vector2(43.80, -63.47),
	Vector2(43.64, -63.64),
	Vector2(43.50, -63.83),
	Vector2(43.40, -63.99),
]

const DECOR := [
	{"lat": 44.44, "lon": -63.26, "tex": "lighthouse", "s": 1.0},
	{"lat": 44.66, "lon": -63.62, "tex": "house", "s": 0.9},
	{"lat": 44.72, "lon": -63.74, "tex": "tower", "s": 1.0},
	{"lat": 44.60, "lon": -63.88, "tex": "treePine", "s": 0.8},
	{"lat": 44.82, "lon": -63.55, "tex": "treePinesSmall", "s": 0.9},
	{"lat": 44.95, "lon": -63.66, "tex": "rocksA", "s": 0.9},
	{"lat": 45.10, "lon": -63.72, "tex": "rocksMountain", "s": 1.1},
	{"lat": 45.30, "lon": -63.86, "tex": "rocksMountain", "s": 1.0},
	{"lat": 44.16, "lon": -63.42, "tex": "treePineTall", "s": 0.85},
	{"lat": 43.98, "lon": -63.62, "tex": "treePinesSmall", "s": 0.8},
	{"lat": 44.52, "lon": -63.44, "tex": "house", "s": 0.8},
	{"lat": 43.72, "lon": -63.76, "tex": "runis", "s": 0.9},
]

const CHAPTER_COLORS := [
	Color("ffb454"),
	Color("66dcff"),
	Color("74f7b4"),
	Color("ff4f5e"),
]

var chapter := 1
var _hover := Vector2.ZERO
var _inside := false
var _t := 0.0
var _reveals: Array = []
var _flash := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.seed = 77


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.0)
	queue_redraw()


func map_rect() -> Rect2:
	return Rect2(48.0, 26.0, size.x - 66.0, size.y - 66.0)


func latlon_to_local(lat: float, lon: float) -> Vector2:
	var uv := SignalDB.map_uv(lat, lon)
	var r := map_rect()
	return r.position + Vector2(uv.x * r.size.x, uv.y * r.size.y)


func local_to_latlon(p: Vector2) -> Vector2:
	var r := map_rect()
	var uv := (p - r.position) / r.size
	return SignalDB.map_latlon(uv)


func trigger_reveal(ch: int) -> void:
	_reveals.append({"ch": ch, "t": 0.0})


func pulse() -> void:
	_flash = 1.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = event.position
		_inside = true
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_place(event.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_inside = false
		queue_redraw()


func _nearest_pending(uv_latlon: Vector2) -> Array:
	var best := -1
	var best_d := 1.0e9
	for i in GameState.pending_pins():
		var s: Dictionary = SignalDB.signals[i]
		var d := Vector2(s["lat"] - uv_latlon.x, s["lon"] - uv_latlon.y).length()
		if d < best_d:
			best_d = d
			best = i
	return [best, best_d]


func _try_place(pos: Vector2) -> void:
	if not map_rect().has_point(pos):
		return
	var ll := local_to_latlon(pos)
	var found := _nearest_pending(ll)
	var index: int = found[0]
	var dist: float = found[1]
	if index >= 0 and dist <= TOL:
		var km := dist * 111.0
		GameState.place_pin(index, km)
		Audio.play("confirmation_002.ogg", -6.0)
		pin_placed.emit(index, km)
	else:
		Audio.play("error_004.ogg", -10.0)
		pin_rejected.emit()


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	var r := map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color("050d0f"))
	draw_rect(r.grow(4.0), Color("02080a"))
	# Sea with a soft depth gradient.
	draw_rect(r, Color("081c26"))
	for i in 18:
		var f := float(i) / 18.0
		draw_rect(Rect2(r.position.x, r.position.y + r.size.y * f, r.size.x, r.size.y / 18.0 + 1.0), Color(0.0, 0.02, 0.03, f * 0.22))
	UIKit.draw_tiled(self, r, UIKit.tex("res://assets/map/textureWater.png"), Color(0.6, 0.9, 1.0, 0.06))
	# Land.
	var poly := PackedVector2Array()
	for p in COAST:
		poly.append(latlon_to_local(p.x, p.y))
	poly.append(latlon_to_local(SignalDB.LAT_MIN, SignalDB.LON_MIN))
	poly.append(latlon_to_local(SignalDB.LAT_MAX, SignalDB.LON_MIN))
	draw_colored_polygon(poly, Color("112418"))
	UIKit.draw_tiled(self, r, UIKit.tex("res://assets/map/textureStone.png"), Color(0.75, 1.0, 0.85, 0.07))
	# Coastline.
	for i in COAST.size() - 1:
		var a := latlon_to_local(COAST[i].x, COAST[i].y)
		var b := latlon_to_local(COAST[i + 1].x, COAST[i + 1].y)
		draw_line(a, b, Color(0.5, 0.82, 0.68, 0.9), 2.0)
		draw_line(a + Vector2(0, 3), b + Vector2(0, 3), Color(0, 0, 0, 0.55), 1.0)
	# Southern and western edge of land to frame.
	var bl := latlon_to_local(SignalDB.LAT_MIN, SignalDB.LON_MIN)
	var tl := latlon_to_local(SignalDB.LAT_MAX, SignalDB.LON_MIN)
	draw_line(poly[poly.size() - 1], bl, Color(0.42, 0.68, 0.6, 0.4), 2.0)
	draw_line(bl, tl, Color(0.42, 0.68, 0.6, 0.4), 2.0)

	_draw_graticule(r)
	_draw_decor()

	# Bearing lines from the station to every pin.
	var station := latlon_to_local(SignalDB.STATION_LAT, SignalDB.STATION_LON)
	for p in GameState.pins:
		var s: Dictionary = SignalDB.signals[p["signal"]]
		var pp := latlon_to_local(s["lat"], s["lon"])
		draw_dashed_line(station, pp, Color(0.5, 0.8, 0.7, 0.18), 1.0, 5.0)

	# Triangulated triangles.
	for ch in GameState.triangulated:
		_draw_triangle(ch)

	# Reveal animations.
	for rev in _reveals:
		_draw_reveal(rev)

	# Pins.
	for p in GameState.pins:
		_draw_pin(p)

	_draw_station(station)
	_draw_hover()

	# Frame.
	draw_rect(Rect2(0, 0, size.x, size.y), Color("152a2a"), false, 3.0)
	UIKit.draw_corner_ticks(self, Rect2(6, 6, size.x - 12, size.y - 12), Color(0.35, 0.62, 0.55, 0.5), 16.0, 2.0)
	draw_rect(Rect2(10.0, 6.0, 168.0, 19.0), Color(0.03, 0.07, 0.07, 0.9))
	UIKit.text(self, Vector2(14, 20), "OPERATIONS CHART", 15, Color(0.55, 0.85, 0.75, 0.9))
	if _flash > 0.0:
		draw_rect(r, Color(1.0, 0.9, 0.6, 0.12 * _flash))


func _draw_graticule(r: Rect2) -> void:
	var lat_start := ceilf(SignalDB.LAT_MIN / 0.25) * 0.25
	var lat_count := int(floor((SignalDB.LAT_MAX - lat_start) / 0.25))
	for i in lat_count + 1:
		var lat := lat_start + float(i) * 0.25
		var major := absf(lat / 0.5 - roundf(lat / 0.5)) < 0.02
		var y := latlon_to_local(lat, SignalDB.LON_MIN).y
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(0.35, 0.62, 0.56, 0.34 if major else 0.13), 1.0)
		if major:
			draw_rect(Rect2(r.position.x - 47.0, y - 9.0, 43.0, 18.0), Color(0.03, 0.08, 0.08, 0.9))
			UIKit.text_right(self, Vector2(r.position.x - 8.0, y + 5.0), "%.1fN" % lat, 13, Color(0.62, 0.9, 0.8, 0.95))
	var lon_start := ceilf(SignalDB.LON_MIN / 0.25) * 0.25
	var lon_count := int(floor((SignalDB.LON_MAX - lon_start) / 0.25))
	for i in lon_count + 1:
		var lon := lon_start + float(i) * 0.25
		var major := absf(lon / 0.5 - roundf(lon / 0.5)) < 0.02
		var x := latlon_to_local(SignalDB.LAT_MIN, lon).x
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0.35, 0.62, 0.56, 0.34 if major else 0.13), 1.0)
		if major:
			draw_rect(Rect2(x - 23.0, r.end.y + 4.0, 46.0, 18.0), Color(0.03, 0.08, 0.08, 0.9))
			UIKit.text_center(self, Vector2(x, r.end.y + 18.0), "%.1fW" % absf(lon), 13, Color(0.62, 0.9, 0.8, 0.95))


func _draw_decor() -> void:
	var r := map_rect()
	for d in DECOR:
		var p := latlon_to_local(d["lat"], d["lon"])
		var t := UIKit.tex("res://assets/map/%s.png" % d["tex"])
		var s: float = d["s"] * 0.62
		var sz := Vector2(t.get_width(), t.get_height()) * s
		draw_texture_rect(t, Rect2(p - sz * 0.5, sz), false, Color(0.82, 1.0, 0.9, 0.72))
	# Compass rose.
	var t := UIKit.tex("res://assets/map/compass.png")
	var cs := 74.0
	draw_texture_rect(t, Rect2(r.end.x - cs - 10.0, r.end.y - cs - 10.0, cs, cs), false, Color(0.8, 1.0, 0.9, 0.66))
	# Plotting table corner marks.
	UIKit.draw_corner_ticks(self, map_rect().grow(-2.0), Color(0.3, 0.6, 0.52, 0.35), 14.0, 1.0)


func _draw_station(p: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	draw_circle(p, 34.0 + pulse * 8.0, Color(0.45, 1.0, 0.7, 0.05 + 0.05 * pulse))
	draw_arc(p, 26.0, 0, TAU, 40, Color(0.45, 1.0, 0.7, 0.18), 1.0)
	draw_circle(p, 16.0 + pulse * 6.0, Color(0.45, 1.0, 0.7, 0.10 + 0.12 * pulse))
	draw_circle(p, 5.0, Color(0.55, 1.0, 0.75, 0.95))
	var d := PackedVector2Array([
		p + Vector2(0, -14), p + Vector2(11, 0), p + Vector2(0, 14), p + Vector2(-11, 0)
	])
	draw_polyline(d + PackedVector2Array([d[0]]), Color(0.55, 1.0, 0.75, 0.9), 2.0)
	draw_rect(Rect2(p.x - 22.0, p.y - 34.0, 44.0, 17.0), Color(0.03, 0.09, 0.08, 0.9))
	UIKit.text_center(self, p + Vector2(0, -21.0), "K-7", 14, Color(0.6, 1.0, 0.78, 1.0))


func _draw_pin(p: Dictionary) -> void:
	var s: Dictionary = SignalDB.signals[p["signal"]]
	var pos := latlon_to_local(s["lat"], s["lon"])
	var ch: int = int(s["chapter"])
	var col: Color = CHAPTER_COLORS[clampi(ch - 1, 0, 3)]
	var r := map_rect()
	if not r.grow(16.0).has_point(pos):
		return
	draw_circle(pos, 9.0, Color(col.r, col.g, col.b, 0.15))
	draw_circle(pos, 4.5, col)
	draw_line(pos, pos + Vector2(0, -14), col, 2.0)
	draw_circle(pos + Vector2(0, -14), 2.6, col)
	UIKit.text_center(self, pos + Vector2(0, 4), str(p["signal"] + 1), 11, Color(0.02, 0.05, 0.04))


func _draw_triangle(ch: int) -> void:
	var pts: Array = []
	for p in GameState.pins:
		if int(SignalDB.signals[p["signal"]]["chapter"]) == ch:
			var s: Dictionary = SignalDB.signals[p["signal"]]
			pts.append(latlon_to_local(s["lat"], s["lon"]))
	if pts.size() < 3:
		return
	var col: Color = CHAPTER_COLORS[clampi(ch - 1, 0, 3)]
	for i in pts.size():
		draw_line(pts[i], pts[(i + 1) % pts.size()], Color(col.r, col.g, col.b, 0.5), 1.5)
	var c: Vector2 = (pts[0] + pts[1] + pts[2]) / 3.0
	draw_circle(c, 4.0, col)
	var src: Dictionary = SignalDB.source(ch)
	var t: Texture2D = null
	match String(src["icon"]):
		"ship":
			t = UIKit.tex("res://assets/map/ship.png")
		"tower":
			t = UIKit.tex("res://assets/map/watchtower.png")
		_:
			t = UIKit.tex("res://assets/map/skull.png")
	if t != null:
		var sz := Vector2(t.get_width(), t.get_height()) * 0.5
		draw_texture_rect(t, Rect2(c - sz * 0.5, sz), false, Color(1.0, 0.85, 0.6, 0.95))
	UIKit.text_center(self, c + Vector2(0, -22), String(src["name"]), 13, Color(1.0, 0.85, 0.6, 0.95))


func _draw_reveal(rev: Dictionary) -> void:
	var ch: int = rev["ch"]
	var t: float = rev["t"]
	if t > 3.0:
		return
	var pts: Array = []
	for p in GameState.pins:
		if int(SignalDB.signals[p["signal"]]["chapter"]) == ch:
			var s: Dictionary = SignalDB.signals[p["signal"]]
			pts.append(latlon_to_local(s["lat"], s["lon"]))
	if pts.size() < 3:
		return
	var c: Vector2 = (pts[0] + pts[1] + pts[2]) / 3.0
	var col: Color = CHAPTER_COLORS[clampi(ch - 1, 0, 3)]
	var ring := fposmod(t, 1.2) / 1.2
	draw_arc(c, 20.0 + ring * 90.0, 0, TAU, 48, Color(col.r, col.g, col.b, (1.0 - ring) * 0.6), 2.0)
	draw_arc(c, 12.0 + fposmod(t + 0.4, 1.2) / 1.2 * 70.0, 0, TAU, 40, Color(col.r, col.g, col.b, 0.25), 1.5)


func _draw_hover() -> void:
	if not _inside:
		return
	var r := map_rect()
	if not r.has_point(_hover):
		return
	var ll := local_to_latlon(_hover)
	var found := _nearest_pending(ll)
	var dist: float = found[1]
	var state := ""
	var col := Color(1, 1, 1, 0.25)
	if found[0] >= 0 and dist <= TOL:
		state = "LOCK"
		col = Color(0.55, 1.0, 0.75, 0.9)
	elif found[0] >= 0 and dist <= TOL * 1.8:
		state = "WARM"
		col = Color(1.0, 0.8, 0.4, 0.7)
	draw_line(Vector2(_hover.x, r.position.y), Vector2(_hover.x, r.end.y), col * Color(1, 1, 1, 0.5), 1.0)
	draw_line(Vector2(r.position.x, _hover.y), Vector2(r.end.x, _hover.y), col * Color(1, 1, 1, 0.5), 1.0)
	draw_circle(_hover, 6.0, Color(col.r, col.g, col.b, 0.15))
	var label := "%s  %s" % [SignalDB.format_lat(ll.x), SignalDB.format_lon(ll.y)]
	if not state.is_empty():
		label += "   [%s]" % state
	UIKit.text(self, Vector2(_hover.x + 10.0, _hover.y - 8.0), label, 13, col)
