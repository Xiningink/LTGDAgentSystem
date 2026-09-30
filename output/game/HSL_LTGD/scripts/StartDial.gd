extends Control
# The big tuning knob used as the title screen's play button.

signal pressed

var hover := 0.0
var angle := -2.2
var _hovering := false
var _t := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_font = load("res://assets/fonts/KenneyFutureNarrow.ttf")


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovering = true
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovering = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			emit_signal("pressed")
			accept_event()
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and (ke.keycode == KEY_SPACE or ke.keycode == KEY_ENTER):
			emit_signal("pressed")
			accept_event()


func _process(delta: float) -> void:
	_t += delta
	var target := 1.7 if _hovering else -2.2
	angle = lerpf(angle, target, clampf(delta * 4.0, 0.0, 1.0))
	hover = lerpf(hover, 1.0 if _hovering else 0.0, clampf(delta * 5.0, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	var amber := Color(1.0, 0.68, 0.26)
	var glow := Color(amber.r, amber.g, amber.b, 0.15 + 0.35 * hover + 0.06 * sin(_t * 3.0))

	# halo
	for i in range(5):
		draw_circle(c, r * (1.0 + 0.10 * float(i)) * (0.65 + 0.35 * hover), Color(glow.r, glow.g, glow.b, glow.a * (0.16 - float(i) * 0.028)))
	# bezel
	draw_circle(c, r, Color(0.10, 0.105, 0.11))
	draw_arc(c, r, 0.0, TAU, 64, Color(0.30, 0.35, 0.34), 3.0)
	draw_arc(c, r * 0.86, 0.0, TAU, 64, Color(0.20, 0.26, 0.26), 2.0)

	# tick ring
	for i in range(28):
		var a := -PI * 0.5 + TAU * float(i) / 28.0
		var inner := r * 0.86
		var outer := r * (0.96 if i % 7 == 0 else 0.93)
		var col := Color(0.45, 0.85, 0.70) if i % 7 == 0 else Color(0.28, 0.46, 0.44)
		draw_line(c + Vector2(cos(a), sin(a)) * inner, c + Vector2(cos(a), sin(a)) * outer, col, 2.0)

	# knob body
	var knob := r * 0.66
	draw_circle(c, knob, Color(0.075, 0.08, 0.086))
	draw_circle(c, knob, Color(amber.r, amber.g, amber.b, 0.10 + 0.20 * hover))
	draw_arc(c, knob, 0.0, TAU, 48, Color(0.32, 0.36, 0.35), 2.0)
	# grip ridges
	for i in range(16):
		var a2 := TAU * float(i) / 16.0
		draw_line(c + Vector2(cos(a2), sin(a2)) * (knob * 0.30), c + Vector2(cos(a2), sin(a2)) * (knob * 0.86), Color(0.15, 0.16, 0.17), 1.0)

	# pointer
	var dir := Vector2(cos(angle), sin(angle))
	draw_line(c, c + dir * knob * 0.92, Color(1.0, 0.34, 0.24), 4.0)
	draw_circle(c, 6.0, Color(0.9, 0.9, 0.88))
	draw_circle(c, 6.0, Color(1.0, 0.34, 0.24, 0.5 + 0.5 * hover))

	if _font != null:
		draw_string(_font, Vector2(c.x - 70, size.y - 8), "TUNE IN", HORIZONTAL_ALIGNMENT_CENTER, 140.0, 22, Color(0.95, 0.80, 0.52, 0.75 + 0.25 * hover))
