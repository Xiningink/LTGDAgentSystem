extends Node
# Small pooled one-shot sound player. All clips come from the Kenney CC0
# interface / sci-fi / digital / impact packs.

const AudioSupport := preload("res://scripts/AudioSupport.gd")

const FILES := {
	"click": "res://assets/sfx/click_a.ogg",
	"click2": "res://assets/sfx/click_b.ogg",
	"select": "res://assets/sfx/select.ogg",
	"toggle": "res://assets/sfx/toggle.ogg",
	"switch": "res://assets/sfx/switch.ogg",
	"error": "res://assets/sfx/error.ogg",
	"confirm": "res://assets/sfx/confirm.ogg",
	"glitch": "res://assets/sfx/glitch_a.ogg",
	"glitch2": "res://assets/sfx/glitch_b.ogg",
	"scratch": "res://assets/sfx/scratch.ogg",
	"bong": "res://assets/sfx/bong.ogg",
	"drop": "res://assets/sfx/drop.ogg",
	"phaser_up": "res://assets/sfx/phaser_up.ogg",
	"phaser_down": "res://assets/sfx/phaser_down.ogg",
	"low_random": "res://assets/sfx/low_random.ogg",
	"zap": "res://assets/sfx/zap.ogg",
	"trash": "res://assets/sfx/space_trash.ogg",
	"tone": "res://assets/sfx/tone.ogg",
	"drone": "res://assets/sfx/drone.ogg",
	"computer": "res://assets/sfx/computer.ogg",
	"forcefield": "res://assets/sfx/forcefield.ogg",
	"metal": "res://assets/sfx/impact_metal.ogg",
	"boom": "res://assets/sfx/low_boom.ogg",
	"door": "res://assets/sfx/door_close.ogg",
	"step_a": "res://assets/sfx/step_a.ogg",
	"step_b": "res://assets/sfx/step_b.ogg",
	"step_c": "res://assets/sfx/step_c.ogg",
	"bell": "res://assets/sfx/bell.ogg"
}

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _enabled := true


func _ready() -> void:
	_enabled = not AudioSupport.is_silent()
	if not _enabled:
		return
	for key in FILES.keys():
		var s: Resource = load(FILES[key])
		if s != null:
			_streams[key] = s
	for i in range(20):
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		add_child(p)
		_players.append(p)


func play(id: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if not _enabled:
		return
	if not _streams.has(id) or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[id]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func play_rand(id: String, volume_db: float = -6.0, spread: float = 0.12) -> void:
	play(id, volume_db, 1.0 + randf_range(-spread, spread))
