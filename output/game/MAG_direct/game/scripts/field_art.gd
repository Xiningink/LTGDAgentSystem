## Title-screen hero art: a bar magnet with traced dipole field lines and
## energy pulses riding them. Deterministic, so it never distracts.
class_name FieldArt
extends Control

var _lines: Array = []            # Array[PackedVector2Array]
var _built_for: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _sb_cache: Dictionary = {}

var focus: Vector2 = Vector2(0.5, 0.5)
var pole_gap: float = 0.17

const SEEDS := 13
const STEP := 7.0
const MAX_STEPS := 260
const SEED_RADIUS := 26.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	if size != _built_for:
		_build()
	queue_redraw()


func _poles() -> Array:
	var c := size * focus
	var half := size.x * pole_gap
	return [c - Vector2(half, 0.0), c + Vector2(half, 0.0)]


func _field(p: Vector2) -> Vector2:
	var poles := _poles()
	var n: Vector2 = poles[0]
	var s: Vector2 = poles[1]
	var out := Vector2.ZERO
	var dn := p - n
	var ds := p - s
	var ln := maxf(dn.length(), 8.0)
	var ls := maxf(ds.length(), 8.0)
	out += dn / (ln * ln * ln)
	out -= ds / (ls * ls * ls)
	return out


func _build() -> void:
	_built_for = size
	_lines.clear()
	if size.x < 32.0 or size.y < 32.0:
		return
	var poles := _poles()
	var n: Vector2 = poles[0]
	var s: Vector2 = poles[1]
	var bounds := Rect2(Vector2(-40, -40), size + Vector2(80, 80))
	for i in range(SEEDS):
		# fan out of the north pole
		var t := float(i) / float(SEEDS - 1)
		var ang := lerpf(-PI * 0.92, PI * 0.92, t)
		var p := n + Vector2(cos(ang), sin(ang)) * SEED_RADIUS
		var line := PackedVector2Array([p])
		var guard := 0
		while guard < MAX_STEPS:
			guard += 1
			var v := _field(p)
			if v.length_squared() < 1e-12:
				break
			p = p + v.normalized() * STEP
			if not bounds.has_point(p):
				break
			if p.distance_to(s) < SEED_RADIUS * 0.7:
				line.append(s)
				break
			line.append(p)
		if line.size() > 3:
			_lines.append(line)


func _magnet_box(bg: Color, corners: Vector4) -> StyleBoxFlat:
	var key := "%s_%d_%d_%d_%d" % [bg.to_html(), int(corners.x), int(corners.y), int(corners.z), int(corners.w)]
	if _sb_cache.has(key):
		return _sb_cache[key]
	var sb := UIKit.flat_corners(bg, corners, Color(0, 0, 0, 0.35), 2.0)
	_sb_cache[key] = sb
	return sb


func _draw() -> void:
	if size.x < 32.0:
		return
	var poles := _poles()
	var n: Vector2 = poles[0]
	var s: Vector2 = poles[1]

	# --- field lines -------------------------------------------------------
	for i in range(_lines.size()):
		var line: PackedVector2Array = _lines[i]
		var phase := float(i) * 0.7
		var a := 0.16 + 0.10 * sin(_t * 0.8 + phase)
		var col := Color(0.35, 0.85, 0.92, a)
		if line.size() > 1:
			draw_polyline(line, col, 1.4, true)
		# travelling pulse
		var idx := int(fmod(_t * 26.0 + phase * 40.0, float(line.size())))
		for k in range(3):
			var j := idx - k
			if j < 0 or j >= line.size():
				continue
			var fade := 1.0 - float(k) / 3.0
			draw_circle(line[j], 2.4 * fade, Color(0.65, 0.98, 1.0, 0.55 * fade))

	# --- magnet body -------------------------------------------------------
	var w := size.x * 0.30
	var h := maxf(size.y * 0.16, 54.0)
	var body := Rect2(Vector2(n.x - w * 0.18, n.y - h * 0.5), Vector2(w * 1.36, h))
	var r := h * 0.32
	var vec := Vector4(r, 0, 0, r)
	# north half
	draw_style_box(_magnet_box(Palette.NORTH, Vector4(r, 0, 0, r)), Rect2(body.position, Vector2(body.size.x * 0.5, body.size.y)))
	# south half
	draw_style_box(_magnet_box(Palette.SOUTH, Vector4(0, r, r, 0)), Rect2(body.position + Vector2(body.size.x * 0.5, 0), Vector2(body.size.x * 0.5, body.size.y)))
	# gloss + outline
	var gloss := Rect2(body.position + Vector2(4, 4), Vector2(body.size.x - 8, body.size.y * 0.36))
	draw_rect(gloss, Color(1, 1, 1, 0.10))
	draw_style_box(_magnet_box(Color(0, 0, 0, 0), Vector4(r, r, r, r)), body)

	var f := UIKit.font("main")
	if f != null:
		var fs := int(h * 0.52)
		var baseline := body.position.y + body.size.y * 0.5 + fs * 0.35
		draw_string(f, Vector2(body.position.x + body.size.x * 0.25 - 8, baseline), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
		draw_string(f, Vector2(body.position.x + body.size.x * 0.75 - 8, baseline), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))

	# --- pole pulses -------------------------------------------------------
	var pulse := 0.5 + 0.5 * sin(_t * 2.4)
	draw_circle(n, SEED_RADIUS * (0.5 + 0.25 * pulse), Color(Palette.NORTH.r, Palette.NORTH.g, Palette.NORTH.b, 0.10))
	draw_circle(s, SEED_RADIUS * (0.5 + 0.25 * (1.0 - pulse)), Color(Palette.SOUTH.r, Palette.SOUTH.g, Palette.SOUTH.b, 0.10))
