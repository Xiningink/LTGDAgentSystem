extends Control
## Receiver unit: spectrum scope, tuning dial, power stage and lock meter.

signal frequency_changed(freq: float)
signal signal_locked(index: int)

const SCOPE_SHADER := "res://assets/shaders/radio_scope.gdshader"

var frequency := 95.00
var active_signals: Array = []
var logged_signals: Array = []
var jam_visual := {"jam_f": 0.0, "jam_amt": 0.0, "clear_f": 0.0, "clear_amt": 0.0}
var glitch := 0.0
var power_dim := 1.0
var enabled := true

var strength := 0.0
var lock_ratio := 0.0

var _scope: ColorRect
var _mat: ShaderMaterial
var _t := 0.0
var _dragging := false
var _lock_target := -1
var _lock_progress := 0.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.seed = 31337
	_scope = ColorRect.new()
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load(SCOPE_SHADER)
	_mat.set_shader_parameter("band_min", SignalDB.BAND_MIN)
	_mat.set_shader_parameter("band_max", SignalDB.BAND_MAX)
	_mat.set_shader_parameter("sig_f", PackedFloat32Array([0, 0, 0, 0]))
	_mat.set_shader_parameter("sig_s", PackedFloat32Array([0, 0, 0, 0]))
	_scope.material = _mat
	add_child(_scope)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	if _scope == null:
		return
	var r := scope_rect()
	_scope.position = r.position
	_scope.size = r.size


func scope_rect() -> Rect2:
	return Rect2(16.0, 44.0, size.x - 32.0, 152.0)


func dial_rect() -> Rect2:
	return Rect2(24.0, 262.0, size.x - 48.0, 62.0)


func _track_rect() -> Rect2:
	var d := dial_rect()
	return Rect2(d.position.x + 12.0, d.position.y + 14.0, d.size.x - 24.0, 22.0)


func _power_rects() -> Array:
	var y := 352.0
	var total := size.x - 32.0
	var gap := 8.0
	var bw := (total - gap * 3.0) / 4.0
	var out: Array = []
	for i in 4:
		out.append(Rect2(16.0 + float(i) * (bw + gap), y, bw, 34.0))
	return out


func freq_to_x(f: float) -> float:
	var tr := _track_rect()
	var u: float = clampf((f - SignalDB.BAND_MIN) / (SignalDB.BAND_MAX - SignalDB.BAND_MIN), 0.0, 1.0)
	return tr.position.x + u * tr.size.x


func x_to_freq(x: float) -> float:
	var tr := _track_rect()
	var u: float = clampf((x - tr.position.x) / tr.size.x, 0.0, 1.0)
	return SignalDB.BAND_MIN + u * (SignalDB.BAND_MAX - SignalDB.BAND_MIN)


func set_frequency(f: float) -> void:
	var next: float = clampf(f, SignalDB.BAND_MIN, SignalDB.BAND_MAX)
	next = snappedf(next, 0.05)
	if is_equal_approx(next, frequency):
		return
	frequency = next
	frequency_changed.emit(frequency)


## Called when a lock completes so the meter can reset cleanly.
func consume_lock() -> void:
	_lock_progress = 0.0
	_lock_target = -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_frequency(frequency + 0.05)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_frequency(frequency - 0.05)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if dial_rect().has_point(mb.position) or scope_rect().has_point(mb.position):
					_dragging = true
					set_frequency(x_to_freq(mb.position.x))
					Audio.play("tick_002.ogg", -18.0, randf_range(0.9, 1.2))
				else:
					var rects := _power_rects()
					for i in rects.size():
						if rects[i].has_point(mb.position):
							GameState.set_power(i)
							Audio.play("switch_003.ogg", -9.0)
							break
			else:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		set_frequency(x_to_freq((event as InputEventMouseMotion).position.x))


func _input(event: InputEvent) -> void:
	if _dragging and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_dragging = false


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.0)
	if Input.is_action_pressed("ui_left"):
		set_frequency(frequency - 5.0 * delta)
	if Input.is_action_pressed("ui_right"):
		set_frequency(frequency + 5.0 * delta)
	_update_detection(delta)
	_update_scope()
	queue_redraw()


func _update_detection(delta: float) -> void:
	var sigma: float = GameState.POWER_SIGMA[GameState.power]
	var best := -1
	var best_s := 0.0
	for i in active_signals:
		var f: float = SignalDB.signals[i]["freq"]
		var d := absf(frequency - f)
		var s := 0.0
		if sigma > 0.0:
			s = exp(-pow(d / sigma, 2.0))
		if s > best_s:
			best_s = s
			best = i
	strength = best_s
	if enabled and sigma > 0.0 and best >= 0 and best_s > 0.6:
		_lock_target = best
		_lock_progress += delta / float(GameState.POWER_LOCK[GameState.power])
		if _lock_progress >= 1.0:
			_lock_progress = 0.0
			_flash = 1.0
			signal_locked.emit(best)
	else:
		_lock_progress = maxf(0.0, _lock_progress - delta * 1.8)
		if best_s <= 0.32:
			_lock_target = -1
	lock_ratio = clampf(_lock_progress, 0.0, 1.0)


func _update_scope() -> void:
	if _mat == null:
		return
	var sig_f := PackedFloat32Array([SignalDB.BAND_MIN, SignalDB.BAND_MIN, SignalDB.BAND_MIN, SignalDB.BAND_MIN])
	var sig_s := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var sigma: float = maxf(GameState.POWER_SIGMA[GameState.power], 0.05)
	var slot := 0
	for i in active_signals:
		if slot >= 4:
			break
		var f: float = SignalDB.signals[i]["freq"]
		var d := absf(frequency - f)
		sig_f[slot] = f
		sig_s[slot] = clampf(exp(-pow(d / (sigma * 1.6), 2.0)), 0.0, 1.0)
		slot += 1
	# Signals already logged stay visible as dim markers.
	for i in logged_signals:
		if slot >= 4:
			break
		sig_f[slot] = SignalDB.signals[i]["freq"]
		sig_s[slot] = 0.22
		slot += 1
	_mat.set_shader_parameter("sig_f", sig_f)
	_mat.set_shader_parameter("sig_s", sig_s)
	_mat.set_shader_parameter("dial", frequency)
	_mat.set_shader_parameter("jam_f", jam_visual.get("jam_f", 0.0))
	_mat.set_shader_parameter("jam_amt", jam_visual.get("jam_amt", 0.0))
	_mat.set_shader_parameter("clear_f", jam_visual.get("clear_f", 0.0))
	_mat.set_shader_parameter("clear_amt", jam_visual.get("clear_amt", 0.0))
	_mat.set_shader_parameter("glitch", glitch)
	_mat.set_shader_parameter("lock", lock_ratio)
	_mat.set_shader_parameter("noise_amt", 0.55 + 0.45 * (1.0 - power_dim) + 0.35 * float(GameState.power == GameState.Power.STANDBY))


func _draw() -> void:
	draw_style_box(UIKit.panel_box(Color(0.10, 0.17, 0.19)), Rect2(Vector2.ZERO, size))
	# Header.
	UIKit.draw_bar(self, Rect2(14, 10, size.x - 28, 26), Color(0.85, 0.9, 0.85, 0.9))
	var led_col: Color = Color("4b6a60") if GameState.power == GameState.Power.STANDBY else Color("74f7b4")
	var led := UIKit.tex("res://assets/ui_oga/led.png")
	draw_texture(led, Vector2(24, 15), led_col)
	UIKit.text(self, Vector2(48, 30), "RECEIVER ARRAY  /  BAND III SHORTWAVE", 15, Color(0.82, 0.95, 0.88, 0.9))
	UIKit.text_right(self, Vector2(size.x - 26, 30), "K-7", 16, Color(0.6, 0.9, 0.8, 0.8))

	# Scope bezel.
	var sr := scope_rect()
	draw_rect(sr.grow(3.0), Color("0a1114"))
	draw_rect(sr.grow(1.0), Color("1c3336"), false, 1.0)
	UIKit.draw_corner_ticks(self, sr.grow(2.0), Color(0.35, 0.7, 0.6, 0.5), 10.0, 2.0)

	# Frequency readout.
	var fy := dial_rect().position.y - 12.0
	UIKit.text(self, Vector2(24, fy), "%.2f" % frequency, 40, Color(0.75, 1.0, 0.85) if GameState.power != GameState.Power.STANDBY else Color(0.35, 0.5, 0.45))
	UIKit.text(self, Vector2(24 + 148, fy), "MHz", 18, Color(0.5, 0.75, 0.68))
	var sig_label := "NO CARRIER"
	var sig_col := Color(0.45, 0.6, 0.55)
	if GameState.power == GameState.Power.STANDBY:
		sig_label = "STANDBY"
	elif strength > 0.6:
		sig_label = "CARRIER"
		sig_col = Color(0.55, 1.0, 0.75)
	elif strength > 0.25:
		sig_label = "FAINT"
		sig_col = Color(1.0, 0.8, 0.45)
	UIKit.text_right(self, Vector2(size.x - 26, fy - 22), sig_label, 15, sig_col)
	var bars := int(round(strength * 5.0))
	for i in 5:
		var c := sig_col if i < bars else Color(0.18, 0.28, 0.26)
		draw_rect(Rect2(size.x - 26.0 - float(5 - i) * 12.0, fy - 14.0, 8.0, 14.0), c)

	# Dial.
	var tr := _track_rect()
	UIKit.draw_bar(self, tr, Color(0.8, 0.85, 0.8, 0.95))
	for i in range(0, 21):
		var f := SignalDB.BAND_MIN + float(i)
		var x := freq_to_x(f)
		var tall := i % 5 == 0
		var top := tr.position.y - (12.0 if tall else 7.0)
		draw_line(Vector2(x, top), Vector2(x, tr.position.y - 2.0), Color(0.35, 0.6, 0.52, 0.75), 1.0)
		if tall:
			UIKit.text_center(self, Vector2(x, tr.end.y + 16.0), "%d" % int(f), 12, Color(0.45, 0.7, 0.62, 0.85))
	# Lock zone hint.
	if _lock_target >= 0 and strength > 0.15:
		var cx := freq_to_x(SignalDB.signals[_lock_target]["freq"])
		var sigma: float = maxf(GameState.POWER_SIGMA[GameState.power], 0.05)
		var half := absf(freq_to_x(SignalDB.BAND_MIN + sigma) - freq_to_x(SignalDB.BAND_MIN))
		draw_rect(Rect2(cx - half, tr.position.y - 2.0, half * 2.0, tr.size.y + 4.0), Color(0.55, 1.0, 0.75, 0.10 + 0.25 * strength))
	# Clear channel marker during jamming.
	if float(jam_visual.get("clear_amt", 0.0)) > 0.5:
		var ccx := freq_to_x(clampf(float(jam_visual.get("clear_f", 0.0)), SignalDB.BAND_MIN, SignalDB.BAND_MAX))
		draw_rect(Rect2(ccx - 7.0, tr.position.y - 12.0, 14.0, tr.size.y + 24.0), Color(0.4, 0.9, 1.0, 0.18))
		draw_line(Vector2(ccx, tr.position.y - 22.0), Vector2(ccx, tr.end.y + 10.0), Color(0.55, 0.95, 1.0, 0.9), 2.0)
		draw_polygon(PackedVector2Array([
			Vector2(ccx, tr.position.y - 30.0), Vector2(ccx - 6.0, tr.position.y - 20.0), Vector2(ccx + 6.0, tr.position.y - 20.0)
		]), PackedColorArray([Color(0.55, 0.95, 1.0)]))
		var hold := clampf(float(jam_visual.get("hold", 0.0)), 0.0, 1.0)
		draw_rect(Rect2(ccx - 14.0, tr.end.y + 6.0, 28.0, 5.0), Color(0.15, 0.35, 0.42))
		draw_rect(Rect2(ccx - 14.0, tr.end.y + 6.0, 28.0 * hold, 5.0), Color(0.55, 0.95, 1.0))
	# Needle.
	var nx := freq_to_x(frequency)
	draw_line(Vector2(nx, tr.position.y - 16.0), Vector2(nx, tr.end.y + 6.0), Color(1.0, 0.95, 0.85, 0.95), 2.0)
	draw_circle(Vector2(nx, tr.position.y - 16.0), 5.0 + 4.0 * _flash, Color(1.0, 0.85, 0.5, 0.95))
	draw_rect(tr, Color(1, 1, 1, 0.08), false, 1.0)

	# Lock meter.
	var lm := Rect2(96, 322, size.x - 122, 8)
	draw_rect(lm, Color("0a1315"))
	draw_rect(Rect2(lm.position, Vector2(lm.size.x * lock_ratio, lm.size.y)), Color(0.55, 1.0, 0.75, 0.9))
	draw_rect(lm, Color(0.3, 0.5, 0.45, 0.6), false, 1.0)
	UIKit.text(self, Vector2(24, 330), "LOCK", 13, Color(0.5, 0.75, 0.66, 0.9))
	UIKit.text_right(self, Vector2(size.x - 26, 344), "CARRIER LOCK  %d%%" % int(lock_ratio * 100.0), 12, Color(0.55, 0.9, 0.75, 0.85))

	# Power stage buttons.
	var pr := _power_rects()
	for i in pr.size():
		var r: Rect2 = pr[i]
		var active := GameState.power == i
		var col: Color = GameState.POWER_COLOR[i]
		var fill := Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 1.0) if active else Color("0b1416")
		draw_rect(r, fill)
		draw_rect(r, col if active else Color(0.22, 0.34, 0.32), false, 2.0 if active else 1.0)
		UIKit.text_center(self, r.get_center() + Vector2(0, 1), GameState.POWER_NAMES[i], 15, col if active else Color(0.5, 0.68, 0.62))
	var pw_label := "POWER STAGE"
	UIKit.text(self, Vector2(pr[0].position.x, pr[0].position.y - 8.0), pw_label, 12, Color(0.45, 0.68, 0.6, 0.8))

	# Status strip.
	if float(jam_visual.get("clear_amt", 0.0)) > 0.5:
		UIKit.text(self, Vector2(24, size.y - 10.0), "CLEAR CHANNEL  %.2f MHz   -   HOLD THE DIAL ON IT" % float(jam_visual.get("clear_f", 0.0)), 13, Color(0.6, 0.95, 1.0, 0.95))
	else:
		UIKit.text(self, Vector2(24, size.y - 10.0), "DRAIN %.2f%%/s" % GameState.POWER_DRAIN[GameState.power], 13, Color(0.5, 0.72, 0.64, 0.85))
	UIKit.text_right(self, Vector2(size.x - 26, size.y - 10.0), "BAND III  %.1f - %.1f MHz" % [SignalDB.BAND_MIN, SignalDB.BAND_MAX], 13, Color(0.4, 0.6, 0.55, 0.7))
	draw_rect(Rect2(Vector2.ZERO, size), Color("152a2a"), false, 3.0)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 1.0, 0.8, 0.10 * _flash))
