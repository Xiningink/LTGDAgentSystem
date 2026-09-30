extends RefCounted
class_name Sfx

## Tiny pooled sound-effect player. main.gd calls attach() once so screens can
## fire effects without owning audio nodes.

static var enabled := true
static var _root: Node = null
static var _players: Array = []
static var _next := 0


static func attach(root: Node) -> void:
	_root = root
	_players.clear()
	_next = 0
	# Headless/CI runs (including the screenshot helper) use a dummy audio driver,
	# which never mixes and therefore keeps playbacks alive until exit. Stay silent
	# there so a run always shuts down cleanly.
	enabled = not _uses_silent_driver()
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.volume_db = -7.0
		root.add_child(p)
		_players.append(p)


static func _uses_silent_driver() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	if AudioServer.has_method("get_driver_name"):
		var driver := String(AudioServer.call("get_driver_name")).to_lower()
		return driver.is_empty() or driver.contains("dummy") or driver.contains("headless")
	return AudioServer.get_output_latency() <= 0.0


static func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled or _players.is_empty():
		return
	var s := Assets.stream(sound)
	if s == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = s
	p.volume_db = -7.0 + volume_db
	p.pitch_scale = pitch
	p.play()


## Stops and releases every voice so shutting the game down mid-jingle does not
## leave audio playbacks hanging in the AudioServer.
static func shutdown() -> void:
	for p in _players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_players.clear()
	_root = null
	Assets.clear_stream_cache()
