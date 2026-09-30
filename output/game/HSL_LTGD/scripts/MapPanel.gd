extends Control
# The chart table. Draws the sector chart, grid, placed pins and the
# triangulation geometry. Emits the estimated position when clicked.

signal pin_requested(lat: float, lon: float)

const LAT_MIN := 40.0
const LAT_MAX := 56.0
const LON_MIN := 8.0
const LON_MAX := 24.0
const STATION_LAT := 52.0
const STATION_LON := 18.0

var pins: Array = []
var pending: Dictionary = {}
var show_source := false
var source_geo := Vector2(53.0, 17.5)
var source_lock := 0.0
var corruption := 0.0
var light := 1.0
var sweep := 0.0
var flash := 0.0
var flash_pos := Vector2.ZERO
var alarm := 0.0
var cursor_enabled := true

var _hover := Vector2(-9999.0, -9999.0)
var _t := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_font = load("res://assets/fonts/KenneyFutureNarrow.ttf")
	set_process(true)


func geo_to_local(lat: float, lon: float) -> Vector2:
	var x := (LON_MAX - lon) / (LON_MAX - LON_MIN) * size.x
	var y := (LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * size.y
	return Vector2(x, y)


func local_to_geo(p: Vector2) -> Vector2:
	var lon := LON_MAX - clampf(p.x / maxf(size.x, 1.0), 0.0, 1.0) * (LON_MAX - LON_MIN)
	var lat := LAT_MAX - clampf(p.y / maxf(size.y, 1.0), 0.0, 1.0) * (LAT_MAX - LAT_MIN)
	return Vector2(lat, lon)


func add_pin(id: int, lat: float, lon: float, cache: bool) -> void:
	pins.append({"id": id, "lat": lat, "lon": lon, "cache": cache, "t": 0.0})


func _process(delta: float) -> void:
	_t += delta
	sweep = fmod(sweep + delta * 0.9, TAU)
	flash = maxf(0.0, flash - delta * 2.2)
	alarm = maxf(0.0, alarm - delta * 1.5)
	if pending.is_empty() and not show_source:
		source_lock = 0.0
	else:
		source_lock = clampf(source_lock + delta * 0.6, 0.0, 1.0)
	for p in pins:
		p["t"] = minf(1.0, float(p["t"]) + delta * 3.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var g := local_to_geo(mb.position)
			pin_requested.emit(g.x, g.y)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2(-9999.0, -9999.0)


func _draw() -> void:
	var s := size
	var dim := lerpf(0.55, 1.0, light)

	# chart paper
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.052, 0.075, 0.086) * dim)
	# sea hatching
	var sea := Color(0.075, 0.115, 0.135) * dim
	var y := 0.0
	while y < s.y:
		draw_line(Vector2(0, y), Vector2(s.x, y + 3.0), Color(sea.r, sea.g, sea.b, 0.35), 1.0)
		y += 9.0

	# land masses
	var land := Color(0.115, 0.128, 0.118) * dim
	var land_hi := Color(0.155, 0.168, 0.150) * dim
	var coast: Array = [
		[Vector2(0.60, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.30), Vector2(0.88, 0.27), Vector2(0.79, 0.21), Vector2(0.72, 0.10), Vector2(0.60, 0.0)],
		[Vector2(0.15, 0.74), Vector2(0.27, 0.69), Vector2(0.32, 0.79), Vector2(0.25, 0.88), Vector2(0.13, 0.83)],
		[Vector2(0.42, 0.50), Vector2(0.51, 0.46), Vector2(0.55, 0.55), Vector2(0.47, 0.61), Vector2(0.40, 0.56)],
		[Vector2(0.84, 0.60), Vector2(0.94, 0.56), Vector2(0.99, 0.68), Vector2(0.90, 0.77), Vector2(0.81, 0.70)]
	]
	for poly in coast:
		var pts := PackedVector2Array()
		for p in poly:
			pts.append(Vector2(p.x * s.x, p.y * s.y))
		draw_colored_polygon(pts, land)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, land_hi, 1.5)
	# skerries
	draw_circle(Vector2(0.34 * s.x, 0.30 * s.y), 3.5, land)
	draw_circle(Vector2(0.63 * s.x, 0.72 * s.y), 2.5, land)
	draw_circle(Vector2(0.72 * s.x, 0.42 * s.y), 2.0, land)

	# latitude / longitude grid
	var grid_col := Color(0.16, 0.30, 0.30, 0.55) * dim
	var lon := LON_MIN
	while lon <= LON_MAX + 0.01:
		var x := geo_to_local(0.0, lon).x
		draw_line(Vector2(x, 0), Vector2(x, s.y), grid_col, 1.0)
		lon += 2.0
	var lat := LAT_MIN
	while lat <= LAT_MAX + 0.01:
		var yy := geo_to_local(lat, 0.0).y
		draw_line(Vector2(0, yy), Vector2(s.x, yy), grid_col, 1.0)
		lat += 2.0
	# heavier equator-ish meridian
	var cx := geo_to_local(0.0, 18.0).x
	draw_line(Vector2(cx, 0), Vector2(cx, s.y), Color(0.24, 0.44, 0.42, 0.5) * dim, 1.0)

	# graticule labels
	if _font != null:
		var lc := Color(0.34, 0.55, 0.52) * dim
		lon = LON_MIN
		while lon <= LON_MAX + 0.01:
			var x2 := geo_to_local(0.0, lon).x
			var txt := "%dW" % int(lon)
			draw_string(_font, Vector2(x2 + 3.0, 11.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lc)
			lon += 4.0
		lat = LAT_MIN
		while lat <= LAT_MAX + 0.01:
			var y2 := geo_to_local(lat, 0.0).y
			draw_string(_font, Vector2(3.0, y2 - 3.0), "%dN" % int(lat), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lc)
			lat += 4.0

	# radar sweep from the station
	var st := geo_to_local(STATION_LAT, STATION_LON)
	var sweep_len := s.length() * 0.85
	var dir := Vector2(cos(sweep), sin(sweep))
	var steps := 26
	for i in range(steps):
		var a := float(i) / float(steps)
		var p1 := st + dir * sweep_len * a
		if not Rect2(Vector2.ZERO, s).has_point(p1):
			continue
		draw_line(st, p1, Color(0.25, 0.95, 0.60, 0.30 * (1.0 - a)), 1.0)

	# range rings around home
	for i in range(1, 4):
		var r := float(i) * s.x * 0.16
		draw_arc(st, r, 0.0, TAU, 64, Color(0.22, 0.50, 0.42, 0.28 * dim), 1.0)

	# triangulation geometry
	if pins.size() >= 3:
		var pts := PackedVector2Array()
		for p in pins:
			pts.append(geo_to_local(float(p["lat"]), float(p["lon"])))
		for i in range(pts.size()):
			var a2: Vector2 = pts[i]
			var b2: Vector2 = pts[(i + 1) % pts.size()]
			_dashed_line(a2, b2, Color(0.95, 0.72, 0.30, 0.55), 1.0)
		var centroid := Vector2.ZERO
		for p in pts:
			centroid += p
		centroid /= float(pts.size())
		draw_circle(centroid, 5.0, Color(0.95, 0.35, 0.28, 0.85))
		draw_arc(centroid, 14.0 + sin(_t * 3.0) * 3.0, 0.0, TAU, 32, Color(0.95, 0.35, 0.28, 0.5), 1.5)

	# resolved source marker
	if show_source:
		var sp := geo_to_local(source_geo.x, source_geo.y)
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		draw_arc(sp, 10.0 + pulse * 12.0, 0.0, TAU, 40, Color(1.0, 0.20, 0.16, (0.9 - pulse * 0.5) * source_lock), 2.0)
		draw_arc(sp, 22.0 + pulse * 14.0, 0.0, TAU, 40, Color(1.0, 0.20, 0.16, (0.5 - pulse * 0.3) * source_lock), 1.0)
		draw_line(sp - Vector2(16, 0), sp + Vector2(16, 0), Color(1.0, 0.35, 0.3, source_lock), 1.0)
		draw_line(sp - Vector2(0, 16), sp + Vector2(0, 16), Color(1.0, 0.35, 0.3, source_lock), 1.0)

	# placed pins
	for p in pins:
		var lp := geo_to_local(float(p["lat"]), float(p["lon"]))
		var t := float(p["t"])
		var col: Color = Color(0.98, 0.30, 0.24)
		if bool(p["cache"]):
			col = Color(0.40, 0.95, 0.55)
		draw_line(lp, lp - Vector2(0, 14.0 * t), col, 1.5)
		draw_circle(lp - Vector2(0, 14.0 * t), 4.5 * t, col)
		draw_arc(lp, 7.0 * t, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.6), 1.0)
		if _font != null:
			draw_string(_font, lp + Vector2(7, 4), str(int(p["id"]) + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.92, 0.94, 0.9, 0.85))

	# home station marker
	draw_circle(st, 5.0, Color(0.45, 0.95, 0.90))
	draw_arc(st, 9.0, 0.0, TAU, 24, Color(0.45, 0.95, 0.90, 0.7), 1.0)
	if _font != null:
		draw_string(_font, st + Vector2(11, -6), "KESTREL-9", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.95, 0.92, 0.9))

	# pending target box (a bracket at the estimated spot is NOT drawn; the
	# operator must read the coordinates themselves)

	# hover crosshair
	if cursor_enabled and is_visible_in_tree() and _hover.x > -9000.0:
		var hc := Color(0.55, 0.95, 0.85, 0.55)
		draw_line(Vector2(_hover.x, 0), Vector2(_hover.x, s.y), Color(hc.r, hc.g, hc.b, 0.25), 1.0)
		draw_line(Vector2(0, _hover.y), Vector2(s.x, _hover.y), Color(hc.r, hc.g, hc.b, 0.25), 1.0)
		var box := Rect2(_hover - Vector2(9, 9), Vector2(18, 18))
		draw_rect(box, hc, false, 1.0)

	# flash feedback
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.95, 0.30, 0.25, flash * 0.35))
		draw_arc(flash_pos, 18.0 + (1.0 - flash) * 30.0, 0.0, TAU, 32, Color(0.95, 0.4, 0.3, flash), 2.0)

	# frame
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.30, 0.42, 0.40, 0.85), false, 2.0)
	var corner := Color(0.55, 0.95, 0.80, 0.9)
	var c := 16.0
	draw_line(Vector2(0, 0), Vector2(c, 0), corner, 2.0)
	draw_line(Vector2(0, 0), Vector2(0, c), corner, 2.0)
	draw_line(Vector2(s.x, 0), Vector2(s.x - c, 0), corner, 2.0)
	draw_line(Vector2(s.x, 0), Vector2(s.x, c), corner, 2.0)
	draw_line(Vector2(0, s.y), Vector2(c, s.y), corner, 2.0)
	draw_line(Vector2(0, s.y), Vector2(0, s.y - c), corner, 2.0)
	draw_line(Vector2(s.x, s.y), Vector2(s.x - c, s.y), corner, 2.0)
	draw_line(Vector2(s.x, s.y), Vector2(s.x, s.y - c), corner, 2.0)

	# corruption static
	if corruption > 0.02:
		var n := int(corruption * 34.0)
		for i in range(n):
			var rx := fmod(sin(float(i) * 12.9898 + _t * 3.1) * 43758.5453, 1.0)
			var ry := fmod(sin(float(i) * 78.233 + _t * 2.3) * 12543.113, 1.0)
			rx = absf(rx)
			ry = absf(ry)
			var p := Vector2(rx * s.x, ry * s.y)
			draw_rect(Rect2(p, Vector2(randf_range(6, 40), 1.0)), Color(0.4, 0.95, 0.7, corruption * 0.25))


func _dashed_line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var total := a.distance_to(b)
	if total < 1.0:
		return
	var dash := 7.0
	var gap := 5.0
	var dir := (b - a) / total
	var d := 0.0
	while d < total:
		var e := minf(d + dash, total)
		draw_line(a + dir * d, a + dir * e, col, width)
		d = e + gap
