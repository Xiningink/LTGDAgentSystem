## Persistent progress: which chambers are open, personal bests, preferences.
extends Node

const PATH := "user://puzzle_magnet_lab.cfg"

var best_moves: Dictionary = {}     # level id -> int
var unlocked: int = 1               # number of chambers available
var sound_on: bool = true

var _config := ConfigFile.new()


func _ready() -> void:
	load_data()
	Sfx.set_sound_on(sound_on)


func load_data() -> void:
	if _config.load(PATH) != OK:
		return
	unlocked = int(_config.get_value("progress", "unlocked", 1))
	sound_on = bool(_config.get_value("settings", "sound", true))
	var raw: Dictionary = _config.get_value("progress", "best", {})
	for key in raw:
		best_moves[String(key)] = int(raw[key])


func save_data() -> void:
	_config.set_value("progress", "unlocked", unlocked)
	_config.set_value("progress", "best", best_moves)
	_config.set_value("settings", "sound", sound_on)
	_config.save(PATH)


func record_result(level_id: String, moves: int, level_index: int, total_levels: int) -> bool:
	var is_new_best := false
	if not best_moves.has(level_id) or moves < int(best_moves[level_id]):
		best_moves[level_id] = moves
		is_new_best = true
	var next_unlock := mini(level_index + 2, total_levels)
	if next_unlock > unlocked:
		unlocked = next_unlock
	save_data()
	return is_new_best


func is_unlocked(index: int) -> bool:
	return index < unlocked


func is_cleared(level_id: String) -> bool:
	return best_moves.has(level_id)


func reset_progress() -> void:
	best_moves.clear()
	unlocked = 1
	save_data()
