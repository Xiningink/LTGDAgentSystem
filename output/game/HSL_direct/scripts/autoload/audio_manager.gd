extends Node
## Audio director: a small pool of one-shots plus smoothed continuous beds
## (radio static, carrier tone, room hum, dread drone, heartbeat).

const DIR := "res://assets/audio/"
const POOL_SIZE := 16
const SILENT := -60.0

var _static: AudioStreamPlayer
var _carrier: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _drone: AudioStreamPlayer
var _heart: AudioStreamPlayer
var _pool: Array = []
var _pool_index := 0
var _cache := {}

var _lvl := {"static": 0.0, "carrier": 0.0, "hum": 0.0, "drone": 0.0, "heart": 0.0}
var _tgt := {"static": 0.0, "carrier": 0.0, "hum": 0.0, "drone": 0.0, "heart": 0.0}
var _static_pitch := 1.0
var _master := 0.85
var _muted := false
var _live := true


func _detect_live() -> bool:
	var drv := ""
	if AudioServer.has_method("get_driver_name"):
		drv = AudioServer.get_driver_name()
	return drv != "Dummy" and drv != ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_live = _detect_live()
	if not _live:
		return
	_static = _bed("static_loop.wav")
	_carrier = _bed("carrier_loop.wav")
	_hum = _bed("hum_loop.wav")
	_drone = _bed("drone_loop.wav")
	_heart = _bed("heartbeat.wav")
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


func _bed(file: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(file, true)
	p.volume_db = SILENT
	add_child(p)
	p.play()
	return p


func _stream(file: String, do_loop: bool) -> AudioStream:
	var key := file + ("|loop" if do_loop else "")
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = load(DIR + file)
	if s is AudioStreamWAV and do_loop:
		var w: AudioStreamWAV = s
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		var bytes_per_frame := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
		if w.stereo:
			bytes_per_frame *= 2
		w.loop_end = int(w.data.size() / bytes_per_frame)
	elif s is AudioStreamOggVorbis and do_loop:
		var o: AudioStreamOggVorbis = s
		o.loop = true
	_cache[key] = s
	return s


func _process(delta: float) -> void:
	if not _live:
		return
	var k := clampf(delta * 6.0, 0.0, 1.0)
	for name in _lvl.keys():
		_lvl[name] = lerpf(_lvl[name], _tgt[name], k)
	_static.volume_db = _db(_lvl["static"])
	_carrier.volume_db = _db(_lvl["carrier"])
	_hum.volume_db = _db(_lvl["hum"])
	_drone.volume_db = _db(_lvl["drone"])
	_heart.volume_db = _db(_lvl["heart"])
	_static.pitch_scale = lerpf(_static.pitch_scale, _static_pitch, k)


func _db(linear: float) -> float:
	if not _live or _muted or linear <= 0.001:
		return SILENT
	return linear_to_db(clampf(linear * _master, 0.001, 1.0))


func set_static(value: float, pitch: float = 1.0) -> void:
	_tgt["static"] = clampf(value, 0.0, 1.0)
	_static_pitch = clampf(pitch, 0.5, 2.0)


func set_carrier(value: float) -> void:
	_tgt["carrier"] = clampf(value, 0.0, 1.0)


func set_hum(value: float) -> void:
	_tgt["hum"] = clampf(value, 0.0, 1.0)


func set_drone(value: float) -> void:
	_tgt["drone"] = clampf(value, 0.0, 1.0)


func set_heart(value: float) -> void:
	_tgt["heart"] = clampf(value, 0.0, 1.0)


func set_master(value: float) -> void:
	_master = clampf(value, 0.0, 1.0)


func toggle_mute() -> bool:
	_muted = not _muted
	return _muted


func is_muted() -> bool:
	return _muted


func stop_all() -> void:
	_tgt["static"] = 0.0
	_tgt["carrier"] = 0.0
	_tgt["hum"] = 0.0
	_tgt["drone"] = 0.0
	_tgt["heart"] = 0.0
	for name in _lvl.keys():
		_lvl[name] = 0.0


func _exit_tree() -> void:
	if not _live:
		return
	# Release looping playbacks so the engine shuts down without leaking them.
	for p in [_static, _carrier, _hum, _drone, _heart]:
		if p != null and is_instance_valid(p):
			p.stop()
			p.stream = null
	for p in _pool:
		if p != null and is_instance_valid(p):
			p.stop()
			p.stream = null
	_cache.clear()


func play(file: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _live:
		return
	if not _cache.has(file):
		_cache[file] = load(DIR + file)
	var p: AudioStreamPlayer = _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE
	p.stream = _cache[file]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func play_any(files: Array, volume_db: float = 0.0, pitch_range: Vector2 = Vector2.ONE) -> void:
	if files.is_empty():
		return
	var f: String = files[randi() % files.size()]
	play(f, volume_db, randf_range(pitch_range.x, pitch_range.y))
