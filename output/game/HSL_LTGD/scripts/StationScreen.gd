extends Control
# The operator room. Everything the player does happens on one desk.

signal finished(kind: String, stats: Dictionary)
signal abort_requested

const SignalData := preload("res://scripts/SignalData.gd")
const MapPanelScript := preload("res://scripts/MapPanel.gd")
const RoomViewScript := preload("res://scripts/RoomView.gd")
const FreqDialScript := preload("res://scripts/FreqDial.gd")
const BatteryGaugeScript := preload("res://scripts/BatteryGauge.gd")
const RadioAudioScript := preload("res://scripts/RadioAudio.gd")
const SfxScript := preload("res://scripts/Sfx.gd")

const FREQ_MIN := 87.0
const FREQ_MAX := 108.0
const MAX_BATTERY := 100.0
const DRAIN := [0.15, 0.30, 0.55]
const LIGHT_LEVEL := [0.50, 0.80, 1.0]
# LOCK_WINDOW shapes the strength meter curve, CATCH_RADIUS is how far the
# dial will reach out and grab a carrier. Lower power = shorter reach.
const LOCK_WINDOW := [0.26, 0.38, 0.54]
const CATCH_RADIUS := [0.50, 0.85, 1.25]
const POWER_NAME := ["LOW", "MED", "HIGH"]
const SCAN_RANGE := ["NARROW", "STANDARD", "WIDE"]
const CACHE_GAIN := 18.0
const PIN_TOLERANCE := 0.62
const MAX_SIGNALS := 5

# ---- game state ----
var battery := MAX_BATTERY
var power_mode := 1
var freq := 87.0
var lock_progress := 0.0
var signal_strength := 0.0
var locked: Dictionary = {}
var placed: Dictionary = {}
var pin_count := 0
var cache_count := 0
var corruption := 0.0
var time_alive := 0.0

var _tick := 0.0
var _light := 0.8
var _light_target := 0.8
var _flicker := 0.0
var _flash := 0.0
var _flash_col := Color(1, 1, 1, 1)
var _glitch_burst := 0.0
var _ambient_t := 12.0
var _entity := 0.0
var _sequence := 0
var _seq_t := 0.0
var _finished := false
var _step_t := 0.0

var _jam_active := false
var _jam_band := Vector2.ZERO
var _jam_timer := 0.0
var _jam_escape := 0.0
var _jam_cooldown := 0.0
var _next_jam := 22.0

var _type_text := ""
var _type_shown := 0.0
var _whisper := ""
var _whisper_a := 0.0
var _log_lines: Array[String] = []

# ---- nodes ----
var room: Control
var window_view: ColorRect
var glow_layer: ColorRect
var scope: ColorRect
var dial: Control
var gauge: Control
var batt_pct: Label
var map: Control
var readout: RichTextLabel
var lcd_freq: Label
var lcd_state: Label
var lock_fill: ColorRect
var console_status: Label
var coord_label: Label
var bearings_label: Label
var status_label: Label
var whisper_label: Label
var flash_rect: ColorRect
var jam_panel: ColorRect
var jam_hint: Label
var jam_fill: ColorRect
var audio: Node
var sfx: Node
var _font_ui: Font
var _font_mono: Font


func _ready() -> void:
	_font_ui = load("res://assets/fonts/KenneyFutureNarrow.ttf")
	_font_mono = load("res://assets/fonts/KenneyMiniSquareMono.ttf")
	_build()

	audio = RadioAudioScript.new()
	audio.name = "RadioAudio"
	add_child(audio)
	sfx = SfxScript.new()
	sfx.name = "Sfx"
	add_child(sfx)

	_log("WATCH BEGUN. STATION KESTREL-9.")
	_log("CELL BANK AT %d PERCENT." % int(battery))
	_set_readout_note("NO CARRIER.\n\nSWEEP THE BAND WITH THE DIAL.\nA CARRIER SOUNDS LIKE A TONE\nUNDER THE STATIC - HOLD IT\nSTEADY TO DECODE.")
	_refresh_bearings()


# ------------------------------------------------------------------ UI build

func _build() -> void:
	room = RoomViewScript.new()
	room.set_anchors_preset(Control.PRESET_FULL_RECT)
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(room)

	window_view = ColorRect.new()
	window_view.position = Vector2(120, 84)
	window_view.size = Vector2(330, 150)
	window_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/window_night.gdshader")
	wmat.set_shader_parameter("darkness", 1.0)
	wmat.set_shader_parameter("shape_presence", 0.0)
	wmat.set_shader_parameter("light_bleed", 0.5)
	window_view.material = wmat
	add_child(window_view)

	glow_layer = ColorRect.new()
	glow_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://shaders/glow.gdshader")
	gmat.set_shader_parameter("uv_center", Vector2(278.0 / 1280.0, 380.0 / 720.0))
	gmat.set_shader_parameter("uv_scale", Vector2(1280.0 / 720.0, 1.0))
	gmat.set_shader_parameter("radius", 0.62)
	gmat.set_shader_parameter("glow_color", Color(1.0, 0.60, 0.26))
	gmat.set_shader_parameter("strength", 0.45)
	gmat.set_shader_parameter("falloff", 2.6)
	glow_layer.material = gmat
	add_child(glow_layer)

	# ---------------- top bar ----------------
	var bar := ColorRect.new()
	bar.color = Color(0.018, 0.023, 0.028, 0.94)
	bar.position = Vector2.ZERO
	bar.size = Vector2(1280, 56)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_add_label("KESTREL-9 RELAY STATION", Vector2(16, 6), Vector2(620, 34), _font_ui, 26, Color(0.86, 0.89, 0.85))
	_add_label("NIGHT WATCH  //  OPERATOR ON DUTY: [REDACTED]  //  SECTOR 7 NORTH ATLANTIC", Vector2(16, 34), Vector2(760, 20), _font_mono, 12, Color(0.44, 0.60, 0.56))
	_add_label("RESERVE CELL", Vector2(900, 4), Vector2(300, 18), _font_mono, 12, Color(0.44, 0.62, 0.58))
	gauge = BatteryGaugeScript.new()
	gauge.position = Vector2(900, 22)
	gauge.size = Vector2(240, 26)
	add_child(gauge)
	batt_pct = _add_label("100", Vector2(1146, 20), Vector2(118, 28), _font_mono, 19, Color(0.60, 0.95, 0.62))
	batt_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# ---------------- chart column ----------------
	_add_label("SECTOR CHART  //  40N-56N  8W-24W", Vector2(576, 74), Vector2(392, 22), _font_mono, 14, Color(0.46, 0.68, 0.62))
	map = MapPanelScript.new()
	map.position = Vector2(576, 100)
	map.size = Vector2(380, 380)
	map.connect("pin_requested", Callable(self, "_on_map_pin_requested"))
	add_child(map)
	coord_label = _add_label("CURSOR  --.- N / --.- W", Vector2(576, 486), Vector2(392, 20), _font_mono, 13, Color(0.50, 0.84, 0.72))
	_add_label("BEARINGS LOGGED", Vector2(576, 512), Vector2(392, 18), _font_mono, 13, Color(0.46, 0.60, 0.56))
	bearings_label = _add_label("", Vector2(576, 532), Vector2(392, 126), _font_mono, 13, Color(0.62, 0.78, 0.72))

	# ---------------- readout column ----------------
	_add_label("SIGNAL READOUT", Vector2(964, 74), Vector2(300, 22), _font_mono, 14, Color(0.46, 0.68, 0.62))
	var rp := ColorRect.new()
	rp.color = Color(0.020, 0.030, 0.030, 0.92)
	rp.position = Vector2(964, 98)
	rp.size = Vector2(300, 310)
	rp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rp)
	var rp_edge := ColorRect.new()
	rp_edge.position = Vector2(964, 98)
	rp_edge.size = Vector2(300, 2)
	rp_edge.color = Color(0.30, 0.55, 0.48, 0.8)
	rp_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rp_edge)
	readout = RichTextLabel.new()
	readout.bbcode_enabled = true
	readout.scroll_active = true
	readout.scroll_following = false
	readout.position = Vector2(976, 106)
	readout.size = Vector2(280, 296)
	readout.add_theme_font_override("normal_font", _font_mono)
	readout.add_theme_font_override("mono_font", _font_mono)
	readout.add_theme_font_size_override("normal_font_size", 15)
	readout.add_theme_font_size_override("mono_font_size", 15)
	readout.add_theme_color_override("default_color", Color(0.66, 0.92, 0.78))
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(readout)

	_add_label("POWER DRAW", Vector2(964, 414), Vector2(300, 20), _font_mono, 14, Color(0.46, 0.68, 0.62))
	var group := ButtonGroup.new()
	for i in range(3):
		var b := Button.new()
		b.text = POWER_NAME[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = (i == 1)
		b.position = Vector2(964 + float(i) * 102.0, 436)
		b.size = Vector2(96, 36)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", _font_ui)
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", Color(0.60, 0.80, 0.74))
		b.add_theme_color_override("font_pressed_color", Color(1.0, 0.88, 0.50))
		b.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.50))
		b.add_theme_stylebox_override("normal", _btn_style(Color(0.055, 0.075, 0.075), Color(0.22, 0.36, 0.33)))
		b.add_theme_stylebox_override("hover", _btn_style(Color(0.10, 0.14, 0.13), Color(0.55, 0.90, 0.60)))
		b.add_theme_stylebox_override("pressed", _btn_style(Color(0.24, 0.20, 0.10), Color(0.95, 0.78, 0.35)))
		b.add_theme_stylebox_override("hover_pressed", _btn_style(Color(0.24, 0.20, 0.10), Color(0.95, 0.78, 0.35)))
		var idx := i
		b.pressed.connect(func() -> void: _on_power_selected(idx))
		add_child(b)

	status_label = _add_label("", Vector2(964, 480), Vector2(300, 90), _font_mono, 13, Color(0.55, 0.74, 0.68))
	_add_label("ESC ABORTS TO TITLE", Vector2(964, 620), Vector2(300, 18), _font_mono, 11, Color(0.30, 0.42, 0.40))

	# ---------------- radio console ----------------
	lcd_freq = _add_label("091.60", Vector2(52, 292), Vector2(150, 44), _font_mono, 32, Color(0.42, 1.0, 0.60))
	lcd_state = _add_label("MED  SEEKING", Vector2(52, 320), Vector2(200, 18), _font_mono, 12, Color(0.34, 0.72, 0.52))

	scope = ColorRect.new()
	scope.position = Vector2(270, 288)
	scope.size = Vector2(240, 84)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var smat := ShaderMaterial.new()
	smat.shader = load("res://shaders/radio_scope.gdshader")
	smat.set_shader_parameter("noise_strength", 0.9)
	smat.set_shader_parameter("signal_strength", 0.0)
	smat.set_shader_parameter("jam_level", 0.0)
	scope.material = smat
	add_child(scope)

	dial = FreqDialScript.new()
	dial.position = Vector2(48, 384)
	dial.size = Vector2(460, 60)
	dial.set("value", freq)
	dial.connect("tuned", Callable(self, "_on_dial_tuned"))
	add_child(dial)
	dial.call("queue_redraw")
	dial.call("grab_focus")

	var lock_bg := ColorRect.new()
	lock_bg.color = Color(0.012, 0.018, 0.016)
	lock_bg.position = Vector2(46, 454)
	lock_bg.size = Vector2(464, 10)
	lock_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lock_bg)
	lock_fill = ColorRect.new()
	lock_fill.color = Color(0.35, 0.95, 0.55)
	lock_fill.position = Vector2(46, 454)
	lock_fill.size = Vector2(0, 10)
	lock_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lock_fill)

	console_status = _add_label("", Vector2(46, 470), Vector2(464, 90), _font_mono, 13, Color(0.52, 0.70, 0.64))

	# ---------------- overlays ----------------
	whisper_label = _add_label("", Vector2(340, 176), Vector2(600, 60), _font_ui, 30, Color(0.92, 0.40, 0.32))
	whisper_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	whisper_label.modulate = Color(1, 1, 1, 0)

	jam_panel = ColorRect.new()
	jam_panel.color = Color(0.30, 0.04, 0.03, 0.72)
	jam_panel.position = Vector2(400, 286)
	jam_panel.size = Vector2(480, 104)
	jam_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jam_panel.visible = false
	add_child(jam_panel)
	var jt := _add_label("INTERFERENCE", Vector2(400, 292), Vector2(480, 34), _font_ui, 28, Color(1.0, 0.60, 0.50))
	jt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jt.visible = false
	jam_hint = _add_label("RETUNE OUT OF THE RED BAND", Vector2(400, 328), Vector2(480, 22), _font_mono, 14, Color(1.0, 0.80, 0.70))
	jam_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jam_hint.visible = false
	var jbg := ColorRect.new()
	jbg.color = Color(0.10, 0.02, 0.02)
	jbg.position = Vector2(28, 70)
	jbg.size = Vector2(424, 14)
	jbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jam_panel.add_child(jbg)
	jam_fill = ColorRect.new()
	jam_fill.color = Color(0.95, 0.35, 0.25)
	jam_fill.position = Vector2(28, 70)
	jam_fill.size = Vector2(424, 14)
	jam_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jam_panel.add_child(jam_fill)

	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_rect)

	jam_title_ref = jt
	jam_hint_ref = jam_hint


var jam_title_ref: Label
var jam_hint_ref: Label


func _add_label(text: String, pos: Vector2, sz: Vector2, font: Font, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = sz
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	return l


func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	return sb


# ------------------------------------------------------------------ process

func _process(delta: float) -> void:
	if _finished:
		return
	_tick += delta
	_flicker = maxf(0.0, _flicker - delta * 3.0)

	if _sequence == 1:
		_run_finale(delta)
	elif _sequence == 2:
		_run_blackout(delta)
	else:
		time_alive += delta
		_update_battery(delta)
		_update_tuning(delta)
		_update_jam(delta)
		_update_ambient(delta)

	_update_dynamics(delta)
	_update_visuals(delta)


func _update_battery(delta: float) -> void:
	var drain := float(DRAIN[power_mode])
	if _jam_active:
		drain *= 3.0
	if lock_progress > 0.02:
		drain += 0.30
	battery = maxf(0.0, battery - drain * delta)
	if battery <= 0.0:
		_begin_blackout()


func _update_tuning(delta: float) -> void:
	freq = float(dial.get("value"))
	var s := 0.0
	var target_id := -1
	var near_id := -1
	var near_f := 0.0
	var near_d := 999.0
	for sig in SignalData.SIGNALS:
		if locked.has(int(sig["id"])):
			continue
		var d: float = absf(freq - float(sig["freq"]))
		if d < near_d:
			near_d = d
			near_id = int(sig["id"])
			near_f = float(sig["freq"])
		var w := float(LOCK_WINDOW[power_mode])
		var v: float = clampf(1.0 - d / w, 0.0, 1.0)
		if v > s:
			s = v
			target_id = int(sig["id"])

	# the dial reaches out and grabs a nearby carrier (not while jamming)
	if not _jam_active and near_id >= 0 and near_d > 0.001:
		var reach := float(CATCH_RADIUS[power_mode])
		if near_d < reach and not bool(dial.get("dragging")):
			var pull: float = minf(near_d, 0.60 * delta)
			freq = freq + signf(near_f - freq) * pull
			dial.call("set_value", freq, false)
			s = clampf(1.0 - absf(freq - near_f) / float(LOCK_WINDOW[power_mode]), 0.0, 1.0)
			target_id = near_id

	signal_strength = s

	if s > 0.5 and not _jam_active:
		lock_progress = minf(1.0, lock_progress + delta * (0.80 + s * 0.55))
		if lock_progress >= 0.999 and target_id >= 0:
			_lock_signal(target_id)
	else:
		lock_progress = maxf(0.0, lock_progress - delta * 1.8)


func _lock_signal(id: int) -> void:
	lock_progress = 0.0
	if locked.has(id):
		return
	var sig: Dictionary = SignalData.SIGNALS[id]
	locked[id] = true
	dial.get("locked_freqs").append(float(sig["freq"]))
	sfx.play("confirm", -7)
	sfx.play("glitch", -14, 1.2)
	_do_flash(0.30, Color(0.35, 1.0, 0.60))
	_log("CARRIER LOCKED  %s" % str(sig["callsign"]))
	_set_readout_signal(id)
	_say("CARRIER LOCKED")


func _on_dial_tuned(v: float) -> void:
	freq = v
	lcd_freq.text = "%06.2f" % v


func _on_power_selected(mode: int) -> void:
	if mode == power_mode:
		return
	power_mode = mode
	sfx.play("switch", -8, 0.9 + 0.12 * float(mode))
	_do_flash(0.12, Color(0.6, 1.0, 0.8))
	if mode == 0:
		_log("POWER LOW. ROOM DIMMED, SCAN RANGE NARROW.")
	elif mode == 1:
		_log("POWER MED. STANDARD SCAN RANGE.")
	else:
		_log("POWER HIGH. WIDE SCAN RANGE, HEAVY DRAW.")


func _on_map_pin_requested(lat: float, lon: float) -> void:
	var target := -1
	for sig in SignalData.SIGNALS:
		var sid := int(sig["id"])
		if locked.has(sid) and not placed.has(sid):
			target = sid
			break
	if target < 0:
		sfx.play("error", -10)
		_log("NO DECODED BEARING TO LOG.")
		if map.get("flash") != null:
			map.set("flash", 0.8)
			map.set("flash_pos", map.call("geo_to_local", lat, lon))
		return
	var sig2: Dictionary = SignalData.SIGNALS[target]
	var d: float = Vector2(lat - float(sig2["lat"]), lon - float(sig2["lon"])).length()
	map.set("flash", 1.0)
	map.set("flash_pos", map.call("geo_to_local", lat, lon))
	if d <= PIN_TOLERANCE:
		_place_pin(target, sig2)
	else:
		battery = maxf(0.0, battery - 2.5)
		corruption = minf(1.0, corruption + 0.05)
		sfx.play("error", -6)
		_do_flash(0.35, Color(1.0, 0.30, 0.24))
		_log("OFF-TARGET. BEARING REJECTED. -2.5 CELL.")
		_set_readout_note("OFF-TARGET\n\nYOUR ESTIMATE  %.1f N / %.1f W\nIS %d TENTHS OFF.\n\nRE-READ THE TRANSCRIPT\nAND CLICK AGAIN." % [lat, lon, int(round(d * 10.0))])
		if battery <= 0.0:
			_begin_blackout()


func _place_pin(id: int, sig: Dictionary) -> void:
	placed[id] = true
	pin_count += 1
	map.call("add_pin", id, float(sig["lat"]), float(sig["lon"]), bool(sig["cache"]))
	sfx.play("confirm", -5)
	_do_flash(0.45, Color(0.35, 1.0, 0.60))
	var extra := ""
	if bool(sig["cache"]):
		cache_count += 1
		battery = minf(MAX_BATTERY, battery + CACHE_GAIN)
		sfx.play("phaser_up", -7)
		extra = "  " + str(SignalData.CACHE_LINES[id % SignalData.CACHE_LINES.size()]) + " +%d CELL" % int(CACHE_GAIN)
	_log("BEARING %d LOGGED - %s.%s" % [pin_count, str(sig["callsign"]), extra])
	_set_readout_note("BEARING %d / %d LOGGED.\n\n%s\n\n%s" % [
		pin_count, MAX_SIGNALS, str(sig["callsign"]),
		"CELL RECOVERED." if bool(sig["cache"]) else "KEEP SWEEPING THE BAND."
	])
	_refresh_bearings()
	if pin_count == 3:
		_on_triangulation()
	if pin_count >= MAX_SIGNALS:
		_begin_finale()


func _on_triangulation() -> void:
	var cx := 0.0
	var cy := 0.0
	var n := 0
	for sig in SignalData.SIGNALS:
		if placed.has(int(sig["id"])):
			cx += float(sig["lat"])
			cy += float(sig["lon"])
			n += 1
	if n > 0:
		map.set("source_geo", Vector2(cx / float(n), cy / float(n)))
	map.set("show_source", true)
	corruption = minf(1.0, corruption + 0.10)
	_do_flash(0.7, Color(0.95, 0.35, 0.25))
	sfx.play("boom", -9)
	sfx.play("computer", -8)
	_log("TRIANGULATION COMPLETE. SOURCE RESOLVED.")
	_say("THE BEARINGS CONVERGE ON YOU.")
	_set_readout_note("TRIANGULATION\n\nTHREE BEARINGS RESOLVE TO A\nSINGLE ORIGIN. THE CHART NOW\nSHOWS WHERE THE JAMMER SITS.\n\nIT IS VERY CLOSE.")


func _refresh_bearings() -> void:
	var lines: Array[String] = []
	for sig in SignalData.SIGNALS:
		var sid := int(sig["id"])
		var cs := str(sig["callsign"])
		if cs.length() > 15:
			cs = cs.substr(0, 15)
		if placed.has(sid):
			lines.append("%d %-15s %s %s" % [sid + 1, cs, str(sig["coords"]), "[C]" if bool(sig["cache"]) else "   "])
		elif locked.has(sid):
			lines.append("%d %-15s DECODED - PLACE" % [sid + 1, cs])
		else:
			lines.append("%d ?? MHz          ---------------" % [sid + 1])
	bearings_label.text = "\n".join(PackedStringArray(lines))


# ------------------------------------------------------------------ jamming

func _update_jam(delta: float) -> void:
	if _jam_cooldown > 0.0:
		_jam_cooldown -= delta
	if not _jam_active:
		_next_jam -= delta
		if _next_jam <= 0.0 and _jam_cooldown <= 0.0:
			_start_jam()
		return

	_jam_timer -= delta
	var inside: bool = freq >= _jam_band.x and freq <= _jam_band.y
	if inside:
		_jam_escape = 0.0
		corruption = minf(1.0, corruption + delta * 0.045)
		if randf() < delta * 8.0:
			_do_flash(0.12, Color(1.0, 0.25, 0.20))
		if _jam_timer <= 0.0:
			_end_jam(false)
	else:
		_jam_escape += delta
		if _jam_escape >= 0.9:
			_end_jam(true)


func _start_jam() -> void:
	_jam_active = true
	_jam_escape = 0.0
	var esc := float(pin_count) / float(MAX_SIGNALS)
	var w: float = lerpf(2.4, 4.6, esc)
	var lo: float = freq - w * 0.5
	var hi: float = freq + w * 0.5
	if lo < FREQ_MIN:
		hi += FREQ_MIN - lo
		lo = FREQ_MIN
	if hi > FREQ_MAX:
		lo -= hi - FREQ_MAX
		hi = FREQ_MAX
	_jam_band = Vector2(maxf(lo, FREQ_MIN), minf(hi, FREQ_MAX))
	_jam_timer = lerpf(6.5, 8.5, esc)
	jam_hint.text = "RETUNE OUT OF THE RED BAND"
	corruption = minf(1.0, corruption + 0.06)
	_flicker = 1.0
	_do_flash(0.5, Color(1.0, 0.25, 0.20))
	sfx.play("forcefield", -3)
	sfx.play("glitch", -4)
	sfx.play("boom", -12)
	_log("INTERFERENCE SPIKE. RETUNE OFF THE BAND.")
	_say("IT FOUND YOU")


func _end_jam(success: bool) -> void:
	_jam_active = false
	var esc := float(pin_count) / float(MAX_SIGNALS)
	_jam_cooldown = 4.0
	_next_jam = lerpf(26.0, 12.0, esc) + randf_range(-2.0, 3.0)
	if success:
		battery = minf(MAX_BATTERY, battery + 4.0)
		sfx.play("confirm", -6)
		_do_flash(0.4, Color(0.35, 1.0, 0.60))
		_log("INTERFERENCE CLEARED. +4 CELL.")
		_say("CLEAR")
	else:
		battery = maxf(0.0, battery - 15.0)
		corruption = minf(1.0, corruption + 0.16)
		sfx.play("boom", -4)
		sfx.play("glitch2", -5)
		_do_flash(0.75, Color(1.0, 0.22, 0.18))
		_log("JAMMED. -15 CELL. LOGIC CORRUPTED.")
		_say("IT WAS INSIDE THE DIAL")
		if battery <= 0.0:
			_begin_blackout()


# ------------------------------------------------------------------ ambience

func _update_ambient(delta: float) -> void:
	_ambient_t -= delta
	if _ambient_t <= 0.0:
		_ambient_t = randf_range(11.0, 22.0) - float(pin_count) * 1.2
		if pin_count >= 1 and not _jam_active:
			var ws: Array = SignalData.WHISPERS
			_say(str(ws[randi() % ws.size()]))
			sfx.play("glitch2", -16, randf_range(0.7, 1.05))
			_flicker = 0.8
	if _glitch_burst > 0.0:
		_glitch_burst = maxf(0.0, _glitch_burst - delta * 2.2)
	if randf() < delta * (0.05 + float(pin_count) * 0.07):
		_glitch_burst = minf(1.0, 0.30 + randf() * 0.7)
		sfx.play("glitch", -18, randf_range(0.8, 1.2))


func _say(text: String) -> void:
	_whisper = text
	_whisper_a = 1.6
	whisper_label.text = text


func _do_flash(amount: float, col: Color) -> void:
	_flash = maxf(_flash, amount)
	_flash_col = col


func _log(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > 5:
		_log_lines.pop_front()
	var joined := "\n".join(PackedStringArray(_log_lines))
	if console_status != null:
		console_status.text = joined


# ------------------------------------------------------------------ dynamics

func _update_dynamics(delta: float) -> void:
	var esc := float(pin_count) / float(MAX_SIGNALS)
	var base := float(LIGHT_LEVEL[power_mode])
	if battery < 22.0:
		base *= lerpf(0.22, 1.0, clampf(battery / 22.0, 0.0, 1.0))
	if _sequence == 2:
		base = 0.0
	_light_target = base * (1.0 - _flicker * 0.5)
	_light = lerpf(_light, _light_target, clampf(delta * 2.6, 0.0, 1.0))

	if _sequence == 0:
		_entity = lerpf(_entity, clampf(corruption - 0.55, 0.0, 1.0) * 0.25 * esc, clampf(delta * 0.7, 0.0, 1.0))

	if audio != null:
		audio.set("static_target", 0.045 + (1.0 - signal_strength) * 0.20 + corruption * 0.07 + (0.25 if _jam_active else 0.0))
		audio.set("tone_target", signal_strength * 0.42 + (0.30 if _jam_active else 0.0))
		audio.set("tone_pitch", 0.55 + (freq - FREQ_MIN) / (FREQ_MAX - FREQ_MIN) * 1.5)
		audio.set("drone_target", 0.05 + esc * 0.13 + corruption * 0.08)
		audio.set("jam_target", 1.0 if _jam_active else 0.0)

	if gauge != null:
		gauge.set("value", battery)
		gauge.set("warn", clampf((30.0 - battery) / 30.0, 0.0, 1.0))


func _update_visuals(delta: float) -> void:
	# room
	room.set("light", _light)
	room.set("flicker", _flicker)
	room.set("escalation", pin_count)
	room.set("corruption", corruption)
	room.set("entity", _entity)
	room.set("jam", 1.0 if _jam_active else 0.0)
	room.set("door_alarm", 1.0 if (_jam_active or battery < 25.0) else 0.0)

	# window
	var esc := float(pin_count) / float(MAX_SIGNALS)
	var wm: ShaderMaterial = window_view.material
	var presence: float = clampf(esc * 0.95 + corruption * 0.35 - 0.15, 0.0, 1.0)
	if _sequence == 1:
		presence = 1.0
	if _sequence == 2:
		presence = clampf(0.3 + _entity, 0.0, 1.0)
	wm.set_shader_parameter("shape_presence", presence)
	wm.set_shader_parameter("darkness", clampf(_light * 0.6 + 0.4, 0.0, 1.0))
	wm.set_shader_parameter("light_bleed", clampf(_light, 0.0, 1.0))

	# glow layer follows the console lamp
	var gm: ShaderMaterial = glow_layer.material
	var lamp := clampf(_light * (0.55 + 0.45 * float(power_mode) / 2.0), 0.05, 1.0)
	if _sequence == 2:
		lamp = 0.02
	gm.set_shader_parameter("strength", 0.30 + lamp * 0.45 + _flicker * -0.2)
	gm.set_shader_parameter("radius", 0.55 + lamp * 0.18)
	gm.set_shader_parameter("glow_color", Color(1.0, 0.58 + 0.10 * sin(_tick), 0.24))

	# scope
	var sm: ShaderMaterial = scope.material
	sm.set_shader_parameter("noise_strength", 0.55 + (1.0 - signal_strength) * 0.55 + corruption * 0.25)
	sm.set_shader_parameter("signal_strength", signal_strength)
	sm.set_shader_parameter("jam_level", 1.0 if _jam_active else 0.0)
	sm.set_shader_parameter("glow", Color(1.0, 0.32, 0.26) if _jam_active else Color(0.42, 0.98, 0.62))

	# labels
	var lcd_col := Color(0.42, 1.0, 0.60)
	if _jam_active:
		lcd_col = Color(1.0, 0.38, 0.30)
	elif signal_strength > 0.55:
		lcd_col = Color(1.0, 0.82, 0.36)
	lcd_freq.add_theme_color_override("font_color", lcd_col)
	lcd_freq.text = "%06.2f" % freq
	var st: String = "LOCKED" if signal_strength > 0.98 else ("CARRIER" if signal_strength > 0.55 else ("JAM" if _jam_active else "SEEKING"))
	lcd_state.text = "%s  %s" % [POWER_NAME[power_mode], st]
	lock_fill.size = Vector2(464.0 * lock_progress, 10.0)
	lock_fill.color = Color(1.0, 0.35, 0.28) if _jam_active else Color(0.35, 0.95, 0.55)

	# dial decorations
	dial.set("jam_active", _jam_active)
	dial.set("jam_band", _jam_band)
	dial.set("noise", _tick)
	dial.set("enabled", _sequence == 0)

	# map decorations
	map.set("corruption", corruption)
	map.set("light", clampf(0.55 + _light * 0.45, 0.0, 1.0))
	map.set("alarm", 1.0 if _jam_active else 0.0)
	var hov: Vector2 = map.get_local_mouse_position()
	if map.get_global_rect().has_point(get_global_mouse_position()):
		var g: Vector2 = map.call("local_to_geo", hov)
		coord_label.text = "CURSOR  %.1f N / %.1f W" % [g.x, g.y]
	else:
		coord_label.text = "CURSOR  --.- N / --.- W"

	# status block
	status_label.text = "PWR DRAW    %.2f /s\nLAMP        %s\nSCAN RANGE  %s\nBEARINGS    %d / %d\nINTERFERENCE %d%%\nJAM STATE   %s" % [
		float(DRAIN[power_mode]) * (3.0 if _jam_active else 1.0),
		POWER_NAME[power_mode],
		SCAN_RANGE[power_mode],
		pin_count,
		MAX_SIGNALS,
		int(round(corruption * 100.0)),
		"ACTIVE" if _jam_active else "QUIET"
	]
	if batt_pct != null:
		batt_pct.text = "%d%%" % int(round(battery))
		var bc := Color(0.60, 0.95, 0.62)
		if battery < 55.0:
			bc = Color(0.98, 0.82, 0.32)
		if battery < 25.0:
			bc = Color(1.0, 0.34, 0.26)
		batt_pct.add_theme_color_override("font_color", bc)

	# jam banner
	jam_panel.visible = _jam_active
	jam_title_ref.visible = _jam_active
	jam_hint_ref.visible = _jam_active
	if _jam_active:
		var tt: float = clampf(_jam_timer / 8.5, 0.0, 1.0)
		jam_fill.size = Vector2(424.0 * tt, 14.0)
		if _jam_escape > 0.0:
			jam_hint.text = "HOLD POSITION - CLEARING %d%%" % int(_jam_escape / 0.9 * 100.0)

	# flash + whisper
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.9)
		flash_rect.color = Color(_flash_col.r, _flash_col.g, _flash_col.b, _flash * 0.55)
	else:
		flash_rect.color = Color(0, 0, 0, 0)
	if _whisper_a > 0.0:
		_whisper_a = maxf(0.0, _whisper_a - delta * 0.55)
		var a: float = clampf(_whisper_a, 0.0, 1.0)
		whisper_label.modulate = Color(1, 1, 1, a * 0.95)
	else:
		whisper_label.modulate = Color(1, 1, 1, 0)

	# readout typewriter
	if readout != null:
		_type_shown = minf(float(_type_text.length()), _type_shown + delta * 90.0)
		readout.visible_characters = int(_type_shown)


# ------------------------------------------------------------------ readout

func _set_readout(text: String) -> void:
	_type_text = text
	_type_shown = 0.0
	readout.text = text
	readout.visible_characters = 0


func _set_readout_note(text: String) -> void:
	_set_readout("[color=#7fd8a8]%s[/color]" % text)


func _set_readout_signal(id: int) -> void:
	var sig: Dictionary = SignalData.SIGNALS[id]
	var body: Array = sig["lines"]
	var lines: Array[String] = []
	for l in body:
		lines.append(str(l))
	var head := "[color=#ffd166]TUNE %06.2f MHz  -  %s[/color]\n[color=#2f6d5a]--------------------------------[/color]" % [float(sig["freq"]), str(sig["callsign"])]
	var tail := "[color=#2f6d5a]--------------------------------[/color]\n[color=#ff8f6b]BEARING  %s[/color]\n[color=#9fe8c0]CLICK THE CHART AT THAT POSITION.[/color]"
	_set_readout(head + "\n" + "\n".join(PackedStringArray(lines)) + "\n" + tail)


# ------------------------------------------------------------------ sequences

func _begin_blackout() -> void:
	if _sequence != 0:
		return
	_sequence = 2
	_seq_t = 0.0
	_step_t = 0.0
	_jam_active = false
	_jam_panel_hide()
	corruption = minf(1.0, corruption + 0.3)
	whisper_label.text = "THE CELLS ARE DEAD"
	_whisper_a = 3.0
	sfx.play("boom", -2)
	sfx.play("door", -4)
	_log("CELL BANK EMPTY. LAMPS FAILING.")


func _jam_panel_hide() -> void:
	jam_panel.visible = false
	jam_title_ref.visible = false
	jam_hint_ref.visible = false


func _run_blackout(delta: float) -> void:
	_seq_t += delta
	_step_t -= delta
	_entity = minf(1.6, _entity + delta * 0.16)
	_light_target = 0.0
	_light = maxf(0.0, _light - delta * 0.7)
	if _step_t <= 0.0:
		_step_t = randf_range(0.75, 1.25)
		sfx.play(["step_a", "step_b", "step_c"][randi() % 3], -4 - float(_seq_t) * 0.2, randf_range(0.75, 0.95))
		_glitch_burst = 0.6
	if _seq_t > 2.4 and _whisper_a <= 0.0:
		whisper_label.text = "SOMETHING CROSSED THE ROOM"
		_whisper_a = 2.6
		_entity = maxf(_entity, 0.7)
	if _seq_t > 5.2 and _whisper_a <= 0.2:
		whisper_label.text = "IT IS AT THE DESK"
		_whisper_a = 3.0
	if _seq_t > 7.2:
		_finish("dark")


func _begin_finale() -> void:
	if _sequence != 0:
		return
	_sequence = 1
	_seq_t = 0.0
	_jam_active = false
	_jam_panel_hide()
	map.set("source_geo", Vector2(SignalData.STATION_LAT, SignalData.STATION_LON))
	map.set("show_source", true)
	corruption = 1.0
	whisper_label.text = "FIVE BEARINGS. ONE ORIGIN."
	_whisper_a = 3.0
	sfx.play("boom", -3)
	sfx.play("forcefield", -6)
	_log("FINAL BEARING LOGGED. RESOLVING ORIGIN.")
	_set_readout_note("FIVE BEARINGS LOGGED.\n\nTHE CHART IS SOLVING.\n\nTHE ORIGIN RESOLVES TO\n52.0 N / 18.0 W.\n\nTHAT IS THIS ROOM.")


func _run_finale(delta: float) -> void:
	_seq_t += delta
	var t := _seq_t
	_entity = minf(1.4, _entity + delta * 0.14)
	_glitch_burst = 1.0
	_light_target = maxf(0.0, 0.65 - t * 0.09)
	_light = lerpf(_light, _light_target, clampf(delta * 2.0, 0.0, 1.0))
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = 1.4
		sfx.play("glitch", -12, randf_range(0.7, 1.1))
	if t > 2.2 and t < 2.4:
		whisper_label.text = "THE DOOR IS BEHIND YOU"
		_whisper_a = 2.2
		sfx.play("door", -6)
	if t > 4.6 and t < 4.8:
		whisper_label.text = "DO NOT TURN THE DIAL"
		_whisper_a = 2.2
	if t > 6.6 and t < 6.8:
		whisper_label.text = "SIGNAL LOST"
		_whisper_a = 3.0
		sfx.play("boom", -2)
		sfx.play("forcefield", -6)
	if t > 9.0:
		_finish("signal_lost")


func _finish(kind: String) -> void:
	if _finished:
		return
	_finished = true
	var st: Dictionary = {
		"signals": pin_count,
		"pins": pin_count,
		"caches": cache_count,
		"battery": int(maxf(0.0, battery)),
		"time": "%02d:%02d" % [int(time_alive) / 60, int(time_alive) % 60],
		"corruption": int(round(corruption * 100.0)),
		"outcome_code": "ORIGIN-DESK" if kind == "signal_lost" else "RESERVE-EMPTY",
		"note": "The band is quiet." if kind == "signal_lost" else "You should have conserved the cells."
	}
	if audio != null:
		audio.set("static_target", 0.0)
		audio.set("tone_target", 0.0)
		audio.set("jam_target", 0.0)
	finished.emit(kind, st)


# ------------------------------------------------------------------ external

func fx_state() -> Dictionary:
	var g: float = 0.035 + corruption * 0.50 + float(pin_count) * 0.012 + _glitch_burst * 0.35
	var tint := Color(0.95, 1.0, 0.97)
	if _jam_active:
		g += 0.35
		tint = Color(1.0, 0.82, 0.78)
	if _sequence == 1:
		g = 0.95
		tint = Color(1.0, 0.75, 0.72)
	if _sequence == 2:
		g = 0.12 + _entity * 0.45
		tint = Color(0.85, 0.72, 0.72)
	if battery < 22.0 and _sequence == 0:
		tint = tint.lerp(Color(1.0, 0.70, 0.60), 0.5 * (1.0 - battery / 22.0))
	return {
		"glitch": clampf(g, 0.0, 1.0),
		"corruption": clampf(corruption, 0.0, 1.0),
		"tint": tint,
		"brightness": clampf(lerpf(0.72, 1.0, _light), 0.4, 1.0)
	}


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _sequence != 0 or _finished:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_ESCAPE:
			abort_requested.emit()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ debug

func debug_setup(cfg: Dictionary) -> void:
	var lk: Array = cfg.get("locked", [])
	for id in lk:
		locked[int(id)] = true
		dial.get("locked_freqs").append(float(SignalData.SIGNALS[int(id)]["freq"]))
	for id in cfg.get("pins", []):
		var sid := int(id)
		locked[sid] = true
		_place_pin(sid, SignalData.SIGNALS[sid])
	corruption = float(cfg.get("corruption", corruption))
	if bool(cfg.get("jam", false)):
		_start_jam()
	if bool(cfg.get("finale", false)):
		_begin_finale()
	if bool(cfg.get("dark", false)):
		battery = 0.0
		_begin_blackout()
	if locked.size() > 0 and _sequence == 0:
		var last := -1
		for sig in SignalData.SIGNALS:
			if locked.has(int(sig["id"])):
				last = int(sig["id"])
		if last >= 0:
			_set_readout_signal(last)
	_refresh_bearings()
	_queue_redraw_all()


func _queue_redraw_all() -> void:
	for n in get_children():
		if n is CanvasItem:
			(n as CanvasItem).queue_redraw()
