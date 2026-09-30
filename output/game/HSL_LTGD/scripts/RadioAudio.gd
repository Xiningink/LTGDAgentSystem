extends Node
# Radio sound bed. Four pre-rendered loops (hiss, carrier tone, low drone,
# jam growl) are cross-faded in real time so the mix reacts to the dial.
# Falls back to silent mode on the dummy audio driver (headless / captures).

const AudioSupport := preload("res://scripts/AudioSupport.gd")

const LOOPS := {
	"hiss": "res://assets/sfx/static.wav",
	"tone": "res://assets/sfx/tone.wav",
	"drone": "res://assets/sfx/drone_loop.wav",
	"jam": "res://assets/sfx/jam.wav"
}

# targets driven by the station screen
var static_target := 0.10
var tone_target := 0.0
var drone_target := 0.10
var jam_target := 0.0
var tone_pitch := 1.0

var _static := 0.0
var _tone := 0.0
var _drone := 0.0
var _jam := 0.0
var _pitch := 1.0

var _enabled := true
var _players := {}


func _ready() -> void:
	_enabled = not AudioSupport.is_silent()
	if not _enabled:
		return
	for key in LOOPS.keys():
		var p := AudioStreamPlayer.new()
		p.name = "Loop_" + str(key)
		p.stream = _load_loop(str(LOOPS[key]))
		p.volume_db = -80.0
		add_child(p)
		_players[key] = p


func _load_loop(path: String) -> AudioStream:
	var res: AudioStream = load(path)
	if res is AudioStreamWAV:
		var w := res as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.data.size() / 2)
	return res


func _process(delta: float) -> void:
	var k := clampf(delta * 5.0, 0.0, 1.0)
	_static = lerpf(_static, static_target, k)
	_tone = lerpf(_tone, tone_target, k)
	_drone = lerpf(_drone, drone_target, k)
	_jam = lerpf(_jam, jam_target, clampf(delta * 3.0, 0.0, 1.0))
	_pitch = lerpf(_pitch, tone_pitch, clampf(delta * 4.0, 0.0, 1.0))

	if not _enabled or _players.is_empty():
		return
	_apply("hiss", _static)
	_apply("tone", _tone, _pitch)
	_apply("drone", _drone)
	_apply("jam", _jam)


func _apply(key: String, level: float, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _players.get(key)
	if p == null:
		return
	if level <= 0.003:
		if p.playing:
			p.stop()
		return
	if not p.playing:
		p.play()
	p.volume_db = -6.0 + linear_to_db(clampf(level, 0.0001, 1.0))
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
