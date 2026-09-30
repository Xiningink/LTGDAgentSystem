extends Control
class_name LabBackdrop

## Animated laboratory backdrop shared by every screen: a deep gradient,
## a machined grid, drifting lab structures and slow floating crates.

var _time := 0.0
var _gradient: GradientTexture2D = null
var _structures: Array = []
var _crates: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color(0.055, 0.078, 0.114))
	grad.set_color(1, Color(0.016, 0.024, 0.039))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 256
	_gradient = tex

	# deterministic decoration layout
	var seeds := [0.12, 0.31, 0.55, 0.74, 0.9, 0.44]
	for i in seeds.size():
		_structures.append({
			"x": seeds[i],
			"tex": Assets.texture(Assets.DECO[i % Assets.DECO.size()]),
			"scale": 0.55 + 0.35 * float((i * 7) % 5) / 5.0,
			"alpha": 0.10 + 0.05 * float(i % 3),
		})
	for i in 5:
		_crates.append({
			"x": 0.08 + 0.2 * float(i),
			"y": 0.12 + 0.17 * float((i * 3) % 4),
			"pol": 1 if i % 2 == 0 else -1,
			"spin": 0.25 + 0.1 * float(i),
			"scale": 0.42 + 0.08 * float(i % 3),
		})


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	draw_texture_rect(_gradient, Rect2(Vector2.ZERO, s), false, Color(1, 1, 1, 1))

	# machined grid
	var step := 64.0
	var grid_color := Color(0.35, 0.55, 0.7, 0.055)
	var x := fmod(_time * 4.0, step)
	while x < s.x:
		draw_line(Vector2(x, 0), Vector2(x, s.y), grid_color, 1.0)
		x += step
	var y := 0.0
	while y < s.y:
		draw_line(Vector2(0, y), Vector2(s.x, y), grid_color, 1.0)
		y += step

	# lab structures along the floor
	for st in _structures:
		var tex: Texture2D = st.tex
		if tex == null:
			continue
		var w: float = float(tex.get_width()) * float(st.scale)
		var h: float = float(tex.get_height()) * float(st.scale)
		var pos := Vector2(st.x * s.x - w * 0.5, s.y - h + 6.0)
		draw_texture_rect(tex, Rect2(pos, Vector2(w, h)), false, Color(0.5, 0.7, 0.9, st.alpha))

	# floating crates with polarity glows
	var crate_tex := Assets.texture(Assets.CRATE)
	for c in _crates:
		var bob := sin(_time * 0.6 + float(c.pol)) * 10.0
		var center := Vector2(c.x * s.x, c.y * s.y + bob)
		var sz: float = 64.0 * float(c.scale)
		var col := UiKit.pol_color(c.pol)
		draw_circle(center, sz * 0.72, Color(col.r, col.g, col.b, 0.10))
		var tr := Transform2D(float(c.spin) * sin(_time * 0.4 + float(c.x)), center)
		draw_set_transform_matrix(tr)
		draw_texture_rect(crate_tex, Rect2(-Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false,
			Color(col.r, col.g, col.b, 0.6).lerp(Color(1, 1, 1, 0.6), 0.30))
		draw_set_transform_matrix(Transform2D.IDENTITY)

	# top glow + bottom vignette
	draw_rect(Rect2(0, 0, s.x, 120.0), Color(0.15, 0.45, 0.75, 0.07), true)
	draw_rect(Rect2(0, s.y - 160.0, s.x, 160.0), Color(0.0, 0.0, 0.0, 0.28), true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
