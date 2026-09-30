extends Control
# Top level flow controller: title -> station -> ending.
# Also owns the full screen interference post process.

const TitleScreenScene := preload("res://scenes/TitleScreen.tscn")
const StationScreenScene := preload("res://scenes/StationScreen.tscn")
const EndingScreenScene := preload("res://scenes/EndingScreen.tscn")

var _title: Control
var _station: Control
var _ending: Control
var _fx: ColorRect
var _fx_mat: ShaderMaterial

var _glitch := 0.05
var _corruption := 0.0
var _tint := Color(1, 1, 1, 1)
var _brightness := 1.0
var _scenario := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_scenario = _read_scenario()

	_title = TitleScreenScene.instantiate()
	add_child(_title)
	_title.connect("start_requested", Callable(self, "_start_run"))

	_ending = EndingScreenScene.instantiate()
	_ending.visible = false
	add_child(_ending)
	_ending.process_mode = Node.PROCESS_MODE_DISABLED
	_ending.connect("restart_requested", Callable(self, "_start_run"))
	_ending.connect("title_requested", Callable(self, "_show_title"))

	_reset_station()
	_show_only(_title)

	_fx = ColorRect.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = load("res://shaders/post_glitch.gdshader")
	_fx_mat.set_shader_parameter("glitch", _glitch)
	_fx_mat.set_shader_parameter("corruption", 0.0)
	_fx_mat.set_shader_parameter("vignette_strength", 1.0)
	_fx_mat.set_shader_parameter("brightness", 1.0)
	_fx_mat.set_shader_parameter("desat", 0.18)
	_fx_mat.set_shader_parameter("tint", Color(1, 1, 1, 1))
	_fx.material = _fx_mat
	add_child(_fx)

	_apply_scenario()


func _read_scenario() -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--scenario" and i + 1 < args.size():
			return args[i + 1]
	return ""


func _reset_station() -> void:
	if _station != null:
		remove_child(_station)
		_station.queue_free()
		_station = null
	_station = StationScreenScene.instantiate()
	_station.visible = false
	add_child(_station)
	_station.process_mode = Node.PROCESS_MODE_DISABLED
	_station.connect("finished", Callable(self, "_on_finished"))
	_station.connect("abort_requested", Callable(self, "_show_title"))


func _show_only(target: Control) -> void:
	for n in [_title, _station, _ending]:
		if n == null:
			continue
		var on: bool = (n == target)
		n.visible = on
		n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _show_title() -> void:
	_reset_station()
	_show_only(_title)


func _start_run() -> void:
	_reset_station()
	_show_only(_station)


func _on_finished(kind: String, stats: Dictionary) -> void:
	_ending.call("show_ending", kind, stats)
	_show_only(_ending)
	if not _scenario.is_empty():
		_ending.call("finish_reveal")


func _apply_scenario() -> void:
	match _scenario:
		"", "title":
			return
		"station":
			_start_run()
		"signal_scan":
			_start_run()
			_station.call("debug_setup", {"locked": [0]})
		"map_pins":
			_start_run()
			_station.call("debug_setup", {"pins": [0, 1, 2]})
		"escalation":
			_start_run()
			_station.call("debug_setup", {"pins": [0, 1, 2, 3], "corruption": 0.62})
		"jam":
			_start_run()
			_station.call("debug_setup", {"pins": [0, 1], "corruption": 0.35, "jam": true})
		"dark":
			_start_run()
			_station.call("debug_setup", {"pins": [0, 1], "corruption": 0.8, "dark": true})
		"finale":
			_start_run()
			_station.call("debug_setup", {"pins": [0, 1, 2, 3]})
		"ending":
			_on_finished("signal_lost", {
				"signals": 5, "pins": 5, "caches": 3, "battery": 41,
				"time": "07:18", "corruption": 88, "note": "The band is quiet."
			})
		"ending_dark":
			_on_finished("dark", {
				"signals": 2, "pins": 2, "caches": 1, "battery": 0,
				"time": "03:44", "corruption": 96, "note": "You should have conserved the cells."
			})
		_:
			_start_run()


func _process(delta: float) -> void:
	var target := {
		"glitch": 0.05, "corruption": 0.0,
		"tint": Color(1, 1, 1, 1), "brightness": 1.0
	}
	for n in [_title, _station, _ending]:
		if n != null and n.visible and n.has_method("fx_state"):
			target = n.call("fx_state")
			break

	_glitch = lerpf(_glitch, float(target.get("glitch", 0.05)), clampf(delta * 7.0, 0.0, 1.0))
	_corruption = lerpf(_corruption, float(target.get("corruption", 0.0)), clampf(delta * 2.5, 0.0, 1.0))
	_tint = _tint.lerp(target.get("tint", Color(1, 1, 1, 1)), clampf(delta * 3.0, 0.0, 1.0))
	_brightness = lerpf(_brightness, float(target.get("brightness", 1.0)), clampf(delta * 3.0, 0.0, 1.0))

	if _fx_mat != null:
		_fx_mat.set_shader_parameter("glitch", _glitch)
		_fx_mat.set_shader_parameter("corruption", _corruption)
		_fx_mat.set_shader_parameter("tint", _tint)
		_fx_mat.set_shader_parameter("brightness", _brightness)
		_fx_mat.set_shader_parameter("desat", 0.16 + _corruption * 0.25)
