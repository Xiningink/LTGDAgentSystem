extends RefCounted
class_name UiKit

## Shared palette, theme and widget factory for Puzzle Magnet Lab.

const BG_DEEP := Color(0.031, 0.043, 0.063)
const PANEL_BG := Color(0.078, 0.106, 0.149)
const PANEL_EDGE := Color(0.176, 0.243, 0.325)
const TEXT := Color(0.855, 0.906, 0.949)
const MUTED := Color(0.467, 0.541, 0.616)
const POS := Color(0.980, 0.353, 0.322)
const NEG := Color(0.302, 0.635, 1.0)
const ACCENT := Color(0.365, 0.882, 0.851)
const GOOD := Color(0.345, 0.878, 0.541)
const AMBER := Color(1.0, 0.702, 0.278)
const DIM := Color(0.24, 0.29, 0.36)

static var _theme: Theme = null


static func pol_color(pol: int) -> Color:
	return POS if pol > 0 else NEG


static func pol_glyph(pol: int) -> String:
	return "+" if pol > 0 else "-"


static func pol_name(pol: int) -> String:
	return "POSITIVE" if pol > 0 else "NEGATIVE"


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = Assets.font(Assets.FONT_HUD)
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_color("font_color", "Button", Color(0.055, 0.086, 0.137))
	t.set_color("font_hover_color", "Button", Color(0.0, 0.02, 0.05))
	t.set_color("font_pressed_color", "Button", Color(0.02, 0.04, 0.08))
	t.set_color("font_disabled_color", "Button", Color(0.42, 0.47, 0.55))
	t.set_font_size("font_size", "Button", 21)
	t.set_color("font_color", "RichTextLabel", TEXT)

	t.set_stylebox("normal", "Button", _btn_box(Assets.UI_BUTTON, Color(0.62, 0.69, 0.78)))
	t.set_stylebox("hover", "Button", _btn_box(Assets.UI_BUTTON, Color(0.92, 0.99, 1.0)))
	t.set_stylebox("pressed", "Button", _btn_box(Assets.UI_BUTTON_DEPTH, Color(0.55, 0.62, 0.72)))
	t.set_stylebox("disabled", "Button", _btn_box(Assets.UI_BUTTON, Color(0.34, 0.38, 0.44)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	_theme = t
	return t


static func _btn_box(path: String, tint: Color) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = Assets.texture(path)
	box.modulate_color = tint
	box.texture_margin_left = 16
	box.texture_margin_right = 16
	box.texture_margin_top = 14
	box.texture_margin_bottom = 14
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.content_margin_left = 26
	box.content_margin_right = 26
	box.content_margin_top = 12
	box.content_margin_bottom = 14
	return box


static func panel_box(tint: Color = Color(0.95, 0.99, 1.0)) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = Assets.texture(Assets.UI_PANEL)
	box.modulate_color = tint
	box.texture_margin_left = 16
	box.texture_margin_right = 16
	box.texture_margin_top = 16
	box.texture_margin_bottom = 16
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	return box


## Dark instrument panel style used for modal cards.
static func card_box() -> StyleBoxTexture:
	return panel_box(Color(0.30, 0.36, 0.46))


static func flat_box(color: Color, radius: int = 10, border: Color = Color(0, 0, 0, 0), border_width: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	if border_width > 0:
		box.border_color = border
		box.set_border_width_all(border_width)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


static func label(text: String, font_size: int = 20, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func heading(text: String, font_size: int = 30, color: Color = ACCENT) -> Label:
	var l := label(text, font_size, color)
	l.add_theme_font_override("font", Assets.font(Assets.FONT_TITLE))
	return l


static func title(text: String, font_size: int = 72, color: Color = Color.WHITE) -> Label:
	var l := heading(text, font_size, color)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.6, 0.9, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 4)
	return l


static func button(text: String, tone: Color = Color(0.62, 0.69, 0.78), min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var box := _btn_box(Assets.UI_BUTTON, tone)
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("hover", _btn_box(Assets.UI_BUTTON, tone.lightened(0.35)))
	b.add_theme_stylebox_override("pressed", _btn_box(Assets.UI_BUTTON_DEPTH, tone.darkened(0.25)))
	b.add_theme_stylebox_override("disabled", _btn_box(Assets.UI_BUTTON, Color(0.3, 0.34, 0.4)))
	if min_width > 0.0:
		b.custom_minimum_size.x = min_width
	b.pressed.connect(func() -> void: Sfx.play("click"))
	return b


static func icon_button(text: String, tone: Color = Color(0.62, 0.69, 0.78)) -> Button:
	var b := button(text, tone, 54.0)
	b.custom_minimum_size.y = 46.0
	b.add_theme_font_size_override("font_size", 17)
	return b


static func panel(color: Color = Color(0.95, 0.99, 1.0), padding: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	var box := panel_box(color)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding * 0.8
	box.content_margin_bottom = padding * 0.8
	p.add_theme_stylebox_override("panel", box)
	return p


static func spacer(expand: bool = true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func vspace(height: float) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size.y = height
	return c


## Rounded-rect helper used by custom _draw() implementations.
static func draw_panel(ci: CanvasItem, rect: Rect2, fill: Color, border: Color, width: float = 2.0, radius: float = 12.0) -> void:
	ci.draw_rect(rect, fill, true)
	if width > 0.0:
		var r := rect.grow(-width * 0.5)
		ci.draw_rect(r, border, false, width)
	# corner accents to soften the box
	ci.draw_rect(Rect2(rect.position, Vector2(radius, width)), border, true)
