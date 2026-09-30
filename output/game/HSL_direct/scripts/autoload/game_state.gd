extends Node
## Global run state for Horror Signal Lost. The station screen drives the
## per-frame tick so nothing drains while menus are up.

signal battery_changed(value: float)
signal power_changed(mode: int)
signal presence_changed(value: float)
signal cells_changed(count: int)
signal signal_discovered(index: int)
signal pin_placed(index: int, offset_km: float)
signal chapter_changed(chapter: int)
signal triangulation_complete(chapter: int)
signal toast_emitted(text: String, kind: String)
signal blackout_started(has_cells: bool)
signal blackout_ended()
signal run_ended(reason: String)

enum Power { STANDBY, LOW, MED, HIGH }

const POWER_NAMES := ["STANDBY", "LOW", "MED", "HIGH"]
const POWER_DRAIN := [0.045, 0.13, 0.26, 0.48]
const POWER_SIGMA := [0.0, 0.10, 0.17, 0.28]
const POWER_LOCK := [99.0, 2.2, 1.5, 1.0]
const POWER_COLOR := [Color("4b6a60"), Color("66dcff"), Color("74f7b4"), Color("ffb454")]

const START_BATTERY := 100.0
const START_CELLS := 1
const CELL_POWER := 25.0
const TRIANGULATION_BATTERY := 20.0
const MAX_CHAPTERS := 4

const PRESENCE_RATE := [0.0, 0.022, 0.06, 0.13]
const JAM_FAIL_PRESENCE := 9.0

var battery := START_BATTERY
var power := Power.MED
var presence := 0.0
var cells := START_CELLS
var chapter := 1
var discovered: Array = []
var pins: Array = []
var triangulated: Array = []
var selected_signal := -1
var elapsed := 0.0
var ended := false
var end_reason := ""
var ending_id := ""
var blackout := false
var blackout_timer := 0.0
var fx_jam := 0.0
var fx_glitch := 0.0
var jam_failures := 0
var jams_survived := 0
var signals_locked := 0
var _rng := RandomNumberGenerator.new()


func reset(seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system())
	_rng.seed = seed_value
	battery = START_BATTERY
	power = Power.MED
	presence = 0.0
	cells = START_CELLS
	chapter = 1
	discovered.clear()
	pins.clear()
	triangulated.clear()
	selected_signal = -1
	elapsed = 0.0
	ended = false
	end_reason = ""
	ending_id = ""
	blackout = false
	blackout_timer = 0.0
	fx_jam = 0.0
	fx_glitch = 0.0
	jam_failures = 0
	jams_survived = 0
	signals_locked = 0
	SignalDB.build_run(seed_value)


func tick(delta: float) -> void:
	if ended:
		return
	if blackout:
		blackout_timer += delta
		add_presence((1.6 + blackout_timer * 1.6) * delta)
		if cells == 0 and blackout_timer > 6.5:
			end_run("dark")
		return
	elapsed += delta
	add_battery(-POWER_DRAIN[power] * delta)
	var rate: float = PRESENCE_RATE[clampi(chapter - 1, 0, MAX_CHAPTERS - 1)]
	if power == Power.STANDBY:
		rate += 0.22
	elif power == Power.HIGH:
		rate += 0.05
	if battery < 15.0:
		rate += 0.18
	if rate > 0.0:
		add_presence(rate * delta)
	if battery <= 0.0:
		_enter_blackout()


func add_battery(value: float) -> void:
	var next: float = clampf(battery + value, 0.0, 100.0)
	var changed := not is_equal_approx(next, battery)
	battery = next
	if changed:
		battery_changed.emit(battery)
	if battery <= 0.0 and not blackout:
		_enter_blackout()


func _enter_blackout() -> void:
	if blackout:
		return
	blackout = true
	blackout_timer = 0.0
	power = Power.STANDBY
	power_changed.emit(power)
	blackout_started.emit(cells > 0)


func add_presence(value: float) -> void:
	if ended:
		return
	presence = clampf(presence + value, 0.0, 100.0)
	presence_changed.emit(presence)
	if presence >= 100.0:
		end_run("consumed")


func set_power(mode: int) -> void:
	if blackout or ended:
		return
	var m: int = clampi(mode, 0, 3)
	if m == power:
		return
	power = m
	power_changed.emit(power)


func cycle_power() -> void:
	set_power((power + 1) % 4)


func use_cell() -> bool:
	if cells <= 0:
		return false
	cells -= 1
	cells_changed.emit(cells)
	battery = clampf(battery + CELL_POWER, 0.0, 100.0)
	battery_changed.emit(battery)
	if blackout and battery > 0.0:
		blackout = false
		blackout_timer = 0.0
		blackout_ended.emit()
	Audio.play("powerUp1.ogg", -3.0)
	toast("EMERGENCY CELL ENGAGED  +%d%%" % int(CELL_POWER), "good")
	return true


func discover(index: int) -> void:
	if discovered.has(index):
		return
	discovered.append(index)
	selected_signal = index
	signals_locked += 1
	add_presence(-1.5)
	signal_discovered.emit(index)


func place_pin(index: int, offset_km: float) -> void:
	pins.append({"signal": index, "lat": SignalDB.signals[index]["lat"], "lon": SignalDB.signals[index]["lon"]})
	pin_placed.emit(index, offset_km)


func has_pin(index: int) -> bool:
	for p in pins:
		if p["signal"] == index:
			return true
	return false


func pending_pins(ch: int = -1) -> Array:
	var target := chapter if ch < 0 else ch
	var out: Array = []
	if target >= MAX_CHAPTERS:
		return out
	for i in SignalDB.signals.size():
		var s: Dictionary = SignalDB.signals[i]
		if int(s["chapter"]) != target:
			continue
		if discovered.has(i) and not has_pin(i):
			out.append(i)
	return out


func chapter_found(ch: int) -> int:
	var n := 0
	for i in discovered:
		if int(SignalDB.signals[i]["chapter"]) == ch:
			n += 1
	return n


func chapter_pins(ch: int) -> int:
	var n := 0
	for p in pins:
		if int(SignalDB.signals[p["signal"]]["chapter"]) == ch:
			n += 1
	return n


func chapter_ready(ch: int) -> bool:
	if triangulated.has(ch):
		return false
	var total := SignalDB.chapter_signal_count(ch)
	if total <= 0:
		return false
	return chapter_found(ch) >= total and chapter_pins(ch) >= total


func complete_triangulation(ch: int) -> void:
	if triangulated.has(ch):
		return
	triangulated.append(ch)
	if ch < 3:
		add_battery(TRIANGULATION_BATTERY)
	cells += 1
	cells_changed.emit(cells)
	triangulation_complete.emit(ch)
	if ch < MAX_CHAPTERS:
		chapter = ch + 1
		chapter_changed.emit(chapter)


func final_signal_found() -> bool:
	return discovered.has(SignalDB.final_signal_index())


func finish(ending: String, reason: String = "") -> void:
	ending_id = ending
	end_reason = reason
	end_run(reason if not reason.is_empty() else ending)


func end_run(reason: String) -> void:
	if ended:
		return
	ended = true
	end_reason = reason
	if ending_id.is_empty():
		ending_id = "consumed" if reason != "dark" else "dark"
	run_ended.emit(reason)


func toast(text: String, kind: String = "info") -> void:
	toast_emitted.emit(text, kind)


func objective_text() -> String:
	if ended:
		return ""
	if chapter >= MAX_CHAPTERS:
		var total := SignalDB.chapter_signal_count(MAX_CHAPTERS)
		var found := chapter_found(MAX_CHAPTERS)
		if found >= total:
			return "ANSWER THE FINAL SIGNAL"
		return "TRACK THE FINAL CARRIER  %d/%d" % [found, total]
	var total := SignalDB.chapter_signal_count(chapter)
	var found := chapter_found(chapter)
	var pin := chapter_pins(chapter)
	var pending := pending_pins().size()
	if found < total:
		return "CHAPTER %d  -  TUNE IN SIGNALS  %d/%d" % [chapter, found, total]
	if pending > 0:
		return "CHAPTER %d  -  PLOT COORDINATES  %d/%d" % [chapter, pin, total]
	return "CHAPTER %d  -  TRIANGULATING..." % chapter


func clock_text() -> String:
	var t := int(elapsed)
	var h := 2 + int(t / 3600.0)
	var m := int((t / 60.0)) % 60
	var s := t % 60
	return "%02d:%02d:%02d" % [h % 24, m, s]
