extends Node

## Tiny pooled SFX player. Kenney CC0 audio.

const POOL_SIZE := 16

const STREAMS := {
	"click": preload("res://assets/audio/ui_click.ogg"),
	"tick": preload("res://assets/audio/ui_tick.ogg"),
	"select": preload("res://assets/audio/ui_select.ogg"),
	"start": preload("res://assets/audio/start.ogg"),
	"ready": preload("res://assets/audio/ready.ogg"),
	"hit_1": preload("res://assets/audio/hit_1.ogg"),
	"hit_2": preload("res://assets/audio/hit_2.ogg"),
	"hit_3": preload("res://assets/audio/hit_3.ogg"),
	"perfect": preload("res://assets/audio/perfect.ogg"),
	"mistap": preload("res://assets/audio/mistap.ogg"),
	"escape": preload("res://assets/audio/escape.ogg"),
	"glitch": preload("res://assets/audio/glitch.ogg"),
	"victory": preload("res://assets/audio/victory.ogg"),
}

var _players: Array[AudioStreamPlayer] = []
var _cursor := 0
var _enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enabled = not _is_capture_run()
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)


## Screenshot / trace harnesses pass `--out` or `--scenario` after `--`.
## Keeping audio silent there avoids playback resources leaking on quit.
func _is_capture_run() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	for a in OS.get_cmdline_user_args():
		if a == "--out" or a.begins_with("--out="):
			return true
		if a == "--mute" or a == "--silent":
			return true
	return false


func _exit_tree() -> void:
	# Stop everything so no audio resources are held during engine shutdown.
	for p in _players:
		p.stop()
		p.stream = null


func _play(stream_name: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if not _enabled:
		return
	if not STREAMS.has(stream_name):
		return
	var p := _next_player()
	p.stream = STREAMS[stream_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func _next_player() -> AudioStreamPlayer:
	for i in range(POOL_SIZE):
		var idx := (_cursor + i) % POOL_SIZE
		if not _players[idx].playing:
			_cursor = (idx + 1) % POOL_SIZE
			return _players[idx]
	_cursor = (_cursor + 1) % POOL_SIZE
	return _players[_cursor]


func play_click() -> void:
	_play("click", -10.0, randf_range(0.98, 1.04))


func play_tick() -> void:
	_play("tick", -9.0, 1.0)


func play_select() -> void:
	_play("select", -7.0, 1.0)


func play_start() -> void:
	_play("start", -4.0, 1.0)
	_play("ready", -8.0, 1.0)


func play_hit(accuracy: float) -> void:
	var idx := randi_range(1, 3)
	_play("hit_%d" % idx, -8.0 + accuracy * 3.0, randf_range(0.94, 1.12))
	if accuracy > 0.82:
		_play("perfect", -9.0, randf_range(0.98, 1.06))


func play_mistap() -> void:
	_play("mistap", -3.0, 1.0)
	_play("glitch", -10.0, 0.8)


func play_escape() -> void:
	_play("escape", -3.0, 0.9)


func play_victory() -> void:
	_play("victory", -3.0, 1.0)
