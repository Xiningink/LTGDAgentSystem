extends Control
## The station: room, window, chart, receiver, log, jamming, blackouts.

signal navigate(screen: String, payload: Dictionary)

const RoomBackground := preload("res://scripts/ui/room_background.gd")
const WindowView := preload("res://scripts/ui/window_view.gd")
const MapChart := preload("res://scripts/ui/map_chart.gd")
const RadioPanel := preload("res://scripts/ui/radio_panel.gd")
const HudBar := preload("res://scripts/ui/hud_bar.gd")
const TranscriptPanel := preload("res://scripts/ui/transcript_panel.gd")
const ModalScript := preload("res://scripts/ui/modal.gd")

const JAM_DURATION := [14.0, 11.0, 9.0, 7.0]
const JAM_COOLDOWN := [70.0, 46.0, 32.0, 22.0]

var content: Control
var room: Control
var window_view: Control
var map: Control
var radio: Control
var hud: Control
var transcript: Control
var _overlay: Control
var _modal: Control

var _started := false
var _paused := false
var _reveal_active := false
var _final_triggered := false
var _t := 0.0
var _shake := 0.0
var _glitch_burst := 0.0
var _toasts: Array = []
var _rng := RandomNumberGenerator.new()
var _hints := {}
var _reveal_pending := -1
var _reveal_timer := 0.0

# Jam state.
var jam_active := false
var jam_timer := 0.0
var jam_freq := 0.0
var jam_clear := 0.0
var jam_cooldown := 26.0
var jam_hold := 0.0
var jam_amount := 0.0
var glitch := 0.0


class Overlay extends Control:
	var screen: Node

	func _draw() -> void:
		screen.draw_overlay(self)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_rng.seed = randi()
	_build()
	_connect_state()
	_show_intro()


func _build() -> void:
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content)

	room = RoomBackground.new()
	content.add_child(room)

	window_view = WindowView.new()
	content.add_child(window_view)

	map = MapChart.new()
	content.add_child(map)

	radio = RadioPanel.new()
	content.add_child(radio)

	transcript = TranscriptPanel.new()
	content.add_child(transcript)

	hud = HudBar.new()
	add_child(hud)

	_overlay = Overlay.new()
	_overlay.screen = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	map.pin_placed.connect(_on_pin_placed)
	map.pin_rejected.connect(_on_pin_rejected)
	radio.signal_locked.connect(_on_signal_locked)
	hud.cell_pressed.connect(_on_cell_pressed)
	hud.mute_pressed.connect(_on_mute_pressed)

	resized.connect(_layout)
	_layout()


func _layout() -> void:
	if room == null:
		return
	room.position = Vector2.ZERO
	room.size = size
	hud.position = Vector2.ZERO
	hud.size = Vector2(size.x, 54.0)
	window_view.position = Vector2(14, 62)
	window_view.size = Vector2(584, 186)
	map.position = Vector2(14, 256)
	map.size = Vector2(584, 452)
	radio.position = Vector2(610, 62)
	radio.size = Vector2(656, 436)
	transcript.position = Vector2(610, 506)
	transcript.size = Vector2(656, 202)


func _connect_state() -> void:
	GameState.toast_emitted.connect(_on_toast)
	GameState.signal_discovered.connect(_on_discovered)
	GameState.blackout_started.connect(_on_blackout)
	GameState.blackout_ended.connect(_on_blackout_end)
	GameState.chapter_changed.connect(_on_chapter_changed)
	GameState.power_changed.connect(_on_power_changed)


func _show_intro() -> void:
	_paused = true
	_show_modal({
		"title": "STATION K-7",
		"subtitle": "02:00 - THE STORM TOOK THE MAINLAND LINE THREE HOURS AGO",
		"accent": Palette.PHOSPHOR,
		"body": [
			"YOU ARE THE NIGHT OPERATOR OF A COASTAL RADIO RELAY.",
			"TUNE THE RECEIVER TO PULL DISTRESS SIGNALS OUT OF THE STATIC.",
			"EVERY SIGNAL LOGS A POSITION. PLOT THREE ON THE CHART",
			"AND THE PINS WILL TRIANGULATE ITS SOURCE.",
			"",
			"THE RADIO EATS POWER. IN THE DARK, SOMETHING LISTENS BACK.",
		],
		"footer": "BATTERY 100%   /   1 EMERGENCY CELL   /   MED POWER STAGE",
		"buttons": [{"id": "begin", "label": "BEGIN WATCH"}],
	})
	_modal.pressed.connect(func(_id): _dismiss_modal(); _started = true; _paused = false; _push_hint())


func _process(delta: float) -> void:
	_t += delta
	if _started and not _paused and not GameState.ended:
		GameState.tick(delta)
		_update_jam(delta)
	if _reveal_pending > 0:
		_reveal_timer -= delta
		if _reveal_timer <= 0.0:
			var ch := _reveal_pending
			_reveal_pending = -1
			_present_reveal(ch)
	_update_visuals()
	_update_audio()
	_check_progress()
	_update_toasts(delta)
	_update_shake(delta)
	_overlay.queue_redraw()


func _update_shake(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta * 4.0)
	var amp := _shake * 7.0 + jam_amount * 3.0 + GameState.presence / 100.0 * 1.4
	if GameState.ended:
		amp = 0.0
	content.position = Vector2(_rng.randf_range(-amp, amp), _rng.randf_range(-amp, amp))


func _update_visuals() -> void:
	var dim: float = [0.22, 0.62, 1.0, 1.18][clampi(GameState.power, 0, 3)]
	if GameState.blackout:
		dim = 0.05
	room.presence = GameState.presence
	room.power_dim = dim
	room.jam = jam_amount
	window_view.presence = GameState.presence
	window_view.chapter = GameState.chapter
	window_view.battery = GameState.battery
	window_view.jam = jam_amount + _glitch_burst
	map.chapter = GameState.chapter
	radio.glitch = clampf(jam_amount * 0.8 + _glitch_burst, 0.0, 1.0)
	radio.power_dim = dim
	radio.enabled = GameState.power != GameState.Power.STANDBY and not GameState.blackout
	var active := _active_signals()
	if radio.active_signals != active:
		radio.active_signals = active
	var logged: Array = []
	for i in SignalDB.signals.size():
		if int(SignalDB.signals[i]["chapter"]) == GameState.chapter and GameState.discovered.has(i):
			logged.append(i)
	if radio.logged_signals != logged:
		radio.logged_signals = logged
	radio.jam_visual = {
		"jam_f": jam_freq,
		"jam_amt": 1.0 if (jam_active or _glitch_burst > 0.1) else 0.0,
		"clear_f": jam_clear,
		"clear_amt": 1.0 if jam_active else 0.0,
		"hold": clampf(jam_hold, 0.0, 1.0),
	}
	_glitch_burst = maxf(0.0, _glitch_burst - 0.016)
	GameState.fx_jam = clampf(0.34 + jam_amount * 0.72, 0.0, 1.0) if jam_active else 0.0
	GameState.fx_glitch = clampf(_glitch_burst, 0.0, 1.0)


func _active_signals() -> Array:
	var out: Array = []
	for i in SignalDB.signals.size():
		var s: Dictionary = SignalDB.signals[i]
		if int(s["chapter"]) != GameState.chapter:
			continue
		if GameState.discovered.has(i):
			continue
		out.append(i)
	return out


func _update_audio() -> void:
	var standby := GameState.power == GameState.Power.STANDBY
	var base := 0.05 if standby else 0.16
	var s: float = base + 0.44 * (1.0 - clampf(radio.strength, 0.0, 1.0))
	s = clampf(s + jam_amount * 0.5, 0.0, 1.0)
	Audio.set_static(s * (0.55 + 0.15 * float(GameState.power)), 1.0 + jam_amount * 0.9)
	Audio.set_carrier(pow(clampf(radio.strength, 0.0, 1.0), 2.0) * 0.38)
	Audio.set_hum(0.10 if standby else 0.20)
	Audio.set_drone(clampf(GameState.presence / 100.0 * 0.45 + float(GameState.chapter - 1) * 0.05, 0.0, 0.6))
	Audio.set_heart(clampf((GameState.presence - 45.0) / 55.0, 0.0, 1.0) * 0.7)


# ------------------------------------------------------------------- jamming
func _update_jam(delta: float) -> void:
	if GameState.blackout:
		jam_active = false
		jam_amount = 0.0
		return
	if not jam_active:
		jam_amount = maxf(0.0, jam_amount - delta * 0.8)
		jam_cooldown -= delta
		if jam_cooldown <= 0.0:
			_start_jam()
		return
	jam_timer -= delta
	var d := absf(radio.frequency - jam_clear)
	if d < 0.35:
		jam_hold += delta
		if jam_hold >= 1.0:
			_end_jam(true)
			return
	else:
		jam_hold = maxf(0.0, jam_hold - delta * 2.2)
	jam_amount = exp(-pow((radio.frequency - jam_freq) / 1.5, 2.0)) * 0.85
	if jam_timer <= 0.0:
		_end_jam(false)


func _start_jam() -> void:
	jam_active = true
	jam_hold = 0.0
	jam_timer = JAM_DURATION[clampi(GameState.chapter - 1, 0, 3)]
	var spread := (SignalDB.BAND_MAX - SignalDB.BAND_MIN)
	jam_freq = snappedf(SignalDB.BAND_MIN + 2.0 + _rng.randf() * (spread - 4.0), 0.05)
	var mid := (SignalDB.BAND_MIN + SignalDB.BAND_MAX) * 0.5
	jam_clear = jam_freq + (6.5 if jam_freq < mid else -6.5)
	jam_clear = clampf(jam_clear, SignalDB.BAND_MIN + 0.6, SignalDB.BAND_MAX - 0.6)
	jam_amount = 0.8
	_shake = 1.0
	Audio.play("glitch_002.ogg", -4.0)
	GameState.toast("INTERFERENCE SPIKE - RETUNE TO THE CLEAR CHANNEL", "bad")


func _end_jam(success: bool) -> void:
	jam_active = false
	jam_hold = 0.0
	jam_amount = 0.0
	var idx: int = clampi(GameState.chapter - 1, 0, 3)
	jam_cooldown = JAM_COOLDOWN[idx] * _rng.randf_range(0.85, 1.2)
	if success:
		GameState.jams_survived += 1
		GameState.toast("INTERFERENCE EVADED", "good")
		GameState.add_battery(1.0)
		GameState.add_presence(-2.0)
		Audio.play("confirmation_002.ogg", -5.0)
	else:
		GameState.toast("THE INTERFERENCE GOT IN", "bad")
		GameState.add_battery(-9.0)
		GameState.add_presence(GameState.JAM_FAIL_PRESENCE)
		GameState.jam_failures += 1
		_glitch_burst = 1.0
		GameState.fx_glitch = 1.0
		_shake = 1.0
		Audio.play("glitch_004.ogg", -2.0)
		Audio.play("lowFrequency_explosion_000.ogg", -8.0)


# ------------------------------------------------------------ signal & chart
func _on_signal_locked(index: int) -> void:
	if GameState.discovered.has(index):
		return
	GameState.discover(index)
	radio.consume_lock()
	transcript.show_signal(index)
	map.pulse()
	Audio.play("spaceTrash2.ogg", -6.0)
	Audio.play("blip.wav", -8.0)
	_shake = 0.5
	if int(SignalDB.signals[index]["chapter"]) == 4:
		GameState.toast("FINAL CARRIER LOCKED", "bad")
	else:
		GameState.toast("SIGNAL LOCKED - COORDINATE LOGGED", "good")
	if not _hints.has("plot"):
		_hints["plot"] = true
		GameState.toast("OPEN THE CHART AND PLOT THE COORDINATE", "info")


func _on_discovered(_index: int) -> void:
	pass


func _on_pin_placed(_index: int, offset_km: float) -> void:
	GameState.toast("PIN PLACED - OFFSET %.1f KM" % offset_km, "good")
	map.pulse()
	_shake = 0.35


func _on_pin_rejected() -> void:
	GameState.toast("NO CARRIER AT THAT POSITION", "warn")


func _on_cell_pressed() -> void:
	if GameState.cells <= 0:
		GameState.toast("NO CELLS REMAINING", "warn")
		Audio.play("error_004.ogg", -10.0)
		return
	if GameState.use_cell():
		_dismiss_modal()


func _on_mute_pressed() -> void:
	Audio.toggle_mute()


func _on_chapter_changed(ch: int) -> void:
	GameState.toast("CHAPTER %d - %s" % [ch, _chapter_name(ch)], "info")


func _chapter_name(ch: int) -> String:
	return ["", "THREE VOICES", "KESTREL", "IT LEARNS", "SIGNAL LOST"][clampi(ch, 0, 4)]


func _on_power_changed(_mode: int) -> void:
	Audio.play("switch_007.ogg", -10.0)


func _check_progress() -> void:
	if GameState.ended or _paused:
		return
	if GameState.chapter < 4:
		if not _reveal_active and GameState.chapter_ready(GameState.chapter):
			_begin_reveal(GameState.chapter)
	elif GameState.final_signal_found() and not _final_triggered:
		_final_triggered = true
		_begin_final()


func _begin_reveal(ch: int) -> void:
	_reveal_active = true
	_paused = true
	map.trigger_reveal(ch)
	map.pulse()
	_shake = 0.8
	Audio.play("sweep.wav", -5.0)
	Audio.play("threeTone1.ogg", -8.0)
	_reveal_pending = ch
	_reveal_timer = 0.9


func _present_reveal(ch: int) -> void:
	GameState.complete_triangulation(ch)
	var src: Dictionary = SignalDB.source(ch)
	var body: Array = []
	for l in src["reveal"]:
		body.append(String(l))
	_show_modal({
		"title": "TRIANGULATION COMPLETE",
		"subtitle": "CHAPTER %d  -  %s" % [ch, String(src["name"])],
		"accent": Color("ffb454"),
		"body": body,
		"footer": String(src["reward"]),
		"buttons": [{"id": "continue", "label": "CONTINUE"}],
	})
	_modal.pressed.connect(func(_id):
		_dismiss_modal()
		_reveal_active = false
		_paused = false
		if ch == 3:
			GameState.toast("THE FINAL CARRIER IS ON YOUR OWN FREQUENCY", "bad")
	)


func _begin_final() -> void:
	_paused = true
	_shake = 1.0
	Audio.play("lowFrequency_explosion_001.ogg", -3.0)
	Audio.set_drone(0.7)
	var body: Array = []
	for l in SignalDB.FINAL_REVEAL:
		body.append(String(l))
	_show_modal({
		"title": "FINAL TRANSMISSION",
		"subtitle": "THE CARRIER IS WAITING FOR AN ANSWER",
		"accent": Palette.RED,
		"body": body,
		"footer": "THERE IS STILL TIME TO DECIDE WHAT K-7 BECOMES.",
		"buttons": [
			{"id": "warning", "label": "TRANSMIT THE WARNING"},
			{"id": "silence", "label": "CUT THE POWER"},
			{"id": "answer", "label": "ANSWER THE VOICE"},
		],
	})
	_modal.pressed.connect(func(id):
		Audio.play("switch_003.ogg", -6.0)
		GameState.finish(String(id))
	)


# ---------------------------------------------------------------- blackout
func _on_blackout(has_cells: bool) -> void:
	_paused = true
	jam_active = false
	jam_amount = 0.0
	_shake = 1.0
	Audio.set_static(0.1)
	Audio.play("lowFrequency_explosion_000.ogg", -6.0)
	if has_cells:
		_show_modal({
			"title": "POWER LOST",
			"subtitle": "THE BATTERY IS DEAD AND THE ROOM IS GOING COLD",
			"accent": Palette.RED,
			"body": [
				"SOMETHING IS ALREADY AT THE GLASS.",
				"YOU HAVE AN EMERGENCY CELL IN THE DESK DRAWER.",
				"IT WILL BUY YOU A FEW MORE MINUTES.",
			],
			"footer": "EMERGENCY CELLS REMAINING: %d" % GameState.cells,
			"buttons": [{"id": "cell", "label": "USE EMERGENCY CELL"}],
		})
		_modal.pressed.connect(func(_id):
			_dismiss_modal()
			GameState.use_cell()
			_paused = false
		)
	else:
		_show_modal({
			"title": "NO POWER REMAINING",
			"subtitle": "THERE IS NOTHING LEFT IN THE DRAWER",
			"accent": Palette.RED,
			"body": [
				"THE STATIC IS GETTING LOUDER WITHOUT THE RADIO.",
				"IT DOES NOT NEED THE ANTENNA ANY MORE.",
			],
			"footer": "",
			"buttons": [],
		})


func _on_blackout_end() -> void:
	_dismiss_modal()
	_paused = false


# ------------------------------------------------------------------- modal
func _show_modal(config: Dictionary) -> void:
	_dismiss_modal()
	var m: Control = ModalScript.new()
	m.title = String(config.get("title", ""))
	m.subtitle = String(config.get("subtitle", ""))
	m.body_lines = config.get("body", [])
	m.footer = String(config.get("footer", ""))
	m.accent = config.get("accent", Palette.PHOSPHOR)
	m.buttons = config.get("buttons", [])
	_modal = m
	add_child(m)


func _dismiss_modal() -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null


# ------------------------------------------------------------------- toasts
func _on_toast(text: String, kind: String) -> void:
	_toasts.append({"text": text, "kind": kind, "t": 0.0})
	if _toasts.size() > 4:
		_toasts.pop_front()


func _update_toasts(delta: float) -> void:
	for t in _toasts:
		t["t"] += delta
	while not _toasts.is_empty() and _toasts[0]["t"] > 5.0:
		_toasts.pop_front()


func _push_hint() -> void:
	GameState.toast("TURN THE DIAL OR USE ARROW KEYS TO TUNE", "info")


func draw_overlay(ci: CanvasItem) -> void:
	# Jam banner.
	if jam_active:
		var w := 520.0
		var r := Rect2((size.x - w) * 0.5, 62.0, w, 46.0)
		ci.draw_rect(r, Color(0.14, 0.03, 0.05, 0.9))
		ci.draw_rect(r, Palette.RED, false, 2.0)
		UIKit.text_center(ci, Vector2(r.get_center().x, r.position.y + 20.0), "INTERFERENCE DETECTED", 20, Palette.RED)
		var ratio: float = clampf(jam_timer / maxf(JAM_DURATION[clampi(GameState.chapter - 1, 0, 3)], 0.01), 0.0, 1.0)
		var bar := Rect2(r.position.x + 16.0, r.position.y + 30.0, r.size.x - 32.0, 8.0)
		ci.draw_rect(bar, Color(0.2, 0.05, 0.07))
		ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Palette.RED)
		UIKit.text_center(ci, Vector2(r.get_center().x, r.end.y + 16.0), "TUNE TO THE CLEAR CHANNEL AND HOLD", 14, Color(1.0, 0.7, 0.72))
	# Low battery warning: pulsing screen edge rather than text over the chart.
	if GameState.battery < 20.0 and not GameState.ended and not GameState.blackout:
		var a := 0.10 + 0.10 * sin(_t * 4.0)
		var edge := Color(1.0, 0.25, 0.3, a)
		ci.draw_rect(Rect2(0, 0, size.x, 6.0), edge)
		ci.draw_rect(Rect2(0, size.y - 6.0, size.x, 6.0), edge)
		ci.draw_rect(Rect2(0, 0, 6.0, size.y), edge)
		ci.draw_rect(Rect2(size.x - 6.0, 0, 6.0, size.y), edge)
	# Toasts.
	var y := 152.0 if jam_active else 68.0
	for t in _toasts:
		var age: float = t["t"]
		var alpha: float = clampf(minf(age * 4.0, (5.0 - age) * 2.0), 0.0, 1.0)
		var col: Color = Palette.PHOSPHOR
		match String(t["kind"]):
			"bad":
				col = Palette.RED
			"warn":
				col = Palette.AMBER
			"good":
				col = Palette.PHOSPHOR
			_:
				col = Palette.CYAN
		var txt := String(t["text"])
		var f := UIKit.font_mono()
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var box := Rect2((size.x - tw) * 0.5 - 14.0, y - 16.0, tw + 28.0, 26.0)
		ci.draw_rect(box, Color(0.02, 0.05, 0.05, 0.85 * alpha))
		ci.draw_rect(box, Color(col.r, col.g, col.b, alpha * 0.8), false, 1.0)
		UIKit.text_center(ci, box.get_center() + Vector2(0, 1), txt, 15, Color(col.r, col.g, col.b, alpha), f)
		y += 30.0
	# Presence whisper.
	if GameState.presence > 45.0 and not GameState.ended:
		var msg := "YOU ARE NOT ALONE IN THIS BAND."
		if GameState.presence > 75.0:
			msg = "IT IS READING YOUR NAME OFF THE DIAL."
		var a2 := clampf((GameState.presence - 45.0) / 55.0, 0.0, 1.0)
		UIKit.text_center(ci, Vector2(size.x * 0.5, 108.0 if jam_active else 88.0), msg, 15, Color(0.85, 0.3, 0.35, a2 * (0.5 + 0.5 * sin(_t * 1.7))))


# ------------------------------------------------------- scenario shortcuts
func apply_scenario(id: String) -> void:
	_started = true
	_paused = false
	_dismiss_modal()
	match id:
		"signal_scan":
			GameState.discover(0)
			transcript.show_signal(0)
			radio.set_frequency(SignalDB.signals[1]["freq"] + 0.35)
		"map":
			for i in 3:
				GameState.discover(i)
			GameState.place_pin(0, 1.4)
			GameState.place_pin(1, 0.9)
			transcript.show_signal(2)
			radio.set_frequency(SignalDB.signals[2]["freq"])
		"jamming":
			GameState.discover(0)
			transcript.show_signal(0)
			jam_cooldown = 0.0
			_start_jam()
			jam_timer = JAM_DURATION[0] * 0.55
			radio.set_frequency(jam_freq + 1.7)
		"triangulation":
			for i in 3:
				GameState.discover(i)
				GameState.place_pin(i, 1.0)
			transcript.show_signal(2)
			_begin_reveal(1)
		"chapter2":
			_seed_chapters(2)
			transcript.show_signal(3)
			radio.set_frequency(SignalDB.signals[4]["freq"] + 0.5)
		"chapter3":
			_seed_chapters(3)
			GameState.presence = 48.0
			transcript.show_signal(6)
			radio.set_frequency(SignalDB.signals[7]["freq"] + 0.4)
		"near_victory":
			_seed_chapters(4)
			GameState.battery = 17.0
			GameState.presence = 74.0
			GameState.cells = 1
			radio.set_frequency(SignalDB.signals[9]["freq"] + 0.3)
			GameState.toast("POWER CRITICAL - CELL RESERVE LOW", "warn")
		"uitest":
			_run_uitest()
		"blackout":
			_seed_chapters(2)
			GameState.cells = 1
			GameState.battery = 0.0
			GameState.blackout = true
			GameState.power = GameState.Power.STANDBY
			_on_blackout(true)
		"final":
			_seed_chapters(4)
			GameState.battery = 42.0
			GameState.presence = 61.0
			GameState.discover(9)
			transcript.show_signal(9)
			_final_triggered = true
			_begin_final()


## Exercises the real interaction code paths (dial lock, chart click, HUD
## buttons) and reports the result, then quits with a status code.
func _run_uitest() -> void:
	var report: Array = []
	# 1. Turning the dial onto a carrier must run through the detection path.
	GameState.set_power(GameState.Power.MED)
	radio.active_signals = _active_signals()
	radio.set_frequency(SignalDB.signals[0]["freq"])
	for _i in 12:
		radio._update_detection(0.2)
	report.append(["dial lock discovers a carrier", GameState.discovered.has(0)])
	# 2. Clicking the chart at a logged coordinate places a pin.
	GameState.place_pin(0, 0.0)
	var ll: Vector2 = Vector2(SignalDB.signals[1]["lat"], SignalDB.signals[1]["lon"])
	GameState.discover(1)
	map._try_place(map.latlon_to_local(ll.x, ll.y))
	report.append(["chart click plots a coordinate", GameState.has_pin(1)])
	# 3. Clicking empty water does not place anything.
	var before: int = GameState.pins.size()
	map._try_place(map.latlon_to_local(44.0, -61.6))
	report.append(["stray chart click rejected", GameState.pins.size() == before])
	# 4. Off-band / standby tuning must never produce a lock.
	GameState.set_power(GameState.Power.STANDBY)
	var locked_before: int = GameState.discovered.size()
	radio.set_frequency(SignalDB.signals[2]["freq"])
	for _i in 12:
		radio._update_detection(0.2)
	report.append(["standby cannot lock carriers", GameState.discovered.size() == locked_before])
	# 5. Emergency cell button.
	GameState.set_power(GameState.Power.MED)
	GameState.battery = 40.0
	GameState.cells = 2
	hud.cell_pressed.emit()
	report.append(["cell button restores power", GameState.battery > 60.0 and GameState.cells == 1])
	# 6. Power stage buttons.
	GameState.set_power(GameState.Power.LOW)
	report.append(["power stage switches", GameState.power == GameState.Power.LOW])
	var failures := 0
	for r in report:
		print("UITEST %s: %s" % ["PASS" if bool(r[1]) else "FAIL", String(r[0])])
		if not bool(r[1]):
			failures += 1
	print("UITEST %s (%d/%d)" % ["PASS" if failures == 0 else "FAIL", report.size() - failures, report.size()])
	get_tree().quit(0 if failures == 0 else 1)


func _seed_chapters(upto: int) -> void:
	for ch in range(1, upto):
		for i in SignalDB.signals.size():
			if int(SignalDB.signals[i]["chapter"]) == ch:
				GameState.discover(i)
				GameState.place_pin(i, 1.0)
		if not GameState.triangulated.has(ch):
			GameState.triangulated.append(ch)
	if upto > 1:
		GameState.chapter = upto
		GameState.chapter_changed.emit(upto)
	GameState.battery = 62.0
	GameState.presence = maxf(GameState.presence, 30.0)
