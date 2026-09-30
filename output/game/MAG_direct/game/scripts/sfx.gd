## Tiny pool-based sound bank. Everything is loaded once and played through a
## rotating set of players so overlapping cues never cut each other off.
extends Node

const SFX_DIR := "res://assets/sfx/"

const SOUNDS := {
	"ui_move": "ui_click.ogg",
	"ui_click": "ui_click.ogg",
	"ui_click_alt": "ui_click_alt.ogg",
	"ui_back": "ui_back.ogg",
	"ui_confirm": "ui_confirm.ogg",
	"ui_deny": "ui_deny.ogg",
	"step": "switch_pad.ogg",
	"crate": "crate_push.ogg",
	"repel": "magnet_repel.ogg",
	"attract": "magnet_attract.ogg",
	"flip": "polarity_flip.ogg",
	"burn": "hazard_burn.ogg",
	"gate_open": "gate_open.ogg",
	"gate_close": "gate_close.ogg",
	"plate": "plate_on.ogg",
	"plate_off": "plate_off.ogg",
	"win": "jingle_win.ogg",
	"unlock": "jingle_unlock.ogg",
	"fanfare": "win_fanfare.ogg",
	"hum": "ambient_hum.ogg",
	"exit_hum": "exit_hum.ogg",
}

const POOL_SIZE := 12

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _music: AudioStreamPlayer
var _music_track: String = ""
var _fade_tween: Tween

var sound_on: bool = true
var silent_system: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	silent_system = _detect_silent_system()
	if silent_system:
		sound_on = false
	for key in SOUNDS:
		var path: String = SFX_DIR + String(SOUNDS[key])
		if ResourceLoader.exists(path):
			_streams[key] = load(path)
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	add_child(_music)


func _exit_tree() -> void:
	# Release audio before teardown so the engine shuts down silently.
	for player in _players:
		player.stop()
		player.stream = null
	if _music != null:
		_music.stop()
		_music.stream = null
	_streams.clear()


func play(key: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if not sound_on:
		return
	if not _streams.has(key):
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[key]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func play_varied(key: String, volume_db: float = -6.0, spread: float = 0.08) -> void:
	play(key, volume_db, 1.0 + randf_range(-spread, spread))


## Looping ambience (menu hum / chamber air). Keyed so we never restart it.
func music(key: String, volume_db: float = -22.0) -> void:
	if key == _music_track:
		return
	_music_track = key
	if not _streams.has(key):
		_music.stop()
		return
	var stream: AudioStream = _streams[key]
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_music.stream = stream
	_music.volume_db = volume_db
	if sound_on:
		_music.play()


func stop_music() -> void:
	_music_track = ""
	_music.stop()


func set_sound_on(value: bool) -> void:
	sound_on = value and not silent_system
	if not sound_on:
		_music.stop()
	elif _music_track != "":
		var track := _music_track
		_music_track = ""
		music(track)


## Headless runs and automated captures use the dummy audio driver; playing
## anything there just leaves dangling stream playbacks at shutdown.
func _detect_silent_system() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	if String(AudioServer.get_driver_name()).to_lower() == "dummy":
		return true
	return false
