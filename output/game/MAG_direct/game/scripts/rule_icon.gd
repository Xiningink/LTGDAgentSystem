## Tiny illustrated diagrams used by the "how to play" screen.
class_name RuleIcon
extends Control

var kind: String = "move"
var _t: float = 0.0


func _init(what: String = "move", size_px: Vector2 = Vector2(150, 112)) -> void:
	kind = what
	custom_minimum_size = size_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _cell(index: int) -> Rect2:
	var cols := 3
	var rows := 2
	var s := minf(size.x / float(cols), size.y / float(rows))
	var ox := (size.x - s * cols) * 0.5
	var oy := (size.y - s * rows) * 0.5
	var x := index % cols
	var y := index / cols
	return Rect2(Vector2(ox + x * s, oy + y * s), Vector2(s, s))


func _center(i: int) -> Vector2:
	return _cell(i).position + _cell(i).size * 0.5


func _offset(rect: Rect2, by: Vector2) -> Rect2:
	return Rect2(rect.position + by, rect.size)


func _grid() -> void:
	for i in range(6):
		var rect := _cell(i).grow(-2.0)
		draw_style_box(UIKit.flat(Palette.FLOOR_A if i % 2 == 0 else Palette.FLOOR_B, 5.0, Palette.FLOOR_EDGE, 1.0), rect)


func _sprite(i: int, base: Color, deep: Color, label: String, scale: float = 0.62) -> void:
	var c := _center(i)
	var s := _cell(i).size.x * scale
	var rect := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
	draw_style_box(UIKit.flat(deep, s * 0.24, Color(0, 0, 0, 0), 0.0), _offset(rect, Vector2(0, 2)))
	draw_style_box(UIKit.flat(base, s * 0.24, base.lightened(0.4), 2.0), rect)
	if label != "":
		var f := UIKit.font("main")
		if f != null:
			var dim := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.42))
			draw_string(f, c - Vector2(dim.x * 0.5, -dim.y * 0.32), label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.42), Color(1, 1, 1, 0.92))


func _magnet(i: int, pol: String, scale: float = 0.66) -> void:
	var c := _center(i)
	var s := _cell(i).size.x * scale
	var rect := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
	var col := Palette.polarity_color(pol)
	var deep := Palette.polarity_deep(pol)
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	draw_circle(c, s * (0.70 + 0.05 * pulse), Color(col.r, col.g, col.b, 0.16))
	draw_style_box(UIKit.flat(deep.darkened(0.35), s * 0.24, col.lightened(0.35), 2.0), rect)
	var inner := rect.grow(-s * 0.12)
	draw_style_box(UIKit.flat(col, s * 0.16, Color(0, 0, 0, 0), 0.0), inner)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.34)), Color(1, 1, 1, 0.16))
	var f := UIKit.font("main")
	if f != null:
		var fs := int(s * 0.5)
		var letter := "N" if pol == "N" else "S"
		var dim := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var at := c - Vector2(dim.x * 0.5, -dim.y * 0.32)
		draw_string_outline(f, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(fs / 8, 2), Color(0, 0, 0, 0.45))
		draw_string(f, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.96))


func _player(i: int, pol: String = "N") -> void:
	var c := _center(i)
	var r := _cell(i).size.x * 0.30
	var col := Palette.polarity_color(pol)
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	draw_circle(c, r * (1.3 + 0.06 * pulse), Color(col.r, col.g, col.b, 0.18))
	draw_circle(c, r, col)
	draw_circle(c, r * 0.62, col.darkened(0.3))
	draw_circle(c, r * 0.36, Palette.PLAYER_CORE)


func _arrow(from: Vector2, to: Vector2, color: Color, width: float = 3.0) -> void:
	draw_line(from, to, color, width, true)
	var dir := (to - from).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var head := 7.0
	draw_colored_polygon(PackedVector2Array([
		to,
		to - dir * head + perp * head * 0.6,
		to - dir * head - perp * head * 0.6,
	]), color)


func _draw() -> void:
	_grid()
	match kind:
		"move":
			_player(0)
			var c := _center(0)
			var s := _cell(0).size.x
			var n := _center(1)
			_arrow(c + Vector2(s * 0.34, 0), n + Vector2(-s * 0.22, 0), Palette.SWITCH)
			_arrow(n + Vector2(s * 0.1, 0), _center(2) + Vector2(-s * 0.36, 0), Palette.SWITCH, 2.0)
		"crate":
			_player(0)
			_sprite(1, Palette.METAL, Palette.METAL_DEEP, "")
			_arrow(_center(0) + Vector2(18, 0), _center(1) + Vector2(-18, 0), Palette.SWITCH)
			_arrow(_center(1) + Vector2(18, 0), _center(2) + Vector2(-20, 0), Palette.METAL.darkened(0.1), 2.4)
		"repel":
			_player(0)
			_magnet(1, "N")
			var s := _cell(0).size.x
			_arrow(_center(0) + Vector2(s * 0.3, 0), _center(1) + Vector2(-s * 0.3, 0), Palette.SWITCH, 2.0)
			_arrow(_center(1) + Vector2(s * 0.3, 0), _center(2) + Vector2(-s * 0.36, 0), Palette.NORTH)
			var mid := (_center(0) + _center(1)) * 0.5
			for i in range(4):
				var y := mid.y - 12 + float(i) * 8.0
				draw_line(Vector2(mid.x - 4, y), Vector2(mid.x + 4, y + 4), Color(1, 0.5, 0.6, 0.7), 1.6)
		"attract":
			_player(0)
			_magnet(1, "S")
			var s2 := _cell(0).size.x
			_arrow(_center(0) + Vector2(s2 * 0.32, -6), _center(1) + Vector2(-s2 * 0.32, -6), Palette.SOUTH, 2.4)
			_arrow(_center(1) + Vector2(-s2 * 0.32, 8), _center(0) + Vector2(s2 * 0.32, 8), Palette.SOUTH, 2.4)
		"hazard":
			for i in [0, 1, 3, 4, 5]:
				pass
			_sprite(3, Palette.METAL, Palette.METAL_DEEP, "")
			_draw_hazard_icon(_cell(4))
			_arrow(_center(3) + Vector2(18, 0), _center(4) + Vector2(-20, 0), Palette.METAL)
			draw_line(_cell(4).position + Vector2(6, 6), _cell(4).end - Vector2(6, 6), Palette.HAZARD, 3.0)
			_player(5)
		"inverter":
			var cell := _cell(1)
			draw_style_box(UIKit.flat(Palette.SWITCH_DEEP, 6.0, Palette.SWITCH, 2.0), cell.grow(-6.0))
			draw_arc(_center(1), cell.size.x * 0.24, _t * 1.5, _t * 1.5 + PI * 1.3, 18, Palette.SWITCH, 3.0, true)
			_player(1)
			var f := UIKit.font("main")
			if f != null:
				var fs3 := int(cell.size.x * 0.34)
				var nd := f.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs3)
				var sd := f.get_string_size("S", HORIZONTAL_ALIGNMENT_LEFT, -1, fs3)
				draw_string(f, _center(0) - Vector2(nd.x * 0.5, 0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs3, Palette.NORTH)
				_arrow(_center(0) + Vector2(14, 0), _center(1) + Vector2(-cell.size.x * 0.34, 0), Palette.TEXT_DIM, 2.0)
				draw_string(f, _center(2) - Vector2(sd.x * 0.5, 0), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, fs3, Palette.SOUTH)
				_arrow(_center(1) + Vector2(cell.size.x * 0.34, 0), _center(2) + Vector2(-14, 0), Palette.TEXT_DIM, 2.0)
		"plate":
			var cell := _cell(1)
			draw_style_box(UIKit.flat(Palette.PLATE, 6.0, Palette.PLATE.lightened(0.3), 2.0), cell.grow(-cell.size.x * 0.24))
			_sprite(1, Palette.METAL, Palette.METAL_DEEP, "")
			_arrow(_center(0) + Vector2(18, 0), _center(1) + Vector2(-18, 0), Palette.SWITCH)
			var gate := _cell(2)
			for i in range(3):
				var bar := Rect2(gate.position.x + gate.size.x * (0.2 + 0.26 * float(i)), gate.position.y + 6, gate.size.x * 0.12, gate.size.y - 12)
				draw_style_box(UIKit.flat(Palette.GATE_DEEP.darkened(0.1), 3.0, Palette.GATE, 1.0), bar)
			draw_line(gate.position + Vector2(0, gate.size.y * 0.5), gate.end - Vector2(0, gate.size.y * 0.5), Color(1, 0.3, 0.4, 0.9), 3.0)
		"exit":
			_player(0)
			var c := _center(1)
			var s := _cell(1).size.x
			draw_circle(c, s * 0.34, Color(Palette.EXIT.r, Palette.EXIT.g, Palette.EXIT.b, 0.2))
			for i in range(3):
				draw_arc(c, s * (0.14 + 0.08 * float(i)), _t * (0.8 + 0.4 * float(i)), _t * (0.8 + 0.4 * float(i)) + PI * 1.3, 16, Palette.EXIT, 2.4, true)
			draw_circle(c, s * 0.08, Palette.EXIT)
			_arrow(_center(0) + Vector2(s * 0.34, 0), c - Vector2(s * 0.36, 0), Palette.SWITCH, 2.4)
		_:
			_player(0)


func _draw_hazard_icon(cell: Rect2) -> void:
	var rect := cell.grow(-3.0)
	draw_style_box(UIKit.flat(Palette.HAZARD_DEEP, 5.0, Palette.HAZARD, 2.0), rect)
	for i in range(6):
		var d := float(i) * 12.0 + fmod(_t * 20.0, 12.0)
		var p1 := Vector2(d, 0) if d <= rect.size.x else Vector2(rect.size.x, d - rect.size.x)
		var p2 := Vector2(0, d) if d <= rect.size.y else Vector2(d - rect.size.y, rect.size.y)
		draw_line(rect.position + p1, rect.position + p2, Color(Palette.HAZARD.r, Palette.HAZARD.g, Palette.HAZARD.b, 0.35), 3.0)
