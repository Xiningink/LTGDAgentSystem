## A single chamber card in the index grid.
class_name LevelCard
extends Button

var index: int = 0
var level: Dictionary = {}
var unlocked: bool = true
var best: int = -1
var chapter_color: Color = Palette.SWITCH
var _hovered: bool = false


func setup(idx: int, data: Dictionary, is_unlocked: bool, best_moves: int) -> void:
	index = idx
	level = data
	unlocked = is_unlocked
	best = best_moves
	chapter_color = Levels.chapter_color(data)
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if unlocked else Control.CURSOR_FORBIDDEN
	custom_minimum_size = Vector2(196, 138)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_text = "Chamber %02d - %s" % [index + 1, String(data.get("name", ""))]
	mouse_entered.connect(func(): _hovered = true; queue_redraw())
	mouse_exited.connect(func(): _hovered = false; queue_redraw())


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var pad := 2.0
	var body := rect.grow(-pad)
	var radius := 10.0

	var bg := Palette.PANEL.lerp(chapter_color, 0.05)
	var border := Palette.PANEL_EDGE
	if unlocked:
		if _hovered:
			bg = Palette.PANEL_SOFT.lerp(chapter_color, 0.16)
			border = chapter_color
		elif best >= 0:
			border = chapter_color.darkened(0.35)
	else:
		bg = Palette.PANEL.darkened(0.35)
		border = Palette.PANEL_EDGE.darkened(0.4)

	draw_style_box(UIKit.flat(bg, radius, border, 2.0, 4.0), body)
	# chapter band
	var band := Rect2(body.position + Vector2(10, 10), Vector2(body.size.x - 20, 4))
	draw_rect(band, chapter_color if unlocked else Palette.TEXT_FAINT.darkened(0.4))

	var f := UIKit.font("main")
	var fm := UIKit.font("mono")
	if f == null:
		return

	var number := "%02d" % (index + 1)
	var num_col := Palette.TEXT if unlocked else Palette.TEXT_FAINT
	draw_string(f, body.position + Vector2(12, 48), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, num_col)

	var name := String(level.get("name", "?"))
	var name_col := Palette.TEXT if unlocked else Palette.TEXT_FAINT
	var name_size := 18
	var available := body.size.x - 24.0
	while name_size > 11 and f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > available:
		name_size -= 1
	draw_string(f, body.position + Vector2(12, 72), name, HORIZONTAL_ALIGNMENT_LEFT, available, name_size, name_col)

	var chapter := Levels.chapter_of(level)
	draw_string(fm, body.position + Vector2(12, 90), String(chapter.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, body.size.x - 24, 11,
		chapter_color if unlocked else Palette.TEXT_FAINT)

	if not unlocked:
		_draw_lock(body.position + Vector2(body.size.x - 30, 36), Palette.TEXT_FAINT)
	else:
		var stars := UIKit.stars_for(best, int(level.get("par", 0))) if best >= 0 else 0
		for i in range(3):
			var c := Vector2(body.position.x + 16 + float(i) * 20.0, body.position.y + 112)
			_star(c, 8.0, i < stars)

		var label := "BEST %d" % best if best >= 0 else "PAR %d" % int(level.get("par", 0))
		var col := Palette.EXIT if best >= 0 else Palette.TEXT_DIM
		draw_string(fm, body.position + Vector2(body.size.x - 74, 118), label, HORIZONTAL_ALIGNMENT_LEFT, 66, 12, col)

		if best >= 0 and best <= int(level.get("par", 0)):
			draw_style_box(UIKit.flat(Color(Palette.GOLD.r, Palette.GOLD.g, Palette.GOLD.b, 0.15), 6.0, Palette.GOLD, 1.0),
				Rect2(body.position + Vector2(body.size.x - 84, 10), Vector2(72, 20)))
			draw_string(fm, body.position + Vector2(body.size.x - 80, 24), "PERFECT", HORIZONTAL_ALIGNMENT_LEFT, 64, 11, Palette.GOLD)


func _star(center: Vector2, r: float, filled: bool) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var ang := -PI * 0.5 + TAU * float(i) / 10.0
		var rad := r if i % 2 == 0 else r * 0.46
		pts.append(center + Vector2(cos(ang), sin(ang)) * rad)
	if filled:
		draw_colored_polygon(pts, Palette.GOLD)
	else:
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(Palette.TEXT_FAINT.r, Palette.TEXT_FAINT.g, Palette.TEXT_FAINT.b, 0.6), 1.2, true)


func _draw_lock(center: Vector2, color: Color) -> void:
	draw_rect(Rect2(center + Vector2(-9, 0), Vector2(18, 14)), color, true)
	draw_arc(center + Vector2(0, 1), 6.5, PI, TAU, 14, color, 3.0, true)
