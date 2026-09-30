extends Control
# Horizontal tuning dial. Mouse drag, wheel or arrow keys move the carrier.

signal tuned(value: float)
signal drag_started
signal drag_ended

const FREQ_MIN := 87.0
const FREQ_MAX := 108.0

var value := 87.0
var locked_freqs: Array = []
var jam_band := Vector2.ZERO
var jam_active := false
var enabled := true
var noise := 0.0
var dragging := false

var _dragging := false
var _font: Font
var _hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_font = load("res://assets/fonts/KenneyFutureNarrow.ttf")


func set_value(v: float, emit_signal_too: bool = false) -> void:
	var nv := clampf(v, FREQ_MIN, FREQ_MAX)
	if absf(nv - value) < 0.0005:
		return
	value = nv
	queue_redraw()
	if emit_signal_too:
		tuned.emit(value)


func _pad() -> float:
	return 20.0


func _x_for(f: float) -> float:
	return _pad() + (clampf(f, FREQ_MIN, FREQ_MAX) - FREQ_MIN) / (FREQ_MAX - FREQ_MIN) * (size.x - _pad() * 2.0)


func _f_for(x: float) -> float:
	var t := clampf((x - _pad()) / maxf(size.x - _pad() * 2.0, 1.0), 0.0, 1.0)
	return FREQ_MIN + t * (FREQ_MAX - FREQ_MIN)


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				dragging = true
				focus_mode = Control.FOCUS_ALL
				grab_focus()
				drag_started.emit()
				set_value(_f_for(mb.position.x), true)
			else:
				if _dragging:
					_dragging = false
					dragging = false
					drag_ended.emit()
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_value(value + 0.05, true)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_value(value - 0.05, true)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			set_value(_f_for(mm.position.x), true)
			accept_event()
	else:
		_hover = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hover = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = false
		queue_redraw()


func _process(delta: float) -> void:
	if not enabled:
		return
	var step := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		step = -1.0
	elif Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		step = 1.0
	if step != 0.0:
		var fine := 0.02 if (Input.is_key_pressed(KEY_SHIFT)) else 0.14
		set_value(value + step * fine * delta * 22.0, true)


func _draw() -> void:
	var cy := size.y * 0.62
	var x0 := _pad()
	var x1 := size.x - _pad()
	var track_h := 12.0

	# faceplate
	draw_rect(Rect2(Vector2(0, 0), size), Color(0.045, 0.052, 0.058))
	draw_rect(Rect2(Vector2(0, 0), size), Color(0.22, 0.30, 0.30, 0.8), false, 1.0)

	# band scale background
	var band_rect := Rect2(Vector2(x0, cy - track_h * 0.5), Vector2(x1 - x0, track_h))
	draw_rect(band_rect, Color(0.075, 0.10, 0.10))
	draw_rect(band_rect, Color(0.20, 0.40, 0.36, 0.7), false, 1.0)

	# jam band
	if jam_active:
		var jx0 := _x_for(jam_band.x)
		var jx1 := _x_for(jam_band.y)
		var jr := Rect2(Vector2(jx0, cy - track_h * 0.5 - 6.0), Vector2(maxf(jx1 - jx0, 2.0), track_h + 12.0))
		draw_rect(jr, Color(0.85, 0.16, 0.12, 0.30 + 0.12 * sin(noise * 9.0)))
		var hx := jr.position.x
		while hx < jr.end.x:
			draw_line(Vector2(hx, jr.end.y), Vector2(minf(hx + 7.0, jr.end.x), jr.position.y), Color(0.95, 0.3, 0.22, 0.55), 1.0)
			hx += 9.0
		draw_rect(jr, Color(0.95, 0.32, 0.22, 0.8), false, 1.0)

	# ticks
	var f := FREQ_MIN
	while f <= FREQ_MAX + 0.001:
		var x := _x_for(f)
		var local := fmod(f, 3.0)
		var is_lab := absf(local) < 0.01 or absf(local - 3.0) < 0.01
		var big := absf(fmod(f, 1.0)) < 0.001
		var h := 12.0 if is_lab else (8.0 if big else 5.0)
		var col := Color(0.35, 0.62, 0.55, 0.95) if is_lab else Color(0.28, 0.48, 0.44, 0.7)
		draw_line(Vector2(x, cy - track_h * 0.5 - 2.0), Vector2(x, cy - track_h * 0.5 - 2.0 - h), col, 1.0)
		if is_lab and _font != null and x > x0 + 14.0 and x < x1 - 14.0:
			draw_string(_font, Vector2(x - 10.0, cy - track_h * 0.5 - 18.0), "%d" % int(f), HORIZONTAL_ALIGNMENT_CENTER, 20.0, 11, Color(0.42, 0.72, 0.64, 0.9))
		f += 0.5

	# locked markers
	for lf in locked_freqs:
		var lx := _x_for(float(lf))
		draw_line(Vector2(lx, cy + track_h * 0.5 + 3.0), Vector2(lx, cy + track_h * 0.5 + 13.0), Color(0.35, 0.98, 0.55, 0.95), 2.0)
		draw_circle(Vector2(lx, cy + track_h * 0.5 + 14.0), 2.2, Color(0.35, 0.98, 0.55))

	# pointer
	var px := _x_for(value)
	var in_jam := jam_active and value >= jam_band.x and value <= jam_band.y
	var pcol := Color(1.0, 0.32, 0.24) if in_jam else Color(1.0, 0.72, 0.30)
	var glow_a := 0.28 + 0.12 * sin(noise * 6.0)
	draw_line(Vector2(px, 6.0), Vector2(px, cy + track_h * 0.5 + 6.0), Color(pcol.r, pcol.g, pcol.b, 0.85), 2.0)
	draw_rect(Rect2(Vector2(px - 9.0, cy - track_h * 0.5 - 4.0), Vector2(18.0, track_h + 8.0)), Color(0.10, 0.11, 0.12))
	draw_rect(Rect2(Vector2(px - 9.0, cy - track_h * 0.5 - 4.0), Vector2(18.0, track_h + 8.0)), pcol, false, 2.0)
	for i in range(4):
		var ry := cy - track_h * 0.5 - 1.0 + float(i) * 3.5
		draw_line(Vector2(px - 6.0, ry), Vector2(px + 6.0, ry), Color(pcol.r, pcol.g, pcol.b, 0.35), 1.0)
	draw_circle(Vector2(px, cy + track_h * 0.5 + 14.0), 6.0, Color(pcol.r, pcol.g, pcol.b, glow_a))

	# knob grub screws
	draw_circle(Vector2(x0 - 6.0, cy), 3.0, Color(0.30, 0.34, 0.34))
	draw_circle(Vector2(x1 + 6.0, cy), 3.0, Color(0.30, 0.34, 0.34))

	if _hover and enabled:
		draw_rect(Rect2(Vector2(0, 0), size), Color(0.45, 0.95, 0.8, 0.25), false, 1.0)
