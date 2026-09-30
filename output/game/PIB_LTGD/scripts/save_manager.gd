extends Node
## Persists personal-best scores between runs.

const SAVE_PATH := "user://ivory_beats.save"

const MODES := ["endless", "sprint", "blitz"]

var best: Dictionary = {
	"endless": 0,
	"sprint": 0,
	"blitz": 0,
}
var total_runs := 0
var total_hits := 0


func _ready() -> void:
	load_data()


func load_data() -> void:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err != OK:
		return
	for mode in best.keys():
		best[mode] = int(config.get_value("best", mode, 0))
	total_runs = int(config.get_value("stats", "runs", 0))
	total_hits = int(config.get_value("stats", "hits", 0))


func save_data() -> void:
	var config := ConfigFile.new()
	for mode in best.keys():
		config.set_value("best", mode, int(best[mode]))
	config.set_value("stats", "runs", total_runs)
	config.set_value("stats", "hits", total_hits)
	config.save(SAVE_PATH)


func get_best(mode: String) -> int:
	return int(best.get(mode, 0))


## Records a finished run and returns true when it set a new personal best.
func record_run(mode: String, score: int, hits: int = 0, perfects: int = 0, seconds: int = 0) -> bool:
	total_runs += 1
	total_hits += hits
	var is_best := score > get_best(mode)
	if is_best:
		best[mode] = score
	save_data()
	return is_best


func reset_all() -> void:
	for mode in best.keys():
		best[mode] = 0
	total_runs = 0
	total_hits = 0
	save_data()
