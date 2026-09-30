extends Control
## Ending screen. Handles every terminal state: the three choices plus being
## consumed by the presence or losing power entirely.

signal navigate(screen: String, payload: Dictionary)

var ending := "warning"

var _t := 0.0
var _chars := 0.0
var _speed := 130.0
var _quit_rect := Rect2(776, 636, 200, 42)
var _retry_rect := Rect2(304, 636, 220, 42)
var _title_rect := Rect2(540, 636, 220, 42)
var _scope: ColorRect
var _mat: ShaderMaterial
var _accent := Palette.AMBER
var _data: Dictionary = {}
var _lines: Array = []
var _total := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	ending = GameState.ending_id if not GameState.ending_id.is_empty() else "consumed"
	_data = SignalDB.ENDINGS.get(ending, SignalDB.ENDINGS["consumed"])
	_lines = _data["lines"]
	_total = 0
	for l in _lines:
		_total += String(l).length()
	match ending:
		"warning":
			_accent = Color("ffb454")
		"silence":
			_accent = Color("66dcff")
		"answer":
			_accent = Color("b48cff")
		"dark":
			_accent = Color("8aa0a8")
		_:
			_accent = Palette.RED

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
	_mat.set_shader_parameter("noise_amt", 0.4)
	_mat.set_shader_parameter("sig_f", PackedFloat32Array([92.0, 103.0, 0, 0]))
	_mat.set_shader_parameter("sig_s", PackedFloat32Array([0.15, 0.1, 0, 0]))
	_scope.material = _mat
	bg.add_child(_scope)

	if ending == "silence":
		Audio.set_static(0.0)
		Audio.set_drone(0.12)
		Audio.set_carrier(0.0)
	else:
		Audio.set_static(0.16, 0.8)
		Audio.set_drone(0.3)
	Audio.set_hum(0.1)
	Audio.set_heart(0.0)
	Audio.play("bong_001.ogg", -10.0)


func _process(delta: float) -> void:
	_t += delta
	_chars += _speed * delta
	_mat.set_shader_parameter("dial", SignalDB.BAND_MIN + fposmod(_t * 0.8, 20.0))
	mat_set_corrupt()
	queue_redraw()


func mat_set_corrupt() -> void:
	if ending == "consumed" or ending == "dark":
		_mat.set_shader_parameter("glitch", 0.35 + 0.25 * sin(_t * 3.0))
	else:
		_mat.set_shader_parameter("glitch", 0.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p := (event as InputEventMouseButton).position
		if _chars < float(_total):
			_chars = float(_total) + 1.0
			return
		if _retry_rect.has_point(p):
			Audio.play("switch_003.ogg", -6.0)
			navigate.emit("restart", {})
		elif _title_rect.has_point(p):
			Audio.play("switch_007.ogg", -8.0)
			navigate.emit("title", {})
		elif _quit_rect.has_point(p):
			get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.03, 0.72))
	var r := Rect2(180, 90, 920, 520)
	draw_style_box(UIKit.panel_box(Color(0.08, 0.13, 0.15)), r)
	draw_rect(r, _accent, false, 2.0)
	UIKit.draw_corner_ticks(self, r.grow(-4.0), Color(_accent.r, _accent.g, _accent.b, 0.7), 22.0, 2.0)
	draw_rect(Rect2(r.position.x + 2, r.position.y + 2, r.size.x - 4, 60.0), Color(_accent.r * 0.1, _accent.g * 0.1, _accent.b * 0.1, 1.0))
	UIKit.text_center(self, Vector2(r.get_center().x, r.position.y + 42.0), String(_data["title"]), 46, _accent)
	UIKit.text_center(self, Vector2(r.get_center().x, r.position.y + 86.0), String(_data["subtitle"]), 17, Color(0.62, 0.8, 0.72))

	var y := r.position.y + 140.0
	var used := 0.0
	for l in _lines:
		var s := String(l)
		var keep := int(clampf(_chars - used, 0.0, float(s.length())))
		UIKit.text(self, Vector2(r.position.x + 60.0, y), s.substr(0, keep), 18, Palette.TEXT, UIKit.font_mono())
		used += float(s.length())
		y += 30.0

	# Stats.
	var sy := r.end.y - 96.0
	draw_rect(Rect2(r.position.x + 40.0, sy - 22.0, r.size.x - 80.0, 2.0), Color(_accent.r, _accent.g, _accent.b, 0.4))
	UIKit.text(self, Vector2(r.position.x + 44.0, sy + 4.0), String(_data["tag"]), 16, Color(0.7, 0.85, 0.78), UIKit.font_mono())
	var stats := "SIGNALS %d   PINS %d   JAMS SURVIVED %d   JAMS LOST %d   WATCH %s" % [
		GameState.discovered.size(), GameState.pins.size(),
		GameState.jams_survived, GameState.jam_failures, GameState.clock_text()
	]
	UIKit.text(self, Vector2(r.position.x + 44.0, sy + 34.0), stats, 14, Color(0.5, 0.7, 0.64), UIKit.font_mono())

	var typing := _chars < float(_total)
	var fade := 0.42 if typing else 1.0
	_draw_button(_retry_rect, "NEW WATCH", fade)
	_draw_button(_title_rect, "TITLE SCREEN", fade)
	_draw_button(_quit_rect, "QUIT", fade)
	UIKit.text_center(self, Vector2(size.x * 0.5, size.y - 34.0),
		"CLICK TO SKIP" if typing else "THE DIAL IS STILL WARM.", 13,
		Color(0.45, 0.6, 0.55) if typing else Color(0.4, 0.58, 0.52))


func _draw_button(rect: Rect2, label: String, alpha: float) -> void:
	var hover := rect.has_point(get_local_mouse_position())
	var col := Color(_accent.r, _accent.g, _accent.b, (1.0 if hover else 0.72) * alpha)
	draw_rect(rect, Color(_accent.r * 0.14 * alpha, _accent.g * 0.14 * alpha, _accent.b * 0.14 * alpha, 1.0))
	draw_rect(rect, col, false, 2.0)
	UIKit.text_center(self, rect.get_center(), label, 17, col)
