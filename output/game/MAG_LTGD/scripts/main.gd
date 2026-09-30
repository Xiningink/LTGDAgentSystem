extends Control
class_name Main

## Application shell: owns progress, screen routing, audio and test scenarios.

const Ui := preload("res://scripts/ui_kit.gd")
const SfxLib := preload("res://scripts/sfx.gd")
const LevelsDataScript := preload("res://scripts/levels.gd")
const TitleScreenScript := preload("res://scripts/title_screen.gd")
const LevelSelectScript := preload("res://scripts/level_select.gd")
const GameScreenScript := preload("res://scripts/game_screen.gd")

const SAVE_PATH := "user://puzzle_magnet_lab.cfg"

var unlocked := 1
var best: Array = []
var scenario := ""
var moves_hint := -1

var _screen: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Ui.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SfxLib.attach(self)
	for i in LevelsDataScript.count():
		best.append(-1)
	_load_progress()
	_parse_args()
	_route()


# ------------------------------------------------------------------- progress --

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		SfxLib.shutdown()


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	unlocked = clampi(int(cfg.get_value("progress", "unlocked", 1)), 1, LevelsDataScript.count())
	var raw: Variant = cfg.get_value("progress", "best", [])
	if raw is Array:
		var stored: Array = raw
		for i in mini(stored.size(), best.size()):
			best[i] = int(stored[i])


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "best", best)
	cfg.save(SAVE_PATH)


func stars_for(index: int) -> int:
	if index >= best.size() or best[index] < 0:
		return 0
	var par: int = LevelsDataScript.get_level(index).solution.size()
	if best[index] <= par:
		return 3
	if best[index] <= int(ceil(float(par) * 1.4)):
		return 2
	return 1


func resume_index() -> int:
	for i in LevelsDataScript.count():
		if best[i] < 0:
			return i
	return LevelsDataScript.count() - 1


# ------------------------------------------------------------------- screens --

func _swap(screen: Control) -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.visible = false
		_screen.queue_free()
	_screen = screen
	add_child(screen)


func _show_title() -> void:
	var t = TitleScreenScript.new()
	t.unlocked = unlocked
	t.best = best.duplicate()
	t.resume_index = resume_index()
	t.begin_requested.connect(func() -> void: _open_game(resume_index()))
	t.levels_requested.connect(_show_levels)
	_swap(t)


func _show_levels() -> void:
	var s = LevelSelectScript.new()
	s.setup(unlocked, best)
	s.level_chosen.connect(func(index: int) -> void: _open_game(index))
	s.back_requested.connect(_show_title)
	_swap(s)


func _open_game(index: int, solution_moves: int = -1, instant: bool = false, fail: bool = false) -> void:
	index = clampi(index, 0, LevelsDataScript.count() - 1)
	var gs = GameScreenScript.new()
	gs.instant = instant
	gs.best_moves = best[index] if index < best.size() else -1
	gs.solved.connect(_on_solved)
	gs.levels_requested.connect(_show_levels)
	gs.next_requested.connect(func(i: int) -> void: _open_game(mini(i + 1, LevelsDataScript.count() - 1)))
	gs.retry_requested.connect(func(i: int) -> void: _open_game(i))
	_swap(gs)
	gs.load_level(index)
	if solution_moves >= 0:
		gs.play_solution(solution_moves)
	if fail:
		gs.force_fail()


func _on_solved(index: int, moves: int) -> void:
	if index < best.size() and (best[index] < 0 or moves < best[index]):
		best[index] = moves
	unlocked = clampi(maxi(unlocked, index + 2), 1, LevelsDataScript.count())
	_save_progress()


# ------------------------------------------------------------------ scenarios --

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a.begins_with("--scenario="):
			scenario = a.substr("--scenario=".length())
		elif a == "--scenario" and i + 1 < args.size():
			scenario = args[i + 1]
			i += 1
		elif a.begins_with("--level="):
			scenario = "level_" + a.substr("--level=".length())
		elif a == "--level" and i + 1 < args.size():
			scenario = "level_" + args[i + 1]
			i += 1
		elif a.begins_with("--moves="):
			moves_hint = int(a.substr("--moves=".length()))
		elif a == "--moves" and i + 1 < args.size():
			moves_hint = int(args[i + 1])
			i += 1
		elif not a.begins_with("--"):
			scenario = a
		i += 1


func _route() -> void:
	var s := scenario.strip_edges().to_lower()
	if s.is_empty():
		_show_title()
		return
	if s == "title" or s == "menu" or s == "splash":
		_show_title()
		return
	if s == "levels" or s == "select" or s == "chambers" or s == "level_select":
		_show_levels()
		return
	if s == "near_victory" or s == "nearvictory":
		var last := LevelsDataScript.count() - 1
		var total: int = LevelsDataScript.get_level(last).solution.size()
		_open_game(last, maxi(total - 2, 0))
		return
	if s == "complete" or s == "victory" or s == "win" or s == "cleared":
		_open_game(0, 999, true)
		return
	if s == "final" or s == "allclear" or s == "all_clear":
		var last_index := LevelsDataScript.count() - 1
		_open_game(last_index, 999, true)
		return
	if s == "fail" or s == "defeat" or s == "death":
		_open_game(4, 6, true, true)
		return
	# level_N or a chamber slug / partial name
	for i in LevelsDataScript.count():
		var data: Dictionary = LevelsDataScript.get_level(i)
		var slug := LevelsDataScript.slug(i)
		if s == slug or s == "level_%d" % (i + 1) or s == "level_%02d" % (i + 1) or s == "level%d" % (i + 1):
			_open_game(i, moves_hint)
			return
		if s.begins_with("level_") and int(s.substr(6)) == i + 1:
			_open_game(i, moves_hint)
			return
		if s.length() >= 4 and (slug.begins_with(s) or String(data.name).to_lower().begins_with(s)):
			_open_game(i, moves_hint)
			return
	_show_title()
