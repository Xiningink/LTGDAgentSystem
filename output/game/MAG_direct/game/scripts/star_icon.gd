## A five-pointed star drawn as geometry (no glyph dependency).
class_name StarIcon
extends Control

var filled: bool = false:
	set(value):
		filled = value
		queue_redraw()

var color: Color = Palette.GOLD:
	set(value):
		color = value
		queue_redraw()

var points: int = 5
var inner_ratio: float = 0.46


func _init(size_px: float = 18.0) -> void:
	custom_minimum_size = Vector2(size_px, size_px)
	size = custom_minimum_size


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var outer := PackedVector2Array()
	for i in range(points * 2):
		var ang := -PI * 0.5 + TAU * float(i) / float(points * 2)
		var rad := r if i % 2 == 0 else r * inner_ratio
		outer.append(c + Vector2(cos(ang), sin(ang)) * rad)
	if filled:
		draw_colored_polygon(outer, color)
		draw_polyline(outer + PackedVector2Array([outer[0]]), color.lightened(0.35), 1.0, true)
	else:
		draw_polyline(outer + PackedVector2Array([outer[0]]), Color(color.r, color.g, color.b, 0.35), 1.4, true)
