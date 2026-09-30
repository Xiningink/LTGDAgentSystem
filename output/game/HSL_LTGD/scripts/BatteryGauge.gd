extends Control
# Segmented battery cell gauge with a drain pulse and low-power warnings.

var value := 100.0
var max_value := 100.0
var pulse := 0.0
var warn := 0.0

var _font: Font
var _t := 0.0


func _ready() -> void:
	_font = load("res://assets/fonts/KenneyFutureNarrow.ttf")
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var ratio := clampf(value / maxf(max_value, 1.0), 0.0, 1.0)
	var h := size.y
	# housing
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.042, 0.048))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.26, 0.36, 0.35, 0.9), false, 2.0)

	var segs := 20
	var gap := 2.0
	var inner := Rect2(Vector2(4, 4), Vector2(size.x - 8.0, h - 8.0))
	var sw := (inner.size.x - gap * float(segs - 1)) / float(segs)
	var lit := int(ceil(ratio * float(segs) - 0.001))

	var base := Color(0.30, 0.85, 0.45)
	if ratio < 0.55:
		base = Color(0.95, 0.78, 0.25)
	if ratio < 0.25:
		base = Color(0.95, 0.26, 0.20)

	for i in range(segs):
		var r := Rect2(Vector2(inner.position.x + float(i) * (sw + gap), inner.position.y), Vector2(sw, inner.size.y))
		if i < lit:
			var a := 1.0
			if i == lit - 1:
				a = 0.55 + 0.45 * sin(_t * 8.0)
			var c := base
			if ratio < 0.25:
				c = base.lerp(Color(1.0, 0.6, 0.5), 0.25 + 0.25 * sin(_t * 6.0))
			draw_rect(r, Color(c.r, c.g, c.b, a))
		else:
			draw_rect(r, Color(0.12, 0.14, 0.15))

	if warn > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.95, 0.25, 0.2, 0.20 * warn))

	if _font != null:
		var txt := "%d%%" % int(round(value))
		var tw := 58.0
		draw_rect(Rect2(Vector2(size.x - tw - 3.0, 3.0), Vector2(tw, size.y - 6.0)), Color(0.016, 0.022, 0.026, 0.88))
		draw_string(_font, Vector2(size.x - tw - 3.0, h - 7.0), txt, HORIZONTAL_ALIGNMENT_CENTER, tw, 15, Color(0.92, 0.96, 0.92, 0.95))
