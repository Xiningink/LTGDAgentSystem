extends Node

## Persists personal bests and lifetime stats to user://.

const SAVE_PATH := "user://ivory_beats.save.json"
const MODES := ["sprint", "endless", "blitz"]

var best: Dictionary = {"sprint": 0, "endless": 0, "blitz": 0}
var plays: int = 0
var total_hits: int = 0
var total_perfects: int = 0
var best_combo: int = 0


func _ready() -> void:
	load_data()


func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var b: Variant = data.get("best", {})
	if typeof(b) == TYPE_DICTIONARY:
		for key in MODES:
			best[key] = int(b.get(key, 0))
	plays = int(data.get("plays", 0))
	total_hits = int(data.get("total_hits", 0))
	total_perfects = int(data.get("total_perfects", 0))
	best_combo = int(data.get("best_combo", 0))


func save_data() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"best": best,
		"plays": plays,
		"total_hits": total_hits,
		"total_perfects": total_perfects,
		"best_combo": best_combo,
	}, "\t"))
	f.close()


func get_best(mode_key: String) -> int:
	return int(best.get(mode_key, 0))


## Records the end of a run. Returns true when a new personal best was set.
func record_run(mode_key: String, run_score: int, run_hits: int, run_perfects: int, run_combo: int) -> bool:
	plays += 1
	total_hits += run_hits
	total_perfects += run_perfects
	best_combo = maxi(best_combo, run_combo)
	var is_best := run_score > int(best.get(mode_key, 0))
	if is_best:
		best[mode_key] = run_score
	save_data()
	return is_best
