extends Control
## Root controller: hosts screens, drives the CRT pass and applies test
## scenarios passed through the command line. Uses a process-driven fade so
## no coroutines are left suspended when the game exits.

const TITLE_SCENE := "res://scenes/TitleScreen.tscn"
const STATION_SCENE := "res://scenes/StationScreen.tscn"
const ENDING_SCENE := "res://scenes/EndingScreen.tscn"
const SELFTEST := preload("res://scripts/tests/selftest.gd")

const SCENARIO_SEED := 20240607
const FADE_OUT := 0.3
const FADE_IN := 0.42

var host: Control
var current: Control

var _fade: ColorRect
var _crt: ColorRect
var _crt_mat: ShaderMaterial
var _jam: ColorRect
var _jam_mat: ShaderMaterial
var _scenario := ""
var _ending_shown := false

var _fade_phase := 0
var _fade_t := 0.0
var _next_scene := ""
var _next_scenario := ""
var _end_delay := -1.0
var _autoenter := -1.0
var _autocheck := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	host = Control.new()
	host.name = "ScreenHost"
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)

	_jam = ColorRect.new()
	_jam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_jam.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_jam_mat = ShaderMaterial.new()
	_jam_mat.shader = load("res://assets/shaders/jam.gdshader")
	_jam_mat.set_shader_parameter("intensity", 0.0)
	_jam.material = _jam_mat
	_jam.visible = false
	add_child(_jam)

	_crt = ColorRect.new()
	_crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crt.color = Color(1, 1, 1, 1)
	_crt_mat = ShaderMaterial.new()
	_crt_mat.shader = load("res://assets/shaders/crt.gdshader")
	_crt.material = _crt_mat
	add_child(_crt)

	_fade = ColorRect.new()
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	add_child(_fade)

	GameState.run_ended.connect(_on_run_ended)
	_parse_args()
	_goto(TITLE_SCENE, false)
	if not _scenario.is_empty():
		_apply_scenario_start()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a == "--scenario" and i + 1 < args.size():
			_scenario = args[i + 1]
			i += 1
		elif a.begins_with("--scenario="):
			_scenario = a.substr("--scenario=".length())
		i += 1


func _process(delta: float) -> void:
	GameState.fx_glitch = maxf(0.0, GameState.fx_glitch - delta * 1.8)
	var p := clampf(GameState.presence / 100.0, 0.0, 1.0)
	var fx := maxf(GameState.fx_jam, GameState.fx_glitch)
	_jam.visible = fx > 0.01
	_jam_mat.set_shader_parameter("intensity", clampf(fx, 0.0, 1.0))
	_jam_mat.set_shader_parameter("seed", float(int(Time.get_ticks_msec() / 90.0) % 97))
	var corrupt := maxf(p * 0.35, GameState.fx_glitch * 0.5)
	if GameState.blackout:
		corrupt = maxf(corrupt, 0.45)
	_crt_mat.set_shader_parameter("corrupt", corrupt)
	_crt_mat.set_shader_parameter("flicker", 0.025 + p * 0.05)
	_crt_mat.set_shader_parameter("grain_strength", 0.04 + p * 0.05)
	_crt_mat.set_shader_parameter("scanline_strength", 0.05 + p * 0.05)

	if _fade_phase == 1:
		_fade_t += delta
		_fade.color.a = minf(_fade_t / FADE_OUT, 1.0)
		if _fade_t >= FADE_OUT:
			_swap_scene()
			_fade_phase = 2
			_fade_t = 0.0
	elif _fade_phase == 2:
		_fade_t += delta
		_fade.color.a = maxf(1.0 - _fade_t / FADE_IN, 0.0)
		if _fade_t >= FADE_IN:
			_fade_phase = 0
			_fade.color.a = 0.0

	if _end_delay > 0.0:
		_end_delay -= delta
		if _end_delay <= 0.0:
			_goto(ENDING_SCENE)

	if _autoenter > 0.0:
		_autoenter -= delta
		if _autoenter <= 0.0:
			_autoenter = -1.0
			_on_navigate("station", {})
			_autocheck = 0.8
	if _autocheck > 0.0:
		_autocheck -= delta
		if _autocheck <= 0.0:
			_autocheck = -1.0
			_run_flow_check()


func _run_flow_check() -> void:
	var problems: Array = []
	if SignalDB.signals.size() != 10:
		problems.append("signals not built (%d)" % SignalDB.signals.size())
	if GameState.chapter != 1:
		problems.append("chapter is %d" % GameState.chapter)
	if not GameState.discovered.is_empty():
		problems.append("spurious discoveries")
	if not GameState.triangulated.is_empty():
		problems.append("spurious triangulation")
	if not is_instance_valid(current) or current.name != "StationScreen":
		problems.append("station screen not shown")
	if not is_equal_approx(GameState.battery, 100.0):
		problems.append("battery is %.1f" % GameState.battery)
	if problems.is_empty():
		print("FLOWTEST PASS: title -> station starts a clean watch")
	else:
		print("FLOWTEST FAIL: ", ", ".join(problems))
	get_tree().quit(0 if problems.is_empty() else 1)


func _goto(path: String, use_fade := true, scenario := "") -> void:
	_next_scene = path
	_next_scenario = scenario
	if use_fade:
		_fade_phase = 1
		_fade_t = 0.0
	else:
		_fade_phase = 0
		_fade.color.a = 0.0
		_swap_scene()


func _swap_scene() -> void:
	GameState.fx_jam = 0.0
	GameState.fx_glitch = 0.0
	if current != null and is_instance_valid(current):
		current.queue_free()
		current = null
	if _next_scene.is_empty():
		return
	var packed: PackedScene = load(_next_scene)
	var inst: Control = packed.instantiate()
	current = inst
	host.add_child(inst)
	if inst.has_signal("navigate"):
		inst.navigate.connect(_on_navigate)
	var scenario := _next_scenario
	_next_scenario = ""
	if not scenario.is_empty() and inst.has_method("apply_scenario"):
		inst.call("apply_scenario", scenario)


func _on_navigate(screen: String, _payload: Dictionary) -> void:
	match screen:
		"title":
			Audio.stop_all()
			_ending_shown = false
			_goto(TITLE_SCENE)
		"station":
			Audio.stop_all()
			GameState.reset(SCENARIO_SEED if not _scenario.is_empty() else 0)
			_ending_shown = false
			_goto(STATION_SCENE)
		"restart":
			Audio.stop_all()
			GameState.reset(SCENARIO_SEED if not _scenario.is_empty() else 0)
			_ending_shown = false
			_goto(STATION_SCENE)
		"quit":
			get_tree().quit()


func _on_run_ended(_reason: String) -> void:
	if _ending_shown:
		return
	_ending_shown = true
	Audio.set_static(0.35, 0.6)
	Audio.set_drone(0.55)
	_end_delay = 1.1


# ------------------------------------------------------------------ scenarios
func _apply_scenario_start() -> void:
	var s := _scenario
	GameState.reset(SCENARIO_SEED)
	match s:
		"title":
			pass
		"station", "signal_scan", "map", "jamming", "triangulation", "chapter2", "chapter3", "near_victory", "blackout", "final", "uitest":
			_goto(STATION_SCENE, false, s)
		"ending":
			_seed_ending("warning", 31.0, 68.0, 743.0, 4)
		"selftest":
			var failures: Array = SELFTEST.run()
			get_tree().quit(0 if failures.is_empty() else 1)
		"enterstation":
			_autoenter = 0.25
		"consumed":
			_seed_ending("consumed", 6.0, 100.0, 512.0, 7)
		"dark":
			_seed_ending("dark", 0.0, 88.0, 655.0, 6)
		_:
			pass


func _seed_ending(id: String, battery: float, presence: float, elapsed: float, fails: int) -> void:
	GameState.discovered = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	GameState.pins.clear()
	for i in 10:
		GameState.pins.append({"signal": i, "lat": SignalDB.signals[i]["lat"], "lon": SignalDB.signals[i]["lon"]})
	GameState.triangulated = [1, 2, 3]
	GameState.chapter = 4
	GameState.battery = battery
	GameState.presence = presence
	GameState.elapsed = elapsed
	GameState.jam_failures = fails
	GameState.ending_id = id
	GameState.ended = true
	_ending_shown = true
	_goto(ENDING_SCENE, false)
