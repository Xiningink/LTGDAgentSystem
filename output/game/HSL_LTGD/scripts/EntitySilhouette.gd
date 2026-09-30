extends Control
# The thing that was jamming the band. Drawn behind the end card.

var mode := "signal_lost"
var grow := 0.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_t += delta
	grow = minf(1.0, grow + delta * (0.10 if mode == "signal_lost" else 0.16))
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var cx := w * 0.5
	var s := 0.35 + grow * 1.15
	var top := h * 1.02 - h * 0.62 * s
	var halfw := w * 0.10 * s
	var col := Color(0.0, 0.0, 0.0, clampf(0.30 + grow * 0.68, 0.0, 0.96))

	var body := PackedVector2Array([
		Vector2(cx - halfw, h + 40.0),
		Vector2(cx - halfw * 0.85, top + 120.0 * s),
		Vector2(cx - halfw * 0.42, top + 34.0 * s),
		Vector2(cx, top),
		Vector2(cx + halfw * 0.42, top + 34.0 * s),
		Vector2(cx + halfw * 0.85, top + 120.0 * s),
		Vector2(cx + halfw, h + 40.0)
	])
	draw_colored_polygon(body, col)
	draw_circle(Vector2(cx, top + 6.0 * s), halfw * 0.82, col)

	# tendrils reaching toward the panel
	for i in range(6):
		var fi := float(i)
		var off := sin(_t * (0.5 + fi * 0.17) + fi * 1.7) * 90.0
		var a := Vector2(cx + off * 0.2, top + 70.0 * s)
		var b := Vector2(cx + off, h * 0.42 + fi * 26.0)
		draw_line(a, b, Color(col.r, col.g, col.b, col.a * 0.55), 6.0 * s)

	# eyes
	var eye_a := clampf(grow * 1.3, 0.0, 0.85)
	for sgn in [-1.0, 1.0]:
		var ep: Vector2 = Vector2(cx + sgn * 26.0 * s, top + 34.0 * s)
		draw_circle(ep, 4.0 * s, Color(0.95, 0.15, 0.10, eye_a))
		draw_circle(ep, 9.0 * s, Color(0.95, 0.15, 0.10, eye_a * 0.25))
