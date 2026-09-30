extends Node2D
class_name Board

## Four-lane vertical playfield. Tiles scroll down toward the strike line.
## The lowest living tile is the active target. Pressing its lane inside the
## strike window shatters it; anything else is a fault.

signal tile_hit(lane: int, accuracy: float, offset: float)
signal tile_escaped(lane: int)
signal tile_mistap(pressed_lane: int, target_lane: int)
signal focus_changed(lane: int, hittable: bool)

const LANES := 4
const BOARD_W := 560.0
const LANE_W := BOARD_W / float(LANES)
const BOARD_LEFT := (1280.0 - BOARD_W) * 0.5
const BOARD_RIGHT := BOARD_LEFT + BOARD_W
const TILE_SIZE := 116.0
const STRIKE_Y := 552.0
const SPAWN_Y := -180.0
const SPACING := 176.0
const GRID_STEP := 58.0

const TILE_ACTIVE := 0
const TILE_DEAD := 1
const TILE_FAULT := 2


class Tile:
	var lane: int
	var y: float
	var state: int

	func _init(p_lane: int, p_y: float, p_state: int) -> void:
		lane = p_lane
		y = p_y
		state = p_state


class Shard:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var max_life: float
	var size: float
	var rot: float
	var rot_spd: float
	var color: Color

	func _init(p_pos: Vector2, p_vel: Vector2, p_life: float, p_size: float, p_rot: float, p_rot_spd: float, p_color: Color) -> void:
		pos = p_pos
		vel = p_vel
		life = p_life
		max_life = p_life
		size = p_size
		rot = p_rot
		rot_spd = p_rot_spd
		color = p_color


var running := false
var speed := 240.0
var base_speed := 240.0
var hit_window := 88.0
var time := 0.0

var tiles: Array[Tile] = []
var shards: Array[Shard] = []
var lane_flash: Array[float] = [0.0, 0.0, 0.0, 0.0]
var lane_flash_color: Array[Color] = [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]
var strike_flash := 0.0
var fault_lane := -1
var fault_time := 0.0
var scroll := 0.0

var _rng := RandomNumberGenerator.new()
var _active_lane := -1
var _was_hittable := false


func _ready() -> void:
	_rng.randomize()
	set_process(true)


func set_seed(value: int) -> void:
	_rng.seed = value


func reset() -> void:
	tiles.clear()
	shards.clear()
	for i in range(LANES):
		lane_flash[i] = 0.0
	strike_flash = 0.0
	fault_lane = -1
	fault_time = 0.0
	scroll = 0.0
	running = false
	_active_lane = -1
	_was_hittable = false
	queue_redraw()


func start_run(cfg: Dictionary, seed_value: int = -1) -> void:
	reset()
	if seed_value >= 0:
		_rng.seed = seed_value
	base_speed = float(cfg.get("base_speed", 240.0))
	speed = base_speed
	running = true
	var first_y := STRIKE_Y - 2.0 * SPACING
	tiles.append(_make_tile(_rng.randi_range(0, LANES - 1), first_y))
	_fill_queue()


func stop_run() -> void:
	running = false


func get_active_tile() -> Tile:
	var best: Tile = null
	for t in tiles:
		if t.state == TILE_ACTIVE:
			if best == null or t.y > best.y:
				best = t
	return best


func lane_center_x(lane: int) -> float:
	return BOARD_LEFT + lane * LANE_W + LANE_W * 0.5


## Handles a lane input. Returns true when the press was accepted as a strike.
func press_lane(lane: int) -> bool:
	if not running:
		return false
	var target := get_active_tile()
	if target == null:
		return false
	var dist := absf(target.y - STRIKE_Y)
	if target.lane == lane and dist <= hit_window:
		var acc := clampf(1.0 - dist / maxf(hit_window, 1.0), 0.0, 1.0)
		target.state = TILE_DEAD
		strike_flash = 1.0
		lane_flash[lane] = 1.0
		lane_flash_color[lane] = Palette.NEON[lane]
		_burst(Vector2(lane_center_x(lane), target.y), Palette.NEON[lane], 26, 0.0)
		emit_signal("tile_hit", lane, acc, target.y - STRIKE_Y)
		return true
	_fault(target, lane)
	return false


func _make_tile(lane: int, y: float) -> Tile:
	return Tile.new(lane, y, TILE_ACTIVE)


func _fill_queue() -> void:
	var top := _topmost_y()
	var guard := 0
	# Keep a steady pipeline: always top up to at least six queued tiles.
	while (top > SPAWN_Y or tiles.size() < 6) and guard < 64:
		top -= SPACING
		tiles.append(_make_tile(_rng.randi_range(0, LANES - 1), top))
		guard += 1


func _topmost_y() -> float:
	var top := SPAWN_Y
	var found := false
	for t in tiles:
		if t.state == TILE_ACTIVE:
			if not found or t.y < top:
				top = t.y
				found = true
	return top


func _fault(target: Tile, pressed_lane: int) -> void:
	target.state = TILE_FAULT
	running = false
	fault_lane = target.lane
	fault_time = 0.0
	lane_flash[pressed_lane] = 1.0
	lane_flash_color[pressed_lane] = Palette.DANGER
	_burst(Vector2(lane_center_x(target.lane), target.y), Palette.DANGER, 22, 130.0)
	emit_signal("tile_mistap", pressed_lane, target.lane)


func _process(delta: float) -> void:
	time += delta
	strike_flash = maxf(0.0, strike_flash - delta * 3.2)
	for i in range(LANES):
		lane_flash[i] = maxf(0.0, lane_flash[i] - delta * 3.4)
	if fault_lane >= 0:
		fault_time += delta

	# Reclaim shattered tiles so long runs do not grow without bound.
	var ti := tiles.size() - 1
	while ti >= 0:
		if tiles[ti].state == TILE_DEAD:
			tiles.remove_at(ti)
		ti -= 1

	if running:
		var dy := speed * delta
		scroll += dy
		for t in tiles:
			if t.state == TILE_ACTIVE:
				t.y += dy
		_fill_queue()
		var target := get_active_tile()
		if target != null:
			var dist := absf(target.y - STRIKE_Y)
			var hittable := dist <= hit_window
			if target.lane != _active_lane or hittable != _was_hittable:
				_active_lane = target.lane
				_was_hittable = hittable
				emit_signal("focus_changed", _active_lane, hittable)
			if target.y > STRIKE_Y + hit_window:
				target.state = TILE_FAULT
				running = false
				fault_lane = target.lane
				fault_time = 0.0
				_burst(Vector2(lane_center_x(target.lane), target.y), Palette.DANGER, 18, 90.0)
				emit_signal("tile_escaped", target.lane)

	_update_shards(delta)
	queue_redraw()


## Places a deterministic stack of tiles for screenshots / preview states.
func debug_pose(active_offset: float, seed_value: int = 4242) -> void:
	tiles.clear()
	shards.clear()
	_rng.seed = seed_value
	var lanes: Array[int] = [2, 0, 3, 1, 2, 3, 0]
	var first_y := STRIKE_Y + active_offset
	for i in range(lanes.size()):
		tiles.append(_make_tile(lanes[i], first_y - i * SPACING))
	running = false
	fault_lane = -1
	_active_lane = -1
	_was_hittable = false
	queue_redraw()


func _burst(pos: Vector2, color: Color, count: int, spread: float) -> void:
	for i in range(count):
		var angle := _rng.randf_range(0.0, TAU)
		var spd := _rng.randf_range(60.0, 320.0 + spread)
		var vel := Vector2(cos(angle), sin(angle)) * spd
		vel.y -= _rng.randf_range(40.0, 160.0)
		var life := _rng.randf_range(0.35, 0.85)
		shards.append(Shard.new(
			pos + Vector2(_rng.randf_range(-42.0, 42.0), _rng.randf_range(-42.0, 42.0)),
			vel,
			life,
			_rng.randf_range(4.0, 13.0),
			_rng.randf_range(0.0, TAU),
			_rng.randf_range(-9.0, 9.0),
			color
		))


func _update_shards(delta: float) -> void:
	var i := shards.size() - 1
	while i >= 0:
		var s := shards[i]
		s.life -= delta
		if s.life <= 0.0:
			shards.remove_at(i)
		else:
			s.vel.y += 950.0 * delta
			s.pos += s.vel * delta
			s.rot += s.rot_spd * delta
			s.vel *= 1.0 - delta * 0.7
		i -= 1


func _draw() -> void:
	# Base board.
	draw_rect(Rect2(BOARD_LEFT, 0.0, BOARD_W, 720.0), Palette.BOARD_BG)

	# Alternating lane shading.
	for i in range(LANES):
		if i % 2 == 1:
			draw_rect(Rect2(BOARD_LEFT + i * LANE_W, 0.0, LANE_W, 720.0), Color(1.0, 1.0, 1.0, 0.02))

	# Scrolling horizontal grid.
	var offset := fmod(scroll, GRID_STEP)
	var gy := offset - GRID_STEP
	while gy < 720.0:
		draw_line(Vector2(BOARD_LEFT, gy), Vector2(BOARD_RIGHT, gy), Palette.GRID, 1.0)
		gy += GRID_STEP

	# Vertical lane separators.
	for i in range(LANES + 1):
		var x := BOARD_LEFT + i * LANE_W
		var edge := i == 0 or i == LANES
		draw_line(
			Vector2(x, 0.0),
			Vector2(x, 720.0),
			Palette.GRID_STRONG if edge else Palette.GRID,
			2.0 if edge else 1.0
		)

	# Strike window band.
	var zt := STRIKE_Y - hit_window
	var zb := STRIKE_Y + hit_window
	draw_rect(Rect2(BOARD_LEFT, zt, BOARD_W, zb - zt), Color(1.0, 1.0, 1.0, 0.03))

	# Tiles.
	var active := get_active_tile()
	for t in tiles:
		if t.state == TILE_ACTIVE:
			_draw_tile(t, t == active)
	for t in tiles:
		if t.state == TILE_FAULT:
			_draw_fault(t)

	# Hit flashes.
	for i in range(LANES):
		var f := lane_flash[i]
		if f > 0.01:
			var c := lane_flash_color[i]
			draw_rect(
				Rect2(BOARD_LEFT + i * LANE_W, 0.0, LANE_W, 720.0),
				Color(c.r, c.g, c.b, 0.16 * f)
			)

	_draw_strike()

	# Shatter shards.
	for s in shards:
		var alpha := clampf(s.life / s.max_life, 0.0, 1.0)
		var col := s.color
		col.a = alpha
		var half := s.size * 0.5
		var c := cos(s.rot)
		var sn := sin(s.rot)
		var pts := PackedVector2Array()
		for k in range(4):
			var ang := TAU * float(k) / 4.0 + PI * 0.25
			var vx := cos(ang) * half
			var vy := sin(ang) * half
			pts.append(s.pos + Vector2(vx * c - vy * sn, vx * sn + vy * c))
		draw_colored_polygon(pts, col)


func _draw_tile(t: Tile, is_target: bool) -> void:
	var cx := lane_center_x(t.lane)
	var r := Rect2(cx - TILE_SIZE * 0.5, t.y - TILE_SIZE * 0.5, TILE_SIZE, TILE_SIZE)
	var dist := absf(t.y - STRIKE_Y)
	var hittable := is_target and dist <= hit_window

	draw_rect(r, Palette.TILE_FILL, true)

	if hittable:
		var neon: Color = Palette.NEON[t.lane]
		var pulse := 0.5 + 0.5 * sin(time * 12.0)
		for k in range(3):
			var grow := 3.0 + float(k) * 5.0 + pulse * 3.0
			var a: float = (0.22 - float(k) * 0.06) * (0.6 + 0.4 * pulse)
			draw_rect(
				Rect2(r.position - Vector2(grow, grow), r.size + Vector2(grow, grow) * 2.0),
				Color(neon.r, neon.g, neon.b, a),
				false,
				3.0
			)
		draw_rect(r, neon, false, 4.0)
		draw_rect(r.grow(-14.0), Color(neon.r, neon.g, neon.b, 0.10 + 0.08 * pulse), true)
	else:
		draw_rect(r, Palette.TILE_EDGE, false, 3.0)


func _draw_fault(t: Tile) -> void:
	var cx := lane_center_x(t.lane)
	var r := Rect2(cx - TILE_SIZE * 0.5, t.y - TILE_SIZE * 0.5, TILE_SIZE, TILE_SIZE)
	var pulse := 0.4 + 0.6 * absf(sin(fault_time * 10.0))
	draw_rect(r, Color(Palette.DANGER.r, Palette.DANGER.g, Palette.DANGER.b, 0.18), true)
	for k in range(3):
		var grow := 4.0 + float(k) * 9.0 + pulse * 4.0
		var a: float = (0.4 - float(k) * 0.1) * pulse
		draw_rect(
			Rect2(r.position - Vector2(grow, grow), r.size + Vector2(grow, grow) * 2.0),
			Color(Palette.DANGER.r, Palette.DANGER.g, Palette.DANGER.b, a),
			false,
			3.0
		)
	draw_rect(r, Palette.DANGER, false, 4.0)


func _draw_strike() -> void:
	var idle := 0.5 + 0.5 * sin(time * 2.4)
	var glow := maxf(strike_flash, idle * 0.4)
	draw_line(
		Vector2(BOARD_LEFT - 20.0, STRIKE_Y),
		Vector2(BOARD_RIGHT + 20.0, STRIKE_Y),
		Color(1.0, 1.0, 1.0, 0.22 + 0.22 * glow),
		2.0
	)
	for k in range(3):
		var w := 6.0 + float(k) * 7.0
		var a: float = (0.20 - float(k) * 0.055) * (0.4 + glow)
		draw_line(
			Vector2(BOARD_LEFT, STRIKE_Y),
			Vector2(BOARD_RIGHT, STRIKE_Y),
			Color(Palette.STRIKE.r, Palette.STRIKE.g, Palette.STRIKE.b, a),
			w
		)
	draw_line(
		Vector2(BOARD_LEFT, STRIKE_Y),
		Vector2(BOARD_RIGHT, STRIKE_Y),
		Palette.STRIKE,
		3.0 + strike_flash * 4.0
	)
