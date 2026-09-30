extends Node2D
## Ivory Beats - game flow, scoring and mode rules.

const STATE_TITLE := 0
const STATE_READY := 1
const STATE_PLAYING := 2
const STATE_GAMEOVER := 3

const MODES := {
	"endless": {
		"name": "ENDLESS",
		"tagline": "SURVIVE THE ACCELERATION",
		"base_speed": 250.0,
		"speed_step": 7.0,
		"max_speed": 1000.0,
		"target": 0,
		"time": 0.0,
	},
	"sprint": {
		"name": "SPRINT",
		"tagline": "CLEAR 40 TILES",
		"base_speed": 300.0,
		"speed_step": 9.0,
		"max_speed": 1000.0,
		"target": 40,
		"time": 45.0,
	},
	"blitz": {
		"name": "BLITZ",
		"tagline": "30 SECOND FRENZY",
		"base_speed": 330.0,
		"speed_step": 6.0,
		"max_speed": 1000.0,
		"target": 0,
		"time": 30.0,
	},
}

@onready var board: IvoryBoard = $Board
@onready var ui: IvoryUI = $UI

var state := STATE_TITLE
var mode := "endless"
var hits := 0
var perfects := 0
var score := 0
var combo := 0
var time_left := 0.0
var elapsed := 0.0
var last_reason := ""
var best_at_start := 0

var _new_record := false
var _scenario := ""
var _save_enabled := true


func _ready() -> void:
	_save_enabled = DisplayServer.get_name() != "headless"
	board.hit.connect(_on_board_hit)
	board.fault.connect(_on_board_fault)
	ui.mode_selected.connect(_on_mode_selected)
	ui.retry_pressed.connect(_on_retry)
	ui.menu_pressed.connect(_on_menu)
	board.reset()
	_recompute_speed()
	state = STATE_TITLE
	ui.show_title(SaveManager.best)
	_apply_scenario()


func _process(delta: float) -> void:
	if state != STATE_PLAYING:
		return
	elapsed += delta
	if time_left > 0.0:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			end_run("TIME")
			return
	_recompute_speed()
	ui.update_hud(mode, MODES[mode], score, hits, time_left, elapsed, SaveManager.get_best(mode))


# --------------------------------------------------------------------------
# Flow
# --------------------------------------------------------------------------

func _on_mode_selected(selected: String) -> void:
	if not MODES.has(selected):
		return
	mode = selected
	_reset_run()
	board.reset()
	_recompute_speed()
	board.running = false
	state = STATE_READY
	Sfx.play("click")
	ui.show_ready(mode, MODES[mode], SaveManager.best)


func _start_play() -> void:
	if board.get_active_tile() == null:
		board.reset()
	_reset_run()
	_recompute_speed()
	board.running = true
	state = STATE_PLAYING
	Sfx.play("start")
	ui.show_playing(mode, MODES[mode], SaveManager.best)


func _on_retry() -> void:
	board.reset()
	_reset_run()
	_recompute_speed()
	board.running = true
	state = STATE_PLAYING
	Sfx.play("start")
	ui.show_playing(mode, MODES[mode], SaveManager.best)


func _on_menu() -> void:
	board.running = false
	board.reset()
	state = STATE_TITLE
	Sfx.play("click")
	ui.show_title(SaveManager.best)


func _reset_run() -> void:
	hits = 0
	perfects = 0
	score = 0
	combo = 0
	elapsed = 0.0
	time_left = float(MODES[mode].get("time", 0.0))
	last_reason = ""
	_new_record = false


func _recompute_speed() -> void:
	var cfg: Dictionary = MODES[mode]
	var target_speed: float = float(cfg.base_speed) + hits * float(cfg.speed_step)
	board.speed = minf(target_speed, float(cfg.max_speed))


func _handle_lane(lane: int) -> void:
	if state == STATE_READY:
		_start_play()
	elif state == STATE_PLAYING:
		board.press_lane(lane)


func end_run(reason: String) -> void:
	if state == STATE_GAMEOVER:
		return
	state = STATE_GAMEOVER
	board.running = false
	last_reason = reason
	best_at_start = SaveManager.get_best(mode)

	match reason:
		"VICTORY":
			Sfx.play("victory")
		"MISTAP":
			Sfx.play("mistap")
		"ESCAPED":
			Sfx.play("escape")
		_:
			Sfx.play("lose")

	if _save_enabled and _scenario.is_empty():
		_new_record = SaveManager.record_run(mode, score, hits, perfects, int(elapsed))
	else:
		_new_record = score > best_at_start

	ui.show_results({
		"mode": mode,
		"mode_name": MODES[mode].name,
		"reason": reason,
		"score": score,
		"best": maxi(best_at_start, score),
		"new_record": _new_record,
		"hits": hits,
		"perfects": perfects,
		"time": elapsed,
		"speed": board.speed,
	})


# --------------------------------------------------------------------------
# Board callbacks
# --------------------------------------------------------------------------

func _on_board_hit(lane: int, perfect: bool, tile_y: float) -> void:
	if state != STATE_PLAYING:
		return
	hits += 1
	if perfect:
		perfects += 1
	combo += 1
	var points := 100 + int(board.speed * 0.12) + (160 if perfect else 45) + mini(combo, 60) * 4
	score += points
	Sfx.play("perfect" if perfect else "hit", 0.0 if perfect else -5.0, randf_range(0.95, 1.06))
	ui.screen_flash(board.COL_PERFECT if perfect else board.COL_HIT, 0.10 if perfect else 0.05)
	board.spawn_popup(lane, tile_y, "+%d" % points, board.COL_PERFECT if perfect else board.COL_HIT)
	var target := int(MODES[mode].get("target", 0))
	if target > 0 and hits >= target:
		end_run("VICTORY")


func _on_board_fault(reason: String) -> void:
	if state != STATE_PLAYING:
		return
	ui.screen_flash(Color("ff3557"), 0.35)
	end_run(reason)


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(event.position)


func _on_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_A, KEY_LEFT:
			_handle_lane(0)
		KEY_S, KEY_UP:
			_handle_lane(1)
		KEY_D, KEY_DOWN:
			_handle_lane(2)
		KEY_F, KEY_RIGHT:
			_handle_lane(3)
		KEY_R:
			if state == STATE_GAMEOVER:
				_on_retry()
		KEY_ESCAPE:
			if state != STATE_TITLE:
				_on_menu()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if state == STATE_GAMEOVER:
				_on_retry()
		KEY_1:
			if state == STATE_TITLE:
				_on_mode_selected("endless")
		KEY_2:
			if state == STATE_TITLE:
				_on_mode_selected("sprint")
		KEY_3:
			if state == STATE_TITLE:
				_on_mode_selected("blitz")


func _on_click(position: Vector2) -> void:
	if state == STATE_READY:
		_handle_lane(_lane_at(position))
	elif state == STATE_PLAYING:
		var lane := _lane_at(position)
		if lane >= 0:
			board.press_lane(lane)


func _lane_at(position: Vector2) -> int:
	var local := position - board.position
	if local.x < 0.0 or local.x >= board.get_board_width():
		return -1
	return int(local.x / board.lane_width)


# --------------------------------------------------------------------------
# Scenario hooks (used by the screenshot helper)
# --------------------------------------------------------------------------

func _apply_scenario() -> void:
	_scenario = _read_user_arg("--scenario", "")
	match _scenario:
		"", "title":
			pass
		"ready", "ready_endless":
			_on_mode_selected("endless")
		"ready_sprint":
			_on_mode_selected("sprint")
		"ready_blitz":
			_on_mode_selected("blitz")
		"playing", "playing_endless":
			_scenario_playing("endless")
		"playing_sprint":
			_scenario_playing("sprint")
		"playing_blitz":
			_scenario_playing("blitz")
		"results_mistap":
			_scenario_results("endless", "MISTAP", 18250, 61, 40)
		"results_escape":
			_scenario_results("blitz", "ESCAPED", 9420, 33, 12)
		"results_victory":
			_scenario_results("sprint", "VICTORY", 26500, 40, 35)
		"results_time":
			_scenario_results("blitz", "TIME", 12040, 48, 20)


func _read_user_arg(flag: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == flag:
			return args[i + 1]
	return fallback


func _scenario_playing(selected: String) -> void:
	_on_mode_selected(selected)
	_start_play()
	for i in 80:
		board._process(1.0 / 60.0)
	_recompute_speed()
	# Freeze the board so the snapshot stays stable no matter how many frames pass.
	board.running = false
	ui.update_hud(mode, MODES[mode], score, hits, time_left, elapsed, SaveManager.get_best(mode))


func _scenario_results(selected: String, reason: String, run_score: int, run_hits: int, run_perfects: int) -> void:
	_on_mode_selected(selected)
	_start_play()
	hits = run_hits
	perfects = run_perfects
	score = run_score
	elapsed = 12.4
	ui.update_hud(mode, MODES[mode], score, hits, time_left, elapsed, SaveManager.get_best(mode))
	end_run(reason)
