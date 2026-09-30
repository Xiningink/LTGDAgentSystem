class_name UIKit
extends RefCounted
## Small static toolkit: fonts, style boxes, textured bars and draw helpers.

const FONT_HEADER := "res://assets/fonts/KenneyFutureNarrow.ttf"
const FONT_BODY := "res://assets/fonts/KenneyFuture.ttf"
const FONT_MONO := "res://assets/fonts/KenneyMiniSquareMono.ttf"
const FONT_SQUARE := "res://assets/fonts/KenneyMiniSquare.ttf"

const PANEL_TEX := "res://assets/ui/extra/panel_rectangle.png"
const PANEL_SCREW_TEX := "res://assets/ui/extra/panel_rectangle_screws.png"
const PANEL_SQUARE_TEX := "res://assets/ui/extra/panel_square.png"
const GLASS_TEX := "res://assets/ui/extra/panel_glass.png"
const BTN_TEX := "res://assets/ui/extra/button_rectangle_depth.png"
const BTN_SQUARE_TEX := "res://assets/ui/extra/button_square_depth.png"

const BAR_L := "res://assets/ui_oga/bar_left.png"
const BAR_M := "res://assets/ui_oga/bar_mid.png"
const BAR_R := "res://assets/ui_oga/bar_right.png"
const GRILL_L := "res://assets/ui_oga/grill_left.png"
const GRILL_M := "res://assets/ui_oga/grill_mid.png"
const GRILL_R := "res://assets/ui_oga/grill_right.png"

static var _fonts := {}
static var _tex := {}
static var _boxes := {}


static func font(path: String) -> FontFile:
	if not _fonts.has(path):
		_fonts[path] = load(path)
	return _fonts[path]


static func font_header() -> FontFile:
	return font(FONT_HEADER)


static func font_mono() -> FontFile:
	return font(FONT_MONO)


static func font_body() -> FontFile:
	return font(FONT_BODY)


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]


static func panel_box(modulate: Color = Color.WHITE, tex_path: String = PANEL_TEX, margin: int = 12, content: int = 14) -> StyleBoxTexture:
	var key := "%s|%s|%d|%d" % [tex_path, modulate.to_html(), margin, content]
	if not _boxes.has(key):
		var sb := StyleBoxTexture.new()
		sb.texture = tex(tex_path)
		sb.texture_margin_left = margin
		sb.texture_margin_right = margin
		sb.texture_margin_top = margin
		sb.texture_margin_bottom = margin
		sb.modulate_color = modulate
		sb.content_margin_left = content
		sb.content_margin_right = content
		sb.content_margin_top = content
		sb.content_margin_bottom = content
		_boxes[key] = sb
	return _boxes[key]


static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, f: Font = null, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	ci.draw_string(f if f != null else font_header(), pos, s, align, width, size, col)


static func text_center(ci: CanvasItem, center: Vector2, s: String, size: int, col: Color, f: Font = null) -> void:
	var use := f if f != null else font_header()
	var w := use.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var asc := use.get_ascent(size)
	var desc := use.get_descent(size)
	ci.draw_string(use, center + Vector2(-w * 0.5, (asc - desc) * 0.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func text_right(ci: CanvasItem, right: Vector2, s: String, size: int, col: Color, f: Font = null) -> void:
	var use := f if f != null else font_header()
	var w := use.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(use, Vector2(right.x - w, right.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Draws the OGA three-piece metal bar stretched across rect.
static func draw_bar(ci: CanvasItem, rect: Rect2, tint: Color = Color.WHITE, left: String = BAR_L, mid: String = BAR_M, right: String = BAR_R) -> void:
	var lt := tex(left)
	var mt := tex(mid)
	var rt := tex(right)
	var cap_l := float(lt.get_width())
	var cap_r := float(rt.get_width())
	var h := rect.size.y
	var ly := rect.position.y + (h - lt.get_height()) * 0.5
	var my := rect.position.y + (h - mt.get_height()) * 0.5
	var ry := rect.position.y + (h - rt.get_height()) * 0.5
	ci.draw_texture(lt, Vector2(rect.position.x, ly), tint)
	var x := rect.position.x + cap_l
	var end := rect.end.x - cap_r
	while x < end - 0.5:
		var remain := end - x
		if remain >= mt.get_width():
			ci.draw_texture(mt, Vector2(x, my), tint)
			x += mt.get_width()
		else:
			var region := Rect2(0, 0, remain, mt.get_height())
			ci.draw_texture_rect_region(mt, Rect2(x, my, remain, mt.get_height()), region, tint)
			x = end
	ci.draw_texture(rt, Vector2(end, ry), tint)


## Fills rect with a tiled texture (used for static / grunge overlays).
static func draw_tiled(ci: CanvasItem, rect: Rect2, t: Texture2D, tint: Color) -> void:
	var tw := float(t.get_width())
	var th := float(t.get_height())
	if tw <= 0.0 or th <= 0.0:
		return
	var y := rect.position.y
	while y < rect.end.y:
		var h := minf(th, rect.end.y - y)
		var x := rect.position.x
		while x < rect.end.x:
			var w := minf(tw, rect.end.x - x)
			ci.draw_texture_rect_region(t, Rect2(x, y, w, h), Rect2(0, 0, w, h), tint)
			x += tw
		y += th


static func draw_corner_ticks(ci: CanvasItem, rect: Rect2, col: Color, length: float = 10.0, width: float = 2.0) -> void:
	var p := rect.position
	var e := rect.end
	ci.draw_line(p, p + Vector2(length, 0), col, width)
	ci.draw_line(p, p + Vector2(0, length), col, width)
	ci.draw_line(Vector2(e.x, p.y), Vector2(e.x - length, p.y), col, width)
	ci.draw_line(Vector2(e.x, p.y), Vector2(e.x, p.y + length), col, width)
	ci.draw_line(Vector2(p.x, e.y), Vector2(p.x + length, e.y), col, width)
	ci.draw_line(Vector2(p.x, e.y), Vector2(p.x, e.y - length), col, width)
	ci.draw_line(e, e - Vector2(length, 0), col, width)
	ci.draw_line(e, e - Vector2(0, length), col, width)
