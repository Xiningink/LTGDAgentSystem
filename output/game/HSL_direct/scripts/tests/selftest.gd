class_name SelfTest
extends RefCounted
## Headless self-test for the signal / triangulation / power state machine.
## Driven by the `selftest` scenario, or any script with the autoloads live.

const P_STANDBY := 0
const P_LOW := 1
const P_MED := 2
const P_HIGH := 3

static var _failures: Array = []
static var _checks := 0


static func ok(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


static func run() -> Array:
	_failures = []
	_checks = 0
	_test_database()
	_test_coordinates()
	_test_progression()
	_test_economy()
	_test_blackout()
	_test_endings()
	_test_story()
	print("SELFTEST %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	for f in _failures:
		print("   FAILED: ", f)
	return _failures


static func _test_database() -> void:
	SignalDB.build_run(1234)
	ok(SignalDB.signals.size() == 10, "10 signals authored")
	ok(SignalDB.chapter_signal_count(1) == 3, "chapter 1 has 3 signals")
	ok(SignalDB.chapter_signal_count(2) == 3, "chapter 2 has 3 signals")
	ok(SignalDB.chapter_signal_count(3) == 3, "chapter 3 has 3 signals")
	ok(SignalDB.chapter_signal_count(4) == 1, "chapter 4 has 1 signal")
	ok(SignalDB.final_signal_index() == 9, "final signal index is 9")
	var freqs: Array = []
	for s in SignalDB.signals:
		var f: float = s["freq"]
		ok(f >= SignalDB.BAND_MIN and f <= SignalDB.BAND_MAX, "carrier inside band")
		for other in freqs:
			ok(absf(float(other) - f) > 1.0, "carriers well separated (%.2f vs %.2f)" % [other, f])
		freqs.append(f)
	for ch in range(1, 4):
		var acc := Vector2.ZERO
		var n := 0
		for s in SignalDB.signals:
			if int(s["chapter"]) == ch:
				acc += Vector2(s["lat"], s["lon"])
				n += 1
		acc /= float(n)
		var src: Dictionary = SignalDB.source(ch)
		ok(Vector2(src["lat"], src["lon"]).distance_to(acc) < 0.0001, "source %d is the centroid" % ch)
	var final_index := SignalDB.final_signal_index()
	for i in SignalDB.signals.size():
		for j in range(i + 1, SignalDB.signals.size()):
			if i == final_index or j == final_index:
				continue  # the last carrier deliberately originates from K-7 itself
			var a: Dictionary = SignalDB.signals[i]
			var b: Dictionary = SignalDB.signals[j]
			ok(Vector2(a["lat"], a["lon"]).distance_to(Vector2(b["lat"], b["lon"])) > 0.2,
				"signals %d and %d are map-separated" % [i, j])


static func _test_coordinates() -> void:
	var lats := [SignalDB.LAT_MIN, 44.3, SignalDB.LAT_MAX]
	var lons := [SignalDB.LON_MIN, -63.2, SignalDB.LON_MAX]
	for lat in lats:
		for lon in lons:
			var back: Vector2 = SignalDB.map_latlon(SignalDB.map_uv(lat, lon))
			ok(absf(back.x - lat) < 0.0005 and absf(back.y - lon) < 0.0005, "lat/lon round trip")


static func _test_progression() -> void:
	GameState.reset(1234)
	ok(GameState.chapter == 1, "starts in chapter 1")
	ok(is_equal_approx(GameState.battery, 100.0), "starts at full battery")
	ok(GameState.cells == 1, "starts with one cell")
	for ch in range(1, 4):
		ok(not GameState.chapter_ready(ch), "chapter %d not ready before discovery" % ch)
		for i in SignalDB.signals.size():
			if int(SignalDB.signals[i]["chapter"]) == ch:
				GameState.discover(i)
		ok(not GameState.chapter_ready(ch), "chapter %d still needs pins" % ch)
		for i in SignalDB.signals.size():
			if int(SignalDB.signals[i]["chapter"]) == ch:
				GameState.place_pin(i, 1.0)
		ok(GameState.chapter_ready(ch), "chapter %d ready after pins" % ch)
		GameState.complete_triangulation(ch)
		ok(GameState.triangulated.has(ch), "chapter %d marked triangulated" % ch)
		ok(GameState.chapter == ch + 1, "advanced to chapter %d" % (ch + 1))
	ok(GameState.cells == 4, "one cell awarded per triangulation")
	ok(GameState.pending_pins().is_empty(), "no pending pins in chapter 4")
	GameState.discover(9)
	ok(GameState.final_signal_found(), "final signal detected")
	ok(not GameState.chapter_ready(4), "chapter 4 has no triangulation step")


static func _test_economy() -> void:
	GameState.reset(99)
	GameState.set_power(P_MED)
	var before: float = GameState.battery
	GameState.tick(60.0)
	ok(absf((before - GameState.battery) - GameState.POWER_DRAIN[P_MED] * 60.0) < 0.05, "medium drain matches table")
	GameState.set_power(P_STANDBY)
	before = GameState.battery
	GameState.tick(60.0)
	ok(GameState.battery < before, "standby still trickles power")
	for i in range(3):
		ok(GameState.POWER_DRAIN[i] < GameState.POWER_DRAIN[i + 1], "power stages ordered")


static func _test_blackout() -> void:
	GameState.reset(7)
	GameState.battery = 0.0
	GameState.add_battery(-0.001)
	ok(GameState.blackout, "blackout engages at zero power")
	ok(GameState.power == P_STANDBY, "radio forced to standby in blackout")
	ok(GameState.cells > 0, "cell available for recovery")
	GameState.use_cell()
	ok(not GameState.blackout, "cell clears the blackout")
	ok(GameState.battery > 20.0, "cell restores usable power")
	GameState.reset(7)
	GameState.cells = 0
	GameState.battery = 0.0
	GameState.add_battery(-0.001)
	ok(GameState.blackout, "blackout engages with no cells")
	for _i in 40:
		GameState.tick(0.5)
	ok(GameState.ended, "no cells means the run ends")
	ok(GameState.ending_id == "dark", "ending recorded as dark")


static func _test_endings() -> void:
	for id in ["warning", "silence", "answer"]:
		GameState.reset(3)
		GameState.finish(id)
		ok(GameState.ending_id == id, "choice ending %s recorded" % id)
		ok(GameState.ended, "choice ending %s ends the run" % id)
	GameState.reset(3)
	GameState.add_presence(100.0)
	ok(GameState.presence >= 100.0, "presence caps at 100")
	ok(GameState.ended, "full presence ends the run")
	ok(GameState.ending_id == "consumed", "presence ending is consumed")


static func _test_story() -> void:
	for key in ["warning", "silence", "answer", "consumed", "dark"]:
		var e: Dictionary = SignalDB.ENDINGS[key]
		ok(not String(e["title"]).is_empty(), "ending %s has a title" % key)
		ok((e["lines"] as Array).size() >= 4, "ending %s has body copy" % key)
	ok(SignalDB.FINAL_REVEAL.size() >= 5, "final reveal has copy")
	for s in SignalDB.signals:
		ok((s["lines"] as Array).size() >= 4, "signal %s has at least 4 lines" % s["caller"])
