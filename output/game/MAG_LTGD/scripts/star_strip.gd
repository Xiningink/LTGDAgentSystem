extends Control
class_name StarStrip

## Draws a row of rating stars without depending on any glyph in the font.

var total := 3
var filled := 0
var star_radius := 9.0
var gap := 6.0
var color_on := Color(1.0, 0.85, 0.35)
var color_off := Color(0.45, 0.50, 0.58)


func set_stars(filled_count: int, total_count: int = 3) -> void:
	filled = filled_count
	total = total_count
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var step := star_radius * 2.0 + gap
	var width_total := step * float(total) - gap
	var x := (size.x - width_total) * 0.5 + star_radius
	var y := size.y * 0.5
	for i in total:
		_draw_star(Vector2(x + step * float(i), y), star_radius, color_on if i < filled else color_off, i < filled)


func _draw_star(center: Vector2, radius: float, color: Color, glow: bool) -> void:
	if glow:
		draw_circle(center, radius * 1.5, Color(color.r, color.g, color.b, 0.18))
	var pts := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.46
		var a := -PI * 0.5 + PI * float(i) / 5.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, color)
