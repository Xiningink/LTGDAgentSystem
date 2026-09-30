extends Control
class_name PolChip

## Small polarity badge used in the HUD (animated field indicator).

var pol := 1
var label_text := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(44, 44)


func set_pol(value: int) -> void:
	pol = value
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var col := Color(0.98, 0.35, 0.32) if pol > 0 else Color(0.30, 0.63, 1.0)
	var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.004)
	var r: float = minf(size.x, size.y) * 0.42
	draw_circle(c, r * 1.25, Color(col.r, col.g, col.b, 0.20 * pulse))
	draw_circle(c, r, Color(0.05, 0.07, 0.11, 0.95))
	draw_arc(c, r, 0.0, TAU, 28, col, 3.0)
	var g := r * 0.5
	draw_line(c - Vector2(g, 0), c + Vector2(g, 0), col.lightened(0.45), 4.0)
	if pol > 0:
		draw_line(c - Vector2(0, g), c + Vector2(0, g), col.lightened(0.45), 4.0)
