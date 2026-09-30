extends Control
## Title screen: a dying signal, a flickering name and a radio-dial play button.

signal navigate(screen: String, payload: Dictionary)

var _t := 0.0
var _scope: ColorRect
var _mat: ShaderMaterial
var _flicker := 1.0
var _next_flicker := 0.0
var _dial_center := Vector2(640, 452)
var _dial_r := 116.0
var _needle := -PI * 0.5
var _needle_speed := 0.35
var _hover := false
var _freq := 98.40
var _quit_rect := Rect2(1030, 640, 170, 40)
var _start_rect := Rect2(0, 0, 0, 0)
var _glitch_off := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := CanvasLayer.new()
	bg.layer = -1
	add_child(bg)
	_scope = ColorRect.new()
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/radio_scope.gdshader")
	_mat.set_shader_parameter("band_min", SignalDB.BAND_MIN)
	_mat.set_shader_parameter("band_max", SignalDB.BAND_MAX)
	_mat.set_shader_parameter("noise_amt", 0.55)
	_mat.set_shader_parameter("sig_f", PackedFloat32Array([93.0, 101.5, 0, 0]))
	_mat.set_shader_parameter("sig_s", PackedFloat32Array([0.35, 0.22, 0, 0]))
	_scope.material = _mat
	bg.add_child(_scope)
	Audio.set_hum(0.12)
	Audio.set_static(0.14, 1.0)
	Audio.set_drone(0.16)


func _process(delta: float) -> void:
	_t += delta
	_freq = SignalDB.BAND_MIN + fposmod(_t * 1.7, SignalDB.BAND_MAX - SignalDB.BAND_MIN)
	_needle += delta * _needle_speed * (3.0 if _hover else 1.0)
	if _t > _next_flicker:
		_next_flicker = _t + randf_range(0.06, 0.6)
		_flicker = randf_range(0.25, 1.0)
		_glitch_off = Vector2(randf_range(-3, 3), randf_range(-2, 2))
	_mat.set_shader_parameter("dial", _freq)
	_mat.set_shader_parameter("lock", 0.3 + 0.3 * sin(_t))
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_start()
		elif event.keycode == KEY_ESCAPE:
			if OS.get_environment("HORROR_NO_QUIT") == "":
				get_tree().quit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var m := (event as InputEventMouseMotion).position
		_hover = m.distance_to(_dial_center) <= _dial_r
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p := (event as InputEventMouseButton).position
		if p.distance_to(_dial_center) <= _dial_r:
			_start()
		elif _quit_rect.has_point(p):
			get_tree().quit()
		else:
			Audio.play("select_005.ogg", -14.0)


func _start() -> void:
	Audio.play("switch_003.ogg", -5.0)
	Audio.play("sweep.wav", -8.0)
	navigate.emit("station", {})


func _draw() -> void:
	# Vignette / room darkness over the static.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.02, 0.62))
	for i in 26:
		var f := float(i) / 26.0
		draw_rect(Rect2(0, size.y * f, size.x, size.y / 26.0 + 2.0), Color(0, 0, 0, 0.035 + f * 0.02))

	# Title.
	var glitch_on: bool = _flicker < 0.55
	var name_col := Color(0.75, 1.0, 0.86, 0.55 + 0.45 * _flicker)
	var cx := size.x * 0.5
	UIKit.text_center(self, Vector2(cx, 96.0), "H O R R O R", 26, Color(0.55, 0.8, 0.72, 0.8))
	if glitch_on:
		UIKit.text_center(self, Vector2(cx + _glitch_off.x, 168.0 + _glitch_off.y), "SIGNAL LOST", 84, Color(0.9, 0.2, 0.3, 0.5))
		UIKit.text_center(self, Vector2(cx - _glitch_off.x, 168.0 - _glitch_off.y), "SIGNAL LOST", 84, Color(0.2, 0.9, 0.7, 0.5))
	UIKit.text_center(self, Vector2(cx, 168.0), "SIGNAL LOST", 84, name_col)

	UIKit.text_center(self, Vector2(cx, 214.0), "STATION K-7   /   BARENTS COAST RELAY   /   02:00", 15, Color(0.45, 0.68, 0.6, 0.8))

	# Receiver readout line.
	var bar := Rect2(cx - 300.0, 246.0, 600.0, 34.0)
	UIKit.draw_bar(self, bar, Color(0.8, 0.85, 0.82, 0.9))
	UIKit.text(self, bar.position + Vector2(18, 23), "%.2f MHz" % _freq, 18, Color(0.75, 1.0, 0.85))
	UIKit.text_right(self, Vector2(bar.end.x - 18, bar.position.y + 23), "SEARCHING FOR DISTRESS CARRIER", 14, Color(0.6, 0.9, 0.78, 0.8))

	_draw_dial()

	# Quit button.
	var hover_q := _quit_rect.has_point(get_local_mouse_position())
	draw_rect(_quit_rect, Color(0.06, 0.1, 0.1, 0.9))
	draw_rect(_quit_rect, Color(0.45, 0.62, 0.56, 1.0 if hover_q else 0.6), false, 2.0)
	UIKit.text_center(self, _quit_rect.get_center(), "QUIT", 16, Color(0.7, 0.9, 0.82))

	UIKit.text_center(self, Vector2(cx, size.y - 26.0), "CC0 ASSETS BY KENNEY + OPEN GAME ART CONTRIBUTORS", 12, Color(0.35, 0.5, 0.45, 0.8))
	UIKit.text(self, Vector2(24, 26), "BUILD 1.0", 12, Color(0.35, 0.5, 0.45, 0.7))
	UIKit.text_right(self, Vector2(size.x - 24, 26), "HEADPHONES RECOMMENDED", 12, Color(0.35, 0.5, 0.45, 0.7))


func _draw_dial() -> void:
	var c := _dial_center
	var r := _dial_r
	# Plinth.
	draw_circle(c, r + 16.0, Color(0.04, 0.07, 0.07, 0.95))
	draw_circle(c, r + 10.0, Color(0.09, 0.15, 0.16, 1.0))
	draw_arc(c, r + 13.0, 0, TAU, 72, Color(0.25, 0.45, 0.42, 0.9), 3.0)
	draw_circle(c, r, Color(0.05, 0.09, 0.1, 1.0))
	# Ticks.
	for i in 36:
		var a := TAU * float(i) / 36.0 - PI * 0.5
		var major := i % 3 == 0
		var inner := r - (14.0 if major else 8.0)
		var col := Color(0.55, 0.9, 0.78, 0.85) if major else Color(0.3, 0.5, 0.45, 0.6)
		draw_line(c + Vector2(cos(a), sin(a)) * inner, c + Vector2(cos(a), sin(a)) * (r - 2.0), col, 2.0)
	# Sweep needle.
	var tip := c + Vector2(cos(_needle), sin(_needle)) * (r - 22.0)
	draw_line(c, tip, Color(1.0, 0.85, 0.5, 0.95), 3.0)
	draw_circle(tip, 5.0, Color(1.0, 0.9, 0.6, 0.95))
	draw_circle(c, 9.0, Color(0.2, 0.3, 0.3))
	draw_circle(c, 4.0, Color(0.6, 0.9, 0.8))
	# Label.
	var glow := 0.55 + 0.45 * sin(_t * 3.0)
	var col := Color(0.6, 1.0, 0.82, 0.7 + 0.3 * glow) if _hover else Color(0.6, 0.95, 0.8, 0.9)
	UIKit.text_center(self, c + Vector2(0, -18), "BEGIN", 30, col)
	UIKit.text_center(self, c + Vector2(0, 16), "WATCH", 30, col)
	if _hover:
		draw_arc(c, r + 6.0, 0, TAU, 72, Color(0.6, 1.0, 0.82, 0.5), 2.0)
	UIKit.text_center(self, c + Vector2(0, r + 34.0), "CLICK THE DIAL OR PRESS ENTER", 14, Color(0.6, 0.85, 0.75, 0.85))
