extends Node
## Tiny pooled sound player for the game's UI and hit feedback.

const POOL_SIZE := 20

const STREAMS := {
	"hit": preload("res://assets/audio/hit.ogg"),
	"perfect": preload("res://assets/audio/perfect.ogg"),
	"mistap": preload("res://assets/audio/mistap.ogg"),
	"escape": preload("res://assets/audio/escape.ogg"),
	"click": preload("res://assets/audio/click.ogg"),
	"start": preload("res://assets/audio/start.ogg"),
	"victory": preload("res://assets/audio/victory.ogg"),
	"lose": preload("res://assets/audio/lose.ogg"),
}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var enabled := true


func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)


func play(key: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not enabled:
		return
	var stream: AudioStream = STREAMS.get(key)
	if stream == null:
		return
	var player := _pick_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _pick_player() -> AudioStreamPlayer:
	for i in POOL_SIZE:
		var idx := (_next + i) % POOL_SIZE
		if not _players[idx].playing:
			_next = (idx + 1) % POOL_SIZE
			return _players[idx]
	# Everything is busy: steal the oldest slot.
	var stolen := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	return stolen
