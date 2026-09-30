class_name IvoryBoard
extends Control
## The four-lane play field. Owns tile flow, hit detection, shatter FX and
## the strike-line reaction check.

signal hit(lane: int, perfect: bool, tile_y: float)
signal fault(reason: String)

const LANES := 4

const COL_BG := Color("0a0a11")
const COL_GRID := Color("15151f")
const COL_LANE := Color("20202c")
const COL_BORDER := Color("343442")
const COL_TILE := Color("101018")
const COL_TILE_EDGE := Color("ececf4")
const COL_TILE_CORE := Color("2b2b3a")
const COL_STRIKE := Color("ffffff")
const COL_PERFECT := Color("3ef2ff")
const COL_HIT := Color("b98bff")
const COL_FAULT := Color("ff3557")
const COL_DIM := Color("6d6d80")

# Geometry.
var lane_width := 150.0
var board_height := 576.0
var tile_height := 92.0
var row_gap := 126.0
var strike_y := 464.0
## Uppercase alias so external scripts / tests can read the strike line.
var STRIKE_Y: float:
	get:
		return strike_y
	set(value):
		strike_y = value
var hit_window := 68.0
var perfect_window := 20.0
var queue_length := 6

# Simulation.
var speed := 250.0
var running := false

var tiles: Array = []
var shards: Array = []
var popups: Array = []
var lane_flash := [0.0, 0.0, 0.0, 0.0]
var lane_fault := [0.0, 0.0, 0.0, 0.0]

var shake := 0.0
var screen_flash := 0.0
var flash_color := Color.WHITE

var _offset := Vector2.ZERO
var _time := 0.0
var _last_lane := -1
var _faulting := false
var _fault_lane := -1
var _fault_reason := ""

var _font: Font
var _big_font: Font
var _tile_style: StyleBoxFlat


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(get_board_width(), board_height)
	_font = load("res://assets/fonts/Kenney Mini Square Mono.ttf")
	_big_font = load("res://assets/fonts/Kenney Future.ttf")
	_tile_style = StyleBoxFlat.new()
	_tile_style.bg_color = COL_TILE
	_tile_style.border_color = COL_TILE_EDGE
	_tile_style.set_border_width_all(3)
	_tile_style.set_corner_radius_all(12)
	reset()


func get_board_width() -> float:
	return lane_width * LANES


func reset() -> void:
	tiles.clear()
	shards.clear()
	popups.clear()
	for i in LANES:
		lane_flash[i] = 0.0
		lane_fault[i] = 0.0
	shake = 0.0
	screen_flash = 0.0
	_offset = Vector2.ZERO
	_time = 0.0
	_last_lane = -1
	running = false
	_faulting = false
	_fault_lane = -1
	_fault_reason = ""
	var y := 120.0
	for i in queue_length:
		tiles.append({"lane": _random_lane(), "y": y})
		y -= row_gap
	queue_redraw()


func get_active_tile():
	if tiles.is_empty():
		return null
	var active = tiles[0]
	for tile in tiles:
		if tile.y > active.y:
			active = tile
	return active


## Called for keyboard lanes and lane-region clicks.
func press_lane(lane: int) -> void:
	if not running or _faulting:
		return
	var active = get_active_tile()
	if active == null:
		_fault("ESCAPED", lane)
		return
	if active.lane == lane and abs(active.y - strike_y) <= hit_window:
		_resolve_hit(active, lane)
	else:
		_fault("MISTAP", lane)


## Adds a floating text popup (used for score feedback from the game root).
func spawn_popup(lane: int, tile_y: float, text: String, color: Color) -> void:
	popups.append({
		"text": text,
		"pos": Vector2(lane * lane_width + lane_width * 0.5, tile_y - 6.0),
		"life": 0.75,
		"max_life": 0.75,
		"color": color,
	})


func _process(delta: float) -> void:
	_time += delta
	for i in LANES:
		lane_flash[i] = max(0.0, lane_flash[i] - delta * 4.0)
		lane_fault[i] = max(0.0, lane_fault[i] - delta * 1.6)
	screen_flash = max(0.0, screen_flash - delta * 3.5)

	if shake > 0.03:
		shake = max(0.0, shake - delta * 80.0)
		_offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		shake = 0.0
		_offset = Vector2.ZERO

	if running:
		var step := speed * delta
		for tile in tiles:
			tile.y += step
		var active = get_active_tile()
		if active != null and active.y > strike_y + hit_window:
			_fault("ESCAPED", active.lane)

	_update_shards(delta)
	_update_popups(delta)
	queue_redraw()


func _resolve_hit(tile, lane: int) -> void:
	var ty: float = tile.y
	var perfect: bool = abs(ty - strike_y) <= perfect_window
	var color: Color = COL_PERFECT if perfect else COL_HIT
	tiles.erase(tile)
	_append_tile()
	lane_flash[lane] = 1.0
	screen_flash = 0.4
	flash_color = color
	_spawn_shards(tile, color, perfect)
	hit.emit(lane, perfect, ty)


func _append_tile() -> void:
	var top := 1.0e20
	for tile in tiles:
		top = min(top, tile.y)
	if top > 1.0e19:
		top = 150.0 + row_gap
	tiles.append({"lane": _random_lane(), "y": top - row_gap})


func _random_lane() -> int:
	var lane := randi() % LANES
	if lane == _last_lane:
		lane = (lane + 1 + randi() % (LANES - 1)) % LANES
	_last_lane = lane
	return lane


func _fault(reason: String, lane: int) -> void:
	if _faulting:
		return
	_faulting = true
	running = false
	_fault_reason = reason
	_fault_lane = lane
	if lane >= 0 and lane < LANES:
		lane_fault[lane] = 1.0
	shake = 26.0
	screen_flash = 0.9
	flash_color = COL_FAULT
	fault.emit(reason)


func _spawn_shards(tile, color: Color, perfect: bool) -> void:
	var lane: int = tile.lane
	var ty: float = tile.y
	var center := Vector2(
		lane * lane_width + lane_width * 0.5,
		ty + tile_height * 0.5
	)
	var count := 22 if perfect else 14
	for i in count:
		var angle := randf() * TAU
		var spd := randf_range(140.0, 620.0)
		shards.append({
			"pos": center + Vector2(randf_range(-26.0, 26.0), randf_range(-34.0, 34.0)),
			"vel": Vector2(cos(angle), sin(angle)) * spd + Vector2(0.0, -180.0),
			"life": randf_range(0.35, 0.72),
			"max_life": 0.72,
			"size": randf_range(4.0, 11.0),
			"rot": randf() * TAU,
			"spin": randf_range(-10.0, 10.0),
			"color": color,
		})
	while shards.size() > 640:
		shards.pop_front()


func _update_shards(delta: float) -> void:
	var i := shards.size() - 1
	while i >= 0:
		var shard = shards[i]
		shard.life -= delta
		if shard.life <= 0.0:
			shards.remove_at(i)
		else:
			shard.pos += shard.vel * delta
			shard.vel.y += 980.0 * delta
			shard.vel *= 1.0 - min(1.0, delta * 2.4)
			shard.rot += shard.spin * delta
		i -= 1


func _update_popups(delta: float) -> void:
	var i := popups.size() - 1
	while i >= 0:
		var popup = popups[i]
		popup.life -= delta
		if popup.life <= 0.0:
			popups.remove_at(i)
		else:
			popup.pos.y -= delta * 70.0
		i -= 1


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

func _draw() -> void:
	draw_set_transform(_offset)
	var w := get_board_width()

	draw_rect(Rect2(0, 0, w, board_height), COL_BG)

	# Descending horizontal grid, tied to scroll speed so it reads as motion.
	var grid_offset := fmod(_time * max(speed, 1.0), 64.0)
	var gy := grid_offset
	while gy < board_height:
		draw_line(Vector2(0, gy), Vector2(w, gy), COL_GRID, 1.0)
		gy += 64.0

	for i in range(1, LANES):
		var x := i * lane_width
		draw_line(Vector2(x, 0), Vector2(x, board_height), COL_LANE, 2.0)

	# Lane reaction flashes.
	for i in LANES:
		if lane_fault[i] > 0.0:
			var fault_col := COL_FAULT
			fault_col.a = lane_fault[i] * 0.42
			draw_rect(Rect2(i * lane_width, 0, lane_width, board_height), fault_col)
		if lane_flash[i] > 0.0:
			var flash_col := COL_PERFECT
			flash_col.a = lane_flash[i] * 0.14
			draw_rect(Rect2(i * lane_width, 0, lane_width, board_height), flash_col)

	# Strike zone band.
	draw_rect(Rect2(0, strike_y - hit_window, w, hit_window * 2.0), Color(1, 1, 1, 0.035))

	var active = get_active_tile()
	for tile in tiles:
		_draw_tile(tile, tile == active)

	_draw_strike(w)
	_draw_shards()
	_draw_popups()
	_draw_key_hints()

	draw_rect(Rect2(0, 0, w, board_height), COL_BORDER, false, 3.0)

	if screen_flash > 0.0:
		var sc := flash_color
		sc.a = screen_flash * 0.22
		draw_rect(Rect2(0, 0, w, board_height), sc)


func _draw_tile(tile, is_active: bool) -> void:
	var lane: int = tile.lane
	var ty: float = tile.y
	var x := lane * lane_width + 10.0
	var w := lane_width - 20.0
	var rect := Rect2(x, ty, w, tile_height)
	var in_window: bool = is_active and abs(ty - strike_y) <= hit_window
	var is_fault_tile: bool = _faulting and lane == _fault_lane and abs(ty - strike_y) <= hit_window + row_gap

	var edge := COL_TILE_EDGE
	if is_fault_tile:
		edge = COL_FAULT
	elif in_window:
		edge = COL_PERFECT if abs(ty - strike_y) <= perfect_window else COL_HIT

	_tile_style.bg_color = COL_TILE
	_tile_style.border_color = edge
	if is_fault_tile:
		_tile_style.bg_color = Color(0.24, 0.03, 0.07)
	draw_style_box(_tile_style, rect)

	# Soft inner key face + front bar.
	var face := Color(1, 1, 1, 0.03 if not in_window else 0.08)
	draw_rect(Rect2(x + 10.0, ty + 10.0, w - 20.0, tile_height - 34.0), face)
	var bar_col := edge
	bar_col.a = 0.85
	draw_rect(Rect2(x + 16.0, ty + tile_height - 22.0, w - 32.0, 6.0), bar_col)

	if in_window:
		var glow := edge
		glow.a = 0.22
		draw_rect(Rect2(x - 5.0, ty - 5.0, w + 10.0, tile_height + 10.0), glow, false, 3.0)


func _draw_strike(w: float) -> void:
	for i in range(4):
		var h := 2.0 + i * 6.0
		var col := Color(1, 1, 1, 0.05 * (4 - i))
		draw_rect(Rect2(0, strike_y - h * 0.5, w, h), col)
	draw_line(Vector2(0, strike_y), Vector2(w, strike_y), COL_STRIKE, 2.0)
	draw_circle(Vector2(0, strike_y), 4.0, COL_STRIKE)
	draw_circle(Vector2(w, strike_y), 4.0, COL_STRIKE)


func _draw_shards() -> void:
	for shard in shards:
		var t: float = clampf(shard.life / shard.max_life, 0.0, 1.0)
		var col: Color = shard.color
		col.a = t
		var rot: float = shard.rot
		var dir := Vector2(cos(rot), sin(rot))
		var pos: Vector2 = shard.pos
		var half: float = shard.size * (0.4 + 0.6 * t) * 0.5
		draw_line(pos - dir * half, pos + dir * half, col, 2.0 + 3.0 * t)


func _draw_popups() -> void:
	for popup in popups:
		var t: float = clampf(popup.life / popup.max_life, 0.0, 1.0)
		var col: Color = popup.color
		col.a = t
		var base: Vector2 = popup.pos
		var size := 26 if t > 0.6 else 22
		draw_string(_font, base - Vector2(90.0, 0.0), popup.text, HORIZONTAL_ALIGNMENT_CENTER, 180.0, size, col)


func _draw_key_hints() -> void:
	var labels := ["A", "S", "D", "F"]
	for i in LANES:
		var x := i * lane_width + lane_width * 0.5
		var col := COL_DIM
		if lane_flash[i] > 0.0:
			col = COL_PERFECT
		col.a = 0.55
		draw_string(_font, Vector2(x - 20.0, board_height - 20.0), labels[i], HORIZONTAL_ALIGNMENT_CENTER, 40.0, 22, col)
