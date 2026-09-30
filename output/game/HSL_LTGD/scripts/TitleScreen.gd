extends Control
# Title screen: a dead channel with a dial you can turn to tune in.

signal start_requested

var _title_a: Label
var _title_b: Label
var _sub: Label
var _hint: Label
var _readout: Label
var _static: ColorRect
var _dial: Control
var _t := 0.0
var _flick := 1.0
var _started := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var font_ui: Font = load("res://assets/fonts/KenneyFutureNarrow.ttf")
	var font_mono: Font = load("res://assets/fonts/KenneyMiniSquareMono.ttf")
	mouse_filter = Control.MOUSE_FILTER_PASS

	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.016, 0.020)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_static = ColorRect.new()
	_static.set_anchors_preset(Control.PRESET_FULL_RECT)
	_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/radio_scope.gdshader")
	mat.set_shader_parameter("noise_strength", 0.20)
	mat.set_shader_parameter("signal_strength", 0.10)
	mat.set_shader_parameter("jam_level", 0.03)
	mat.set_shader_parameter("glow", Color(0.30, 0.62, 0.50))
	mat.set_shader_parameter("base_color", Color(0.003, 0.005, 0.006))
	_static.material = mat
	add_child(_static)

	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vmat := ShaderMaterial.new()
	vmat.shader = load("res://shaders/glow.gdshader")
	vmat.set_shader_parameter("uv_center", Vector2(0.5, 0.46))
	vmat.set_shader_parameter("uv_scale", Vector2(1.6, 1.0))
	vmat.set_shader_parameter("radius", 0.62)
	vmat.set_shader_parameter("glow_color", Color(0.22, 0.42, 0.36))
	vmat.set_shader_parameter("strength", 0.5)
	vig.material = vmat
	add_child(vig)

	_readout = Label.new()
	_readout.add_theme_font_override("font", font_mono)
	_readout.add_theme_font_size_override("font_size", 13)
	_readout.add_theme_color_override("font_color", Color(0.42, 0.86, 0.68, 0.75))
	_readout.position = Vector2(40, 34)
	_readout.text = "RX-7 // NO CARRIER"
	add_child(_readout)

	_title_a = Label.new()
	_title_a.add_theme_font_override("font", font_ui)
	_title_a.add_theme_font_size_override("font_size", 40)
	_title_a.add_theme_color_override("font_color", Color(0.72, 0.26, 0.20))
	_title_a.text = "HORROR"
	_title_a.position = Vector2(0, 150)
	_title_a.size = Vector2(1280, 52)
	_title_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title_a)

	_title_b = Label.new()
	_title_b.add_theme_font_override("font", font_ui)
	_title_b.add_theme_font_size_override("font_size", 104)
	_title_b.add_theme_color_override("font_color", Color(0.97, 0.95, 0.90))
	_title_b.text = "SIGNAL LOST"
	_title_b.position = Vector2(0, 196)
	_title_b.size = Vector2(1280, 120)
	_title_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title_b)

	_sub = Label.new()
	_sub.add_theme_font_override("font", font_mono)
	_sub.add_theme_font_size_override("font_size", 15)
	_sub.add_theme_color_override("font_color", Color(0.52, 0.62, 0.60))
	_sub.text = "KESTREL-9 RELAY STATION  -  NIGHT WATCH  -  ELEVEN DAYS ALONE"
	_sub.position = Vector2(0, 318)
	_sub.size = Vector2(1280, 24)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_sub)

	_dial = load("res://scripts/StartDial.gd").new()
	_dial.position = Vector2(546, 360)
	_dial.size = Vector2(188, 210)
	_dial.connect("pressed", Callable(self, "_on_start"))
	add_child(_dial)

	_hint = Label.new()
	_hint.add_theme_font_override("font", font_mono)
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.46, 0.70, 0.62, 0.85))
	_hint.text = "SWEEP THE BAND TO HEAR A SIGNAL   |   DRAG THE DIAL   |   STOP HOLDING A CARRIER TO LOCK IT   |   LOG BEARINGS ON THE CHART"
	_hint.position = Vector2(0, 592)
	_hint.size = Vector2(1280, 22)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

	var hint2 := Label.new()
	hint2.add_theme_font_override("font", font_mono)
	hint2.add_theme_font_size_override("font_size", 13)
	hint2.add_theme_color_override("font_color", Color(0.40, 0.56, 0.52, 0.7))
	hint2.text = "MOUSE WHEEL / A-D FINE TUNE  -  SPACE OR CLICK THE KNOB TO BEGIN  -  ESC ABORTS TO TITLE"
	hint2.position = Vector2(0, 616)
	hint2.size = Vector2(1280, 20)
	hint2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint2)

	var foot := Label.new()
	foot.add_theme_font_override("font", font_mono)
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.30, 0.42, 0.40, 0.7))
	foot.text = "KENNEY CC0 LIBRARY ASSETS  -  BUILT WITH GODOT 4"
	foot.position = Vector2(0, 676)
	foot.size = Vector2(1280, 20)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(foot)


func _on_start() -> void:
	if _started:
		return
	_started = true
	start_requested.emit()


func fx_state() -> Dictionary:
	return {
		"glitch": 0.035 + 0.015 * sin(_t * 1.7) + _flick * 0.04,
		"corruption": 0.0,
		"tint": Color(0.96, 1.0, 0.98),
		"brightness": 1.0
	}


func _process(delta: float) -> void:
	_t += delta
	# dying signal flicker on the title
	var n := _rng.randf()
	if n > 0.86:
		_flick = 0.25 + 0.6 * _rng.randf()
	else:
		_flick = lerpf(_flick, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	var a := clampf(1.0 - _flick, 0.15, 1.0)
	_title_b.modulate = Color(1, 1, 1, a)
	_title_a.modulate = Color(1, 1, 1, clampf(1.0 - _flick * 0.6, 0.2, 1.0))
	_sub.modulate = Color(1, 1, 1, 0.55 + 0.45 * a)

	if _static != null:
		var m: ShaderMaterial = _static.material
		m.set_shader_parameter("noise_strength", 0.16 + 0.07 * sin(_t * 2.3) + _flick * 0.22)
		m.set_shader_parameter("signal_strength", 0.06 + 0.06 * sin(_t * 0.7))

	if _readout != null:
		var f := 87.0 + fmod(_t * 3.7, 21.0)
		_readout.text = "RX-7 // %05.2f MHz // %s" % [f, "NO CARRIER" if fmod(_t, 3.0) > 1.2 else "SEARCHING"]


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and (ke.keycode == KEY_SPACE or ke.keycode == KEY_ENTER):
			_on_start()
			get_viewport().set_input_as_handled()
