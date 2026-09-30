class_name ModalPanel
extends Control
## Reusable modal: title, typed body copy, footer and a row of buttons.

signal pressed(action: String)

var title := ""
var subtitle := ""
var body_lines: Array = []
var footer := ""
var accent := Palette.PHOSPHOR
var buttons: Array = []
var dismissible := false

var _t := 0.0
var _chars := 0.0
var _speed := 70.0
var _flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chars = 0.0
	Audio.play("bong_001.ogg", -8.0)


func total_chars() -> int:
	var n := 0
	for l in body_lines:
		n += String(l).length()
	return n


func skip() -> void:
	_chars = float(total_chars()) + 1.0


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 3.0)
	if _chars <= float(total_chars()):
		_chars += _speed * delta
	queue_redraw()


func _panel_rect() -> Rect2:
	var w: float = minf(860.0, size.x - 120.0)
	var line_h := 27.0
	var h: float = 150.0 + float(body_lines.size()) * line_h
	if not footer.is_empty():
		h += 34.0
	if not buttons.is_empty():
		h += 74.0
	h = minf(h, size.y - 80.0)
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)


func _button_rects() -> Array:
	var out: Array = []
	if buttons.is_empty():
		return out
	var r := _panel_rect()
	var n := buttons.size()
	var gap := 16.0
	var bw: float = minf(260.0, (r.size.x - 60.0 - gap * float(n - 1)) / float(n))
	var total := bw * float(n) + gap * float(n - 1)
	var x := r.position.x + (r.size.x - total) * 0.5
	var y := r.end.y - 56.0
	for i in n:
		out.append(Rect2(x + float(i) * (bw + gap), y, bw, 40.0))
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p := (event as InputEventMouseButton).position
		if _chars <= float(total_chars()):
			skip()
			return
		var rects := _button_rects()
		for i in rects.size():
			if (rects[i] as Rect2).has_point(p):
				var b: Dictionary = buttons[i]
				if b.get("enabled", true):
					Audio.play("confirmation_002.ogg", -7.0)
					pressed.emit(String(b["id"]))
				else:
					Audio.play("error_004.ogg", -12.0)
				return
		if dismissible:
			pressed.emit("dismiss")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.62))
	var r := _panel_rect()
	draw_rect(r.grow(6.0), Color(0, 0, 0, 0.5))
	draw_style_box(UIKit.panel_box(Color(0.09, 0.15, 0.17)), r)
	draw_rect(r, accent, false, 2.0)
	UIKit.draw_corner_ticks(self, r.grow(-4.0), Color(accent.r, accent.g, accent.b, 0.7), 20.0, 2.0)
	# Header band.
	draw_rect(Rect2(r.position.x + 2.0, r.position.y + 2.0, r.size.x - 4.0, 44.0), Color(accent.r * 0.10, accent.g * 0.10, accent.b * 0.10, 1.0))
	UIKit.text_center(self, Vector2(r.get_center().x, r.position.y + 30.0), title, 30, accent)
	if not subtitle.is_empty():
		UIKit.text_center(self, Vector2(r.get_center().x, r.position.y + 62.0), subtitle, 15, Color(0.6, 0.78, 0.7))

	var y := r.position.y + 100.0
	var used := 0.0
	for l in body_lines:
		var s := String(l)
		var keep := int(clampf(_chars - used, 0.0, float(s.length())))
		UIKit.text(self, Vector2(r.position.x + 40.0, y), s.substr(0, keep), 18, Palette.TEXT, UIKit.font_mono())
		used += float(s.length())
		y += 27.0

	if not footer.is_empty():
		UIKit.text(self, Vector2(r.position.x + 40.0, r.end.y - (78.0 if not buttons.is_empty() else 30.0)), footer, 15, Color(0.62, 0.8, 0.72), UIKit.font_mono())

	var rects := _button_rects()
	for i in rects.size():
		var br: Rect2 = rects[i]
		var b: Dictionary = buttons[i]
		var enabled: bool = b.get("enabled", true)
		var col: Color = accent if enabled else Color(0.3, 0.36, 0.34)
		var hover := br.has_point(get_local_mouse_position())
		draw_rect(br, Color(col.r * (0.22 if hover else 0.12), col.g * (0.22 if hover else 0.12), col.b * (0.22 if hover else 0.12), 1.0))
		draw_rect(br, col, false, 2.0)
		UIKit.text_center(self, br.get_center() + Vector2(0, 1), String(b["label"]), 17, col)
	if _flash > 0.0:
		draw_rect(r, Color(accent.r, accent.g, accent.b, 0.15 * _flash))
