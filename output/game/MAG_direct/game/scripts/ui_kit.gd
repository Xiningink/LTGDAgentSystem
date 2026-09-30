## Small factory + style library so the screens stay declarative.
class_name UIKit
extends RefCounted

const FONT_MAIN := "res://assets/fonts/Kenney Future.ttf"
const FONT_NARROW := "res://assets/fonts/Kenney Future Narrow.ttf"
const FONT_MONO := "res://assets/fonts/Kenney Mini Square.ttf"

const PANEL_TEX := "res://assets/ui/panel_square_screws.png"
const PANEL_FLAT_TEX := "res://assets/ui/panel_square.png"
const BUTTON_TEX := "res://assets/ui/button_square_depth.png"

static var _fonts: Dictionary = {}
static var _panel_tex: Texture2D
static var _panel_flat_tex: Texture2D
static var _button_tex: Texture2D
static var _theme: Theme


static func font(kind: String = "main") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path := FONT_MAIN
	match kind:
		"narrow":
			path = FONT_NARROW
		"mono":
			path = FONT_MONO
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path)
	_fonts[kind] = f
	return f


static func panel_texture() -> Texture2D:
	if _panel_tex == null and ResourceLoader.exists(PANEL_TEX):
		_panel_tex = load(PANEL_TEX)
	return _panel_tex


static func flat_panel_texture() -> Texture2D:
	if _panel_flat_tex == null and ResourceLoader.exists(PANEL_FLAT_TEX):
		_panel_flat_tex = load(PANEL_FLAT_TEX)
	return _panel_flat_tex


static func button_texture() -> Texture2D:
	if _button_tex == null and ResourceLoader.exists(BUTTON_TEX):
		_button_tex = load(BUTTON_TEX)
	return _button_tex


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var main := font("main")
	if main != null:
		t.default_font = main
	t.default_font_size = 16
	_theme = t
	return _theme


## Drop cached engine resources so nothing is left alive at shutdown.
static func release() -> void:
	_fonts.clear()
	_theme = null
	_panel_tex = null
	_panel_flat_tex = null
	_button_tex = null


# --- style boxes -------------------------------------------------------------

static func flat(
	bg: Color,
	radius: float = 8.0,
	border: Color = Color(0, 0, 0, 0),
	border_width: float = 0.0,
	shadow: float = 0.0
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	sb.corner_detail = 8
	if border_width > 0.0:
		sb.border_color = border
		sb.set_border_width_all(int(border_width))
	if shadow > 0.0:
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = int(shadow)
		sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	return sb


static func flat_corners(
	bg: Color,
	corners: Vector4,
	border: Color = Color(0, 0, 0, 0),
	border_width: float = 0.0
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = int(corners.x)
	sb.corner_radius_top_right = int(corners.y)
	sb.corner_radius_bottom_right = int(corners.z)
	sb.corner_radius_bottom_left = int(corners.w)
	sb.corner_detail = 8
	if border_width > 0.0:
		sb.border_color = border
		sb.set_border_width_all(int(border_width))
	sb.anti_aliasing = true
	return sb


## Kenney sci-fi glass panel, tinted into the lab palette.
static func panel_style(tint: Color = Palette.PANEL, margin: float = 18.0, screws: bool = true) -> StyleBox:
	var tex := panel_texture() if screws else flat_panel_texture()
	if tex == null:
		return flat(tint, 10.0, Palette.PANEL_EDGE, 2.0)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.modulate_color = tint
	return sb


# --- widgets -----------------------------------------------------------------

static func label(
	text: String,
	size: int = 16,
	color: Color = Palette.TEXT,
	align: int = HORIZONTAL_ALIGNMENT_LEFT,
	font_kind: String = "main"
) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	var f := font(font_kind)
	if f != null:
		l.add_theme_font_override("font", f)
	return l


static func title(text: String, size: int = 34, color: Color = Palette.TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	return l


static func button(text: String, size: int = 18, accent: Color = Palette.SWITCH) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", size)
	var f := font("main")
	if f != null:
		b.add_theme_font_override("font", f)
	b.add_theme_stylebox_override("normal", _button_style(accent, false, false))
	b.add_theme_stylebox_override("hover", _button_style(accent, true, false))
	b.add_theme_stylebox_override("pressed", _button_style(accent, true, true))
	b.add_theme_stylebox_override("disabled", _button_style(Palette.TEXT_FAINT, false, false))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Palette.TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Palette.TEXT_FAINT)
	return b


static func _button_style(accent: Color, hot: bool, down: bool) -> StyleBoxFlat:
	var bg := Palette.PANEL_SOFT.lerp(accent, 0.14 if hot else 0.05)
	if down:
		bg = bg.darkened(0.15)
	var border := accent if hot else Palette.PANEL_EDGE
	var sb := flat(bg, 8.0, border, 2.0, 0.0 if down else 3.0)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 11.0
	sb.content_margin_bottom = 11.0
	return sb


static func icon_button(text: String, size: int = 15) -> Button:
	var b := button(text, size, Palette.SWITCH)
	var sb: StyleBoxFlat = b.get_theme_stylebox("normal")
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return b


static func separator(color: Color = Palette.PANEL_EDGE, height: float = 1.0) -> Control:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(0, height)
	return c


## 0-3 star rating from move efficiency.
static func stars_for(moves: int, par: int) -> int:
	if moves <= par:
		return 3
	if moves <= par + 3:
		return 2
	return 1


static func star_row(stars: int, size_px: float = 18.0) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	for i in range(3):
		var star := StarIcon.new(size_px)
		star.filled = i < stars
		star.color = Palette.GOLD
		box.add_child(star)
	return box
