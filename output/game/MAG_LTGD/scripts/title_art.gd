extends Control
class_name TitleArt

## Animated horseshoe-magnet artwork for the title screen.

const Ui := preload("res://scripts/ui_kit.gd")
const AssetLib := preload("res://scripts/assets.gd")

var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	var cx := s.x * 0.5
	var cy := s.y * 0.46
	var w: float = minf(s.x * 0.17, 52.0)
	var r: float = minf(s.x * 0.29, s.y * 0.35)
	var legs: float = s.y * 0.30
	var tip: float = maxf(18.0, w * 0.55)
	var center := Vector2(cx, cy)

	# field arcs
	for i in 3:
		var rr := r + w * 0.5 + 22.0 + float(i) * 20.0
		var pulse := 0.5 + 0.5 * sin(_time * 1.3 - float(i) * 0.7)
		var col := Color(0.42, 0.78, 1.0, 0.08 + 0.07 * pulse)
		draw_arc(center, rr, PI + 0.35, TAU - 0.35, 40, col, 2.0)
		# travelling spark along the arc
		var a := PI + 0.45 + fmod(_time * 0.6 + float(i) * 0.33, 1.0) * (PI - 0.9)
		var p := center + Vector2(cos(a), sin(a)) * rr
		draw_circle(p, 3.5, Color(0.7, 0.95, 1.0, 0.75))
		draw_circle(p, 9.0, Color(0.4, 0.8, 1.0, 0.16))

	# steel body
	var body := Color(0.63, 0.70, 0.80)
	draw_rect(Rect2(cx - r - w * 0.5, cy, w, legs), body, true)
	draw_rect(Rect2(cx + r - w * 0.5, cy, w, legs), body, true)
	draw_arc(center, r, PI, TAU, 56, body, w)
	draw_arc(center, r - w * 0.26, PI, TAU, 56, Color(1, 1, 1, 0.22), w * 0.16)

	# poles
	var pos_rect := Rect2(cx - r - w * 0.5, cy + legs - tip, w, tip)
	var neg_rect := Rect2(cx + r - w * 0.5, cy + legs - tip, w, tip)
	var glow: float = 0.6 + 0.4 * sin(_time * 2.4)
	draw_rect(Rect2(pos_rect.position - Vector2(4, 0), pos_rect.size + Vector2(8, 0)),
		Color(Ui.POS.r, Ui.POS.g, Ui.POS.b, 0.16 * glow), true)
	draw_rect(Rect2(neg_rect.position - Vector2(4, 0), neg_rect.size + Vector2(8, 0)),
		Color(Ui.NEG.r, Ui.NEG.g, Ui.NEG.b, 0.16 * glow), true)
	draw_rect(pos_rect, Ui.POS, true)
	draw_rect(neg_rect, Ui.NEG, true)

	# pole glyphs
	var lw: float = maxf(3.0, w * 0.11)
	var g: float = w * 0.24
	var pc := pos_rect.get_center()
	var nc := neg_rect.get_center()
	draw_line(pc - Vector2(g, 0), pc + Vector2(g, 0), Color.WHITE, lw)
	draw_line(pc - Vector2(0, g), pc + Vector2(0, g), Color.WHITE, lw)
	draw_line(nc - Vector2(g, 0), nc + Vector2(g, 0), Color.WHITE, lw)

	# orbiting crates
	var crate := AssetLib.texture(AssetLib.CRATE)
	for i in 2:
		var ang := _time * 0.7 + float(i) * PI
		var orbit := Vector2(cx + cos(ang) * (r + w * 1.5), cy + 18.0 + sin(ang) * (legs * 0.5 + 24.0))
		var pol := 1 if i == 0 else -1
		var col := Ui.pol_color(pol)
		var sz := 40.0
		draw_circle(orbit, sz * 0.9, Color(col.r, col.g, col.b, 0.14))
		draw_texture_rect(crate, Rect2(orbit - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false,
			col.lerp(Color(1, 1, 1), 0.1))
		var gg := sz * 0.22
		draw_line(orbit - Vector2(gg, 0), orbit + Vector2(gg, 0), Color.WHITE, 3.5)
		if pol > 0:
			draw_line(orbit - Vector2(0, gg), orbit + Vector2(0, gg), Color.WHITE, 3.5)
