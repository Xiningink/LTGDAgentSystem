extends Node2D

## Ivory Beats - main controller and state machine.

enum State { TITLE, READY, PLAYING, RESULTS }

const BOARD_SCENE := preload("res://scenes/Board.tscn")
const TITLE_SCENE := preload("res://scenes/TitleScreen.tscn")
const HUD_SCENE := preload("res://scenes/Hud.tscn")
const RESULTS_SCENE := preload("res://scenes/ResultsPanel.tscn")
const BG_TEXTURE := preload("res://assets/textures/grid_thin.png")

const MODES := {
	"sprint": {
		"name": "SPRINT",
		"detail": "RACE THE CLOCK",
		"tagline": "Clear 40 tiles before the timer reaches zero.",
		"target": 40,
		"time_limit": 28.0,
		"base_speed": 250.0,
		"speed_step_hits": 4,
		"speed_step": 11.0,
		"max_speed": 720.0,
		"accent": 0,
	},
	"endless": {
		"name": "ENDLESS",
		"detail": "SURVIVE THE CASCADE",
		"tagline": "The scroll accelerates without mercy. How long can you last?",
		"target": 0,
		"time_limit": 0.0,
		"base_speed": 235.0,
		"speed_step_hits": 5,
		"speed_step": 20.0,
		"max_speed": 1000.0,
		"accent": 3,
	},
	"blitz": {
		"name": "BLITZ",
		"detail": "20 SECOND BURST",
		"tagline": "A tight countdown. Every tile counts. Maximize hits.",
		"target": 0,
		"time_limit": 20.0,
		"base_speed": 315.0,
		"speed_step_hits": 6,
		"speed_step": 15.0,
		"max_speed": 860.0,
		"accent": 1,
	},
}

var state: State = State.TITLE
var mode := "endless"

var score := 0
var score_display := 0.0
var hits := 0
var perfects := 0
var combo := 0
var best_combo := 0
var time_left := 0.0
var elapsed := 0.0
var difficulty := 0.0
var last_reason := ""

var board: Board
var title: TitleScreen
var hud: Hud
var results: ResultsPanel
var flash_rect: ColorRect

var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _last_second := -1
var _flash_color := Color.WHITE
var _flash_alpha := 0.0
var _shake_time := 0.0
var _shake_dur := 0.0
var _shake_mag := 0.0
var _shake := Vector2.ZERO
var _scenario := ""
var _scenario_seed := 20250930


func _ready() -> void:
	_rng.randomize()
	_build()
	_detect_scenario()
	_enter_title()
	if _scenario != "":
		_apply_scenario()


func _build() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	var bg := TextureRect.new()
	bg.texture = BG_TEXTURE
	bg_layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg.modulate = Color(1, 1, 1, 0.032)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	board = BOARD_SCENE.instantiate()
	add_child(board)
	board.tile_hit.connect(_on_tile_hit)
	board.tile_escaped.connect(_on_tile_escaped)
	board.tile_mistap.connect(_on_tile_mistap)

	var ui := CanvasLayer.new()
	ui.layer = 1
	add_child(ui)
	title = TITLE_SCENE.instantiate()
	ui.add_child(title)
	title.mode_selected.connect(_on_mode_selected)

	hud = HUD_SCENE.instantiate()
	ui.add_child(hud)

	results = RESULTS_SCENE.instantiate()
	ui.add_child(results)
	results.retry_requested.connect(_on_retry)
	results.menu_requested.connect(_on_menu)

	var fx := CanvasLayer.new()
	fx.layer = 2
	add_child(fx)
	flash_rect = ColorRect.new()
	fx.add_child(flash_rect)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta

	if state == State.PLAYING:
		elapsed += delta
		var cfg: Dictionary = MODES[mode]
		if float(cfg.time_limit) > 0.0:
			time_left -= delta
			if time_left <= 0.0:
				time_left = 0.0
				_end_run("TIME UP" if int(cfg.target) > 0 else "TIME")
			else:
				var sec := int(ceil(time_left))
				if sec != _last_second and sec <= 5 and sec > 0:
					_last_second = sec
					AudioManager.play_tick()
		_recompute_speed()

	score_display = lerpf(score_display, float(score), clampf(delta * 10.0, 0.0, 1.0))
	_update_flash(delta)
	_update_shake(delta)
	if state != State.TITLE:
		_refresh_hud()


func _refresh_hud() -> void:
	var cfg: Dictionary = MODES[mode]
	hud.refresh({
		"mode": mode,
		"cfg": cfg,
		"best": SaveManager.get_best(mode),
		"score": int(round(score_display)),
		"hits": hits,
		"perfects": perfects,
		"target": int(cfg.target),
		"time_left": time_left,
		"combo": combo,
		"speed": board.speed,
		"speed_mult": board.speed / maxf(float(cfg.base_speed), 1.0),
		"prompt": state == State.READY,
		"playing": state == State.PLAYING,
	})


func _enter_title() -> void:
	state = State.TITLE
	board.reset()
	board.visible = false
	title.setup(MODES, SaveManager.best)
	title.visible = true
	hud.visible = false
	hud.set_prompt(false)
	results.dismiss()


func _enter_ready() -> void:
	state = State.READY
	score = 0
	score_display = 0.0
	hits = 0
	perfects = 0
	combo = 0
	best_combo = 0
	time_left = float(MODES[mode].time_limit)
	elapsed = 0.0
	_last_second = -1
	board.reset()
	board.visible = true
	title.visible = false
	hud.visible = true
	hud.set_prompt(true)
	results.dismiss()
	_recompute_speed()


func _start_play() -> void:
	if state == State.PLAYING:
		return
	state = State.PLAYING
	var cfg: Dictionary = MODES[mode]
	score = 0
	score_display = 0.0
	hits = 0
	perfects = 0
	combo = 0
	best_combo = 0
	time_left = float(cfg.time_limit)
	elapsed = 0.0
	_last_second = -1
	var seed_value := -1
	if _scenario != "":
		seed_value = _scenario_seed
	board.start_run(cfg, seed_value)
	board.visible = true
	_recompute_speed()
	hud.set_prompt(false)
	results.dismiss()
	AudioManager.play_start()


func _recompute_speed() -> void:
	var cfg: Dictionary = MODES[mode]
	var step_hits := maxi(int(cfg.speed_step_hits), 1)
	var steps := hits / step_hits
	board.speed = minf(float(cfg.base_speed) + float(steps) * float(cfg.speed_step), float(cfg.max_speed))
	difficulty = clampf(
		(board.speed - float(cfg.base_speed)) / maxf(float(cfg.max_speed) - float(cfg.base_speed), 1.0),
		0.0, 1.0
	)
	# Window stays roughly constant in time, tightening slightly as speed climbs.
	var window_t := lerpf(0.34, 0.12, difficulty)
	board.hit_window = clampf(board.speed * window_t, 58.0, 150.0)


func _on_mode_selected(mode_key: String) -> void:
	mode = mode_key
	_enter_ready()


func _on_tile_hit(lane: int, accuracy: float, _offset: float) -> void:
	hits += 1
	combo += 1
	best_combo = maxi(best_combo, combo)
	var cfg: Dictionary = MODES[mode]
	var speed_mult := board.speed / maxf(float(cfg.base_speed), 1.0)
	var points := int(round((60.0 + 140.0 * accuracy) * speed_mult))
	score += points
	if accuracy > 0.82:
		perfects += 1
	AudioManager.play_hit(accuracy)
	if int(cfg.target) > 0 and hits >= int(cfg.target):
		_end_run("VICTORY")


func _on_tile_escaped(_lane: int) -> void:
	_end_run("ESCAPED")


func _on_tile_mistap(_pressed_lane: int, _target_lane: int) -> void:
	_end_run("MISTAP")


func _end_run(reason: String) -> void:
	if state == State.RESULTS:
		return
	state = State.RESULTS
	last_reason = reason
	board.stop_run()
	var cfg: Dictionary = MODES[mode]
	var victory := reason == "VICTORY"
	if victory:
		score += int(round(time_left * 25.0))
	var is_best := SaveManager.record_run(mode, score, hits, perfects, best_combo)
	results.present({
		"mode": mode,
		"mode_name": str(cfg.name),
		"accent": int(cfg.accent),
		"reason": reason,
		"victory": victory,
		"score": score,
		"best": SaveManager.get_best(mode),
		"is_best": is_best,
		"hits": hits,
		"perfects": perfects,
		"best_combo": best_combo,
		"time_left": time_left,
	})
	if victory:
		AudioManager.play_victory()
		_flash(Palette.NEON[2], 0.16)
	elif reason == "MISTAP":
		AudioManager.play_mistap()
		_shake_screen(18.0, 0.5)
		_flash(Palette.DANGER, 0.22)
	elif reason == "ESCAPED":
		AudioManager.play_escape()
		_shake_screen(14.0, 0.45)
		_flash(Palette.DANGER, 0.18)
	else:
		AudioManager.play_escape()
		_shake_screen(6.0, 0.28)


func _on_retry() -> void:
	if state == State.RESULTS:
		_start_play()


func _on_menu() -> void:
	_enter_title()


func _handle_lane(lane: int) -> void:
	match state:
		State.READY:
			_start_play()
		State.PLAYING:
			board.press_lane(lane)
		_:
			pass


func _key_to_lane(keycode: int) -> int:
	match keycode:
		KEY_A, KEY_1:
			return 0
		KEY_S, KEY_2:
			return 1
		KEY_D, KEY_3:
			return 2
		KEY_F, KEY_4:
			return 3
	return -1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		var keycode := key_event.keycode
		var lane := _key_to_lane(keycode)
		if lane >= 0:
			_handle_lane(lane)
			get_viewport().set_input_as_handled()
			return
		if keycode == KEY_ESCAPE or keycode == KEY_M:
			if state == State.RESULTS or state == State.READY or state == State.PLAYING:
				_on_menu()
			return
		if keycode == KEY_ENTER or keycode == KEY_KP_ENTER or keycode == KEY_SPACE:
			match state:
				State.TITLE:
					title.activate_selected()
				State.READY:
					_start_play()
				State.RESULTS:
					_on_retry()
			return
		if keycode == KEY_R and state == State.RESULTS:
			_on_retry()
			return
		if state == State.TITLE:
			if keycode == KEY_UP or keycode == KEY_LEFT:
				title.move_selection(-1)
			elif keycode == KEY_DOWN or keycode == KEY_RIGHT:
				title.move_selection(1)
	elif event is InputEventMouseButton:
		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return
		var pos: Vector2 = event.position
		if state == State.READY:
			_start_play()
		elif state == State.PLAYING:
			if pos.x >= Board.BOARD_LEFT and pos.x < Board.BOARD_RIGHT:
				var lane := int((pos.x - Board.BOARD_LEFT) / Board.LANE_W)
				_handle_lane(clampi(lane, 0, Board.LANES - 1))


func _flash(color: Color, strength: float) -> void:
	_flash_color = color
	_flash_alpha = maxf(_flash_alpha, strength)


func _update_flash(delta: float) -> void:
	_flash_alpha = maxf(0.0, _flash_alpha - delta * 1.5)
	flash_rect.color = Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash_alpha)


func _shake_screen(magnitude: float, duration: float) -> void:
	_shake_mag = magnitude
	_shake_dur = duration
	_shake_time = duration


func _update_shake(delta: float) -> void:
	if _shake_time > 0.0:
		_shake_time = maxf(0.0, _shake_time - delta)
		var falloff := _shake_time / maxf(_shake_dur, 0.001)
		var m := _shake_mag * falloff * falloff
		_shake = Vector2(_rng.randf_range(-m, m), _rng.randf_range(-m, m))
		board.position = _shake
	else:
		_shake = Vector2.ZERO
		board.position = Vector2.ZERO


# ------------------------------------------------------------------ scenarios

func _detect_scenario() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		if a == "--scenario" and i + 1 < args.size():
			_scenario = args[i + 1]
			i += 2
			continue
		elif a.begins_with("--scenario="):
			_scenario = a.substr("--scenario=".length())
		elif a == "--seed" and i + 1 < args.size():
			_scenario_seed = int(args[i + 1])
			i += 2
			continue
		elif a.begins_with("--seed="):
			_scenario_seed = int(a.substr("--seed=".length()))
		i += 1


func _apply_scenario() -> void:
	match _scenario:
		"title", "menu":
			pass
		"ready":
			_on_mode_selected("endless")
		"showcase":
			_showcase("endless", -30.0, 128)
		"showcase_sprint":
			_showcase("sprint", -30.0, 22)
		"showcase_blitz":
			_showcase("blitz", -55.0, 17)
		"endless":
			_scenario_play("endless", 0, 0)
		"sprint":
			_scenario_play("sprint", 0, 0)
		"blitz":
			_scenario_play("blitz", 0, 0)
		"near_victory":
			_scenario_play("sprint", 37, 11840)
		"results", "game_over":
			_scenario_results("endless", 24, 9420)
		_:
			pass


func _showcase(mode_key: String, active_offset: float, pre_hits: int) -> void:
	mode = mode_key
	_enter_ready()
	_start_play()
	hits = pre_hits
	score = pre_hits * 128 + 640
	score_display = float(score)
	perfects = int(pre_hits * 0.6)
	combo = 9
	best_combo = 12
	_recompute_speed()
	board.debug_pose(active_offset, _scenario_seed)
	board.speed = float(MODES[mode].max_speed) * 0.4 + float(MODES[mode].base_speed) * 0.6
	hud.set_prompt(false)
	_refresh_hud()


func _scenario_play(mode_key: String, pre_hits: int, pre_score: int) -> void:
	mode = mode_key
	_enter_ready()
	_start_play()
	if pre_hits > 0:
		hits = pre_hits
		score = pre_score
		score_display = float(score)
		perfects = int(pre_hits * 0.55)
		combo = 7
		best_combo = 11
		_recompute_speed()
	_refresh_hud()


func _scenario_results(mode_key: String, pre_hits: int, pre_score: int) -> void:
	mode = mode_key
	_enter_ready()
	_start_play()
	hits = pre_hits
	score = pre_score
	score_display = float(score)
	perfects = int(pre_hits * 0.5)
	best_combo = 14
	time_left = 0.0
	_recompute_speed()
	board.debug_pose(-30.0, _scenario_seed)
	hud.set_prompt(false)
	_end_run("MISTAP")
