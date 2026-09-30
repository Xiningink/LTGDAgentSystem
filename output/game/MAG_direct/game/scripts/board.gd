## The chamber view: simulation, animation and all of the board artwork.
##
## Everything (floors, walls, crates, magnets, hazards, gates, portals) is drawn
## procedurally so it stays crisp at any resolution and can react to state.
class_name Board
extends Control

signal move_committed(result: Dictionary)
signal move_blocked(result: Dictionary)
signal solved(result: Dictionary)
signal undo_performed()

const MOVE_BUSY := 0.13
const LERP_SPEED := 15.0

var sim: MagnetSim
var level: Dictionary = {}

var tile_size: float = 48.0
var origin: Vector2 = Vector2.ZERO
var board_size: Vector2 = Vector2.ZERO

var moves: int = 0
var history: Array = []
var input_enabled: bool = true
var show_field_links: bool = true

var _t: float = 0.0
var _busy: float = 0.0
var _player_render: Vector2 = Vector2.ZERO
var _player_facing: Vector2i = Vector2i.RIGHT
var _vis_items: Array = []          # {"kind","pol","pos","render","pop"}
var _ghosts: Array = []             # fading destroyed objects
var _particles: Array = []
var _rings: Array = []
var _bolts: Array = []
var _pop: Dictionary = {}           # Vector2i -> float (tile pop animation)
var _flash: float = 0.0
var _flash_color: Color = Color.WHITE
var _shake: float = 0.0
var _rewind: float = 0.0
var _gate_glow: Dictionary = {}     # letter -> float
var _plate_glow: Dictionary = {}    # Vector2i -> float
var _plate_state: Dictionary = {}   # Vector2i -> bool
var _hover: Vector2i = Vector2i(-1, -1)
var _queued: Vector2i = Vector2i.ZERO
var _last_size: Vector2 = Vector2.ZERO
var _sb: Dictionary = {}
var _heartbeat: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false


func _ready() -> void:
	set_process(true)


# --- public API --------------------------------------------------------------

func load_level(level_data: Dictionary) -> void:
	level = level_data
	sim = MagnetSim.new()
	sim.load_level(level_data)
	moves = 0
	history.clear()
	_player_render = Vector2(sim.player)
	_player_facing = Vector2i.RIGHT
	_busy = 0.0
	_particles.clear()
	_rings.clear()
	_bolts.clear()
	_ghosts.clear()
	_pop.clear()
	_gate_glow.clear()
	_plate_glow.clear()
	_flash = 0.0
	_shake = 0.0
	_rewind = 0.0
	_rebuild_visuals()
	_layout(true)
	_queued = Vector2i.ZERO
	queue_redraw()


func try_move(dir: Vector2i) -> bool:
	if sim == null or not input_enabled:
		return false
	if _busy > 0.0:
		_queued = dir
		return false
	_layout()
	var snapshot: Dictionary = sim.snapshot()
	var result: Dictionary = sim.try_move(dir)
	if not bool(result["ok"]):
		_shake = maxf(_shake, 0.28)
		Sfx.play("ui_deny", -12.0)
		move_blocked.emit(result)
		# whoosh of a failed nudge
		var t := sim.player + dir
		if sim.has_tile(t):
			_burst(Vector2(t), Palette.TEXT_FAINT, 4, 0.55, 0.0)
		return false
	history.append(snapshot)
	if history.size() > 200:
		history.pop_front()
	moves += 1
	_player_facing = dir
	_apply_result(result)
	_feedback(result)
	move_committed.emit(result)
	if bool(result["reached_exit"]):
		input_enabled = false
		solved.emit(result)
	return true


func undo() -> bool:
	if sim == null or history.is_empty() or _busy > 0.0:
		return false
	sim.restore(history.pop_back())
	moves = maxi(moves - 1, 0)
	_rebuild_visuals()
	_queued = Vector2i.ZERO
	_busy = 0.08
	_rewind = 1.0
	Sfx.play("ui_back", -8.0)
	undo_performed.emit()
	queue_redraw()
	return true


func reset_level() -> void:
	if sim == null:
		return
	var fresh := MagnetSim.new()
	fresh.load_level(level)
	sim = fresh
	moves = 0
	history.clear()
	_queued = Vector2i.ZERO
	input_enabled = true
	_rebuild_visuals()
	_busy = 0.08
	_rewind = 1.0
	_shake = 0.2
	Sfx.play("ui_back", -6.0)
	queue_redraw()


func can_undo() -> bool:
	return not history.is_empty()


## QA helper: jump straight to an arbitrary state (used by screenshot scenarios).
func force_state(player_pos: Vector2i, item_list: Dictionary, move_count: int) -> void:
	if sim == null:
		return
	_layout()
	sim.items.clear()
	for pos in item_list:
		sim.items[pos] = item_list[pos]
	sim.player = player_pos
	moves = move_count
	history.clear()
	_rebuild_visuals()
	_busy = 0.0
	queue_redraw()


func force_win() -> void:
	if sim == null:
		return
	for pos in sim.tiles:
		if sim.tile_at(pos) == MagnetSim.EXIT:
			sim.player = pos
			break
	_rebuild_visuals()
	input_enabled = false
	celebrate()
	solved.emit({"reached_exit": true, "player_to": sim.player, "moves": [], "destroys": [],
		"cleared": [], "swapped": false, "cascaded": false, "flipped": false,
		"gates_opened": [], "gates_closed": [], "ok": true, "reason": ""})


## QA helper: replay a string of moves directly against the model.
func debug_walk(path: String) -> void:
	if sim == null:
		return
	_layout()
	for i in range(path.length()):
		var ch := path.substr(i, 1)
		var dir := Vector2i.ZERO
		match ch:
			"U": dir = Vector2i(0, -1)
			"D": dir = Vector2i(0, 1)
			"L": dir = Vector2i(-1, 0)
			"R": dir = Vector2i(1, 0)
		if dir == Vector2i.ZERO:
			continue
		var result := sim.try_move(dir)
		if bool(result["ok"]):
			moves += 1
	_rebuild_visuals()
	_busy = 0.0
	queue_redraw()


func level_id() -> String:
	return String(level.get("id", ""))


func par() -> int:
	return int(level.get("par", 0))


# --- state plumbing ----------------------------------------------------------

func _rebuild_visuals() -> void:
	_vis_items.clear()
	_plate_state.clear()
	for pos in sim.items:
		var item: Dictionary = sim.items[pos]
		_vis_items.append({
			"kind": String(item["kind"]),
			"pol": String(item.get("pol", "")),
			"pos": pos,
			"render": Vector2(pos),
			"pop": 0.0,
		})
	for pos in sim.tiles:
		if MagnetSim.PLATE_LETTERS.has(sim.tile_at(pos)):
			_plate_state[pos] = sim.plate_pressed(pos)
	_player_render = Vector2(sim.player)


func _vis_at(pos: Vector2i) -> Dictionary:
	for entry in _vis_items:
		if entry["pos"] == pos:
			return entry
	return {}


func _apply_result(result: Dictionary) -> void:
	# objects first
	for move in result["moves"]:
		var entry := _vis_at(move["from"])
		if entry.is_empty():
			continue
		entry["pos"] = move["to"]
		entry["pop"] = 1.0
		_pop[move["to"]] = 1.0
	for entry in result["destroys"]:
		var at: Vector2i = entry["at"]
		var vis := _vis_at(at)
		if not vis.is_empty():
			_vis_items.erase(vis)
			_ghosts.append({
				"kind": vis["kind"], "pol": vis["pol"], "pos": at,
				"render": Vector2(at), "life": 0.5, "max_life": 0.5,
			})
	# then the player steps into the freed tile
	_pop[result["player_to"]] = 1.0


func _feedback(result: Dictionary) -> void:
	_busy = MOVE_BUSY
	var pp: Vector2i = result["player_to"]
	var target_center := Vector2(pp)
	if bool(result["swapped"]):
		Sfx.play_varied("attract", -9.0)
		_burst(Vector2(pp), Palette.polarity_color(sim.polarity), 10, 1.6, 0.0)
		_ring(Vector2(pp), Palette.polarity_color(sim.polarity), 1.1, 0.32)
	elif not result["moves"].is_empty():
		var any_magnet := false
		for entry in result["moves"]:
			var vis := _vis_at(entry["to"])
			if not vis.is_empty() and String(vis["kind"]) == "magnet":
				any_magnet = true
				break
		if any_magnet:
			Sfx.play_varied("repel", -9.0)
			_burst(target_center, Palette.NORTH, 8, 1.5, 0.0)
		else:
			Sfx.play_varied("crate", -11.0)
			_burst(target_center, Palette.METAL, 6, 1.1, 0.0)
		if bool(result["cascaded"]):
			_shake = maxf(_shake, 0.22)
			_flash = 0.35
			_flash_color = Palette.NORTH
	else:
		Sfx.play_varied("step", -18.0, 0.12)
		_burst(Vector2(pp), Palette.SWITCH, 3, 0.5, 0.0)

	for dest in result["cleared"]:
		_burst(Vector2(dest), Palette.HAZARD, 26, 2.4, 0.0)
		_ring(Vector2(dest), Palette.HAZARD, 1.35, 0.4)
		_shake = maxf(_shake, 0.5)
		_flash = 0.5
		_flash_color = Palette.HAZARD
		Sfx.play("burn", -7.0)
	if result.has("destroyed_at"):
		var dpos: Vector2i = result["destroyed_at"]
		_burst(Vector2(dpos), Palette.HAZARD, 30, 2.7, 0.0)
		_shake = maxf(_shake, 0.6)
		_flash = 0.6
		_flash_color = Palette.HAZARD
		Sfx.play("burn", -6.0)

	if bool(result["flipped"]):
		Sfx.play("flip", -8.0)
		_ring(Vector2(pp), Palette.SWITCH, 1.5, 0.45)
		_burst(Vector2(pp), Palette.SWITCH, 16, 1.9, 0.0)
		_flash = 0.3
		_flash_color = Palette.SWITCH

	for letter in result["gates_opened"]:
		_gate_glow[letter] = 1.0
		Sfx.play("gate_open", -10.0)
		_bolt_ring(letter, Palette.GATE)
	for letter in result["gates_closed"]:
		Sfx.play("gate_close", -14.0)

	# plate clicks
	for pos in sim.tiles:
		if not MagnetSim.PLATE_LETTERS.has(sim.tile_at(pos)):
			continue
		var pressed := sim.plate_pressed(pos)
		var was: bool = bool(_plate_state.get(pos, false))
		if pressed != was:
			_plate_state[pos] = pressed
			_plate_glow[pos] = 1.0 if pressed else -1.0
			Sfx.play("plate" if pressed else "plate_off", -14.0)
			_burst(Vector2(pos), Palette.PLATE, 8, 1.0, 0.0)
			_ring(Vector2(pos), Palette.PLATE, 0.85, 0.3)


func _bolt_ring(letter: String, color: Color) -> void:
	for pos in sim.gate_positions(letter):
		_ring(Vector2(pos), color, 1.2, 0.4)
		_burst(Vector2(pos), color, 12, 1.6, 0.0)


# --- effects -----------------------------------------------------------------

## All effect geometry is stored in tile space so it survives relayouts.
func _burst(at: Vector2, color: Color, count: int, speed: float, up_bias: float) -> void:
	for i in range(count):
		var ang := randf() * TAU
		var sp := speed * randf_range(0.45, 1.0)
		var vel := Vector2(cos(ang), sin(ang)) * sp
		vel.y -= up_bias * speed * randf_range(0.2, 1.0)
		_particles.append({
			"pos": at,
			"vel": vel,
			"life": randf_range(0.25, 0.6),
			"max_life": 0.6,
			"size": randf_range(0.035, 0.09),
			"color": color,
			"drag": 3.2,
			"gravity": 0.45,
		})


func _ring(at: Vector2, color: Color, max_radius: float, life: float) -> void:
	_rings.append({"pos": at, "color": color, "radius": 0.0, "max_radius": max_radius, "life": life, "max_life": life})


func _lightning(a: Vector2, b: Vector2, color: Color) -> void:
	_bolts.append({"a": a, "b": b, "color": color, "life": 0.22, "max_life": 0.22, "seed": randf() * 100.0})


func screen_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func celebrate() -> void:
	_flash = 0.9
	_flash_color = Palette.EXIT
	_shake = 0.35
	for i in range(6):
		var pos := Vector2i(randi_range(0, sim.width - 1), randi_range(0, sim.height - 1))
		_burst(Vector2(pos), [Palette.EXIT, Palette.GOLD, Palette.SWITCH][i % 3], 14, 2.1, 0.0)


# --- layout ------------------------------------------------------------------

func _layout(force: bool = false) -> void:
	if sim == null:
		return
	if not force and size == _last_size:
		return
	_last_size = size
	var cols := maxi(sim.width, 1)
	var rows := maxi(sim.height, 1)
	var pad := 26.0
	var avail := size - Vector2(pad * 2, pad * 2)
	tile_size = floor(minf(avail.x / float(cols), avail.y / float(rows)))
	tile_size = clampf(tile_size, 18.0, 92.0)
	board_size = Vector2(tile_size * cols, tile_size * rows)
	origin = ((size - board_size) * 0.5).floor()
	origin.y += 2.0


func tile_rect(pos: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(pos) * tile_size, Vector2(tile_size, tile_size))


func _tile_center(pos: Vector2i, offset: Vector2) -> Vector2:
	return origin + (Vector2(pos) + Vector2(0.5, 0.5)) * tile_size + offset


func _tile_center_f(pos: Vector2, offset: Vector2) -> Vector2:
	return origin + (pos + Vector2(0.5, 0.5)) * tile_size + offset


func tile_at_point(point: Vector2) -> Vector2i:
	var local := (point - origin) / tile_size
	return Vector2i(floori(local.x), floori(local.y))


# --- process -----------------------------------------------------------------

func _process(delta: float) -> void:
	if sim == null:
		return
	_layout()
	_t += delta
	_heartbeat += delta
	_busy = maxf(_busy - delta, 0.0)
	if _busy <= 0.0 and _queued != Vector2i.ZERO and input_enabled:
		var queued := _queued
		_queued = Vector2i.ZERO
		try_move(queued)
	var k := 1.0 - exp(-LERP_SPEED * delta)

	_player_render = _player_render.lerp(Vector2(sim.player), k)
	for entry in _vis_items:
		entry["render"] = (entry["render"] as Vector2).lerp(Vector2(entry["pos"]), k)
		entry["pop"] = maxf(float(entry["pop"]) - delta * 3.6, 0.0)

	for ghost in _ghosts:
		ghost["life"] -= delta
		ghost["render"] = (ghost["render"] as Vector2) + Vector2(0, -delta * 0.9)
	_ghosts = _ghosts.filter(func(g): return g["life"] > 0.0)

	var alive: Array = []
	for p in _particles:
		p["life"] -= delta
		if p["life"] <= 0.0:
			continue
		p["vel"] = (p["vel"] as Vector2) * (1.0 - p["drag"] * delta)
		p["vel"] = (p["vel"] as Vector2) + Vector2(0, p["gravity"] * delta)
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		alive.append(p)
	_particles = alive

	var rings_alive: Array = []
	for r in _rings:
		r["life"] -= delta
		if r["life"] <= 0.0:
			continue
		var f := 1.0 - float(r["life"]) / float(r["max_life"])
		r["radius"] = float(r["max_radius"]) * ease(f, 0.35)
		rings_alive.append(r)
	_rings = rings_alive

	var bolts_alive: Array = []
	for b in _bolts:
		b["life"] -= delta
		if b["life"] > 0.0:
			bolts_alive.append(b)
	_bolts = bolts_alive

	for key in _pop.keys():
		_pop[key] = maxf(float(_pop[key]) - delta * 3.0, 0.0)
	for letter in _gate_glow.keys():
		_gate_glow[letter] = maxf(float(_gate_glow[letter]) - delta * 0.9, 0.0)
	for pos in _plate_glow.keys():
		var v := float(_plate_glow[pos])
		_plate_glow[pos] = v - delta * 1.6 if v > 0.0 else minf(v + delta * 1.6, 0.0)

	_shake = maxf(_shake - delta * 3.4, 0.0)
	_flash = maxf(_flash - delta * 2.2, 0.0)
	_rewind = maxf(_rewind - delta * 2.6, 0.0)
	queue_redraw()


# --- input -------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var pos := tile_at_point(event.position)
		if pos != _hover:
			_hover = pos
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := tile_at_point(event.position)
		if pos != sim.player:
			var delta := pos - sim.player
			if absi(delta.x) + absi(delta.y) == 1:
				try_move(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2i(-1, -1)
		queue_redraw()


# --- style cache -------------------------------------------------------------

func _offset(rect: Rect2, by: Vector2) -> Rect2:
	return Rect2(rect.position + by, rect.size)


func _style(key: String, bg: Color, radius: float, border: Color, bw: float) -> StyleBoxFlat:
	if _sb.has(key):
		return _sb[key]
	var sb := UIKit.flat(bg, radius, border, bw)
	_sb[key] = sb
	return sb


func _style4(key: String, bg: Color, corners: Vector4, border: Color, bw: float) -> StyleBoxFlat:
	if _sb.has(key):
		return _sb[key]
	var sb := UIKit.flat_corners(bg, corners, border, bw)
	_sb[key] = sb
	return sb


func _text_center(text: String, center: Vector2, size_px: int, color: Color, font_kind: String = "main") -> void:
	var f := UIKit.font(font_kind)
	if f == null:
		return
	var dim := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	draw_string(f, center - Vector2(dim.x * 0.5, -dim.y * 0.30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


## Sutherland-Hodgman clip of a convex polygon against a rectangle.
func _clip_poly(poly: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var planes := [
		Vector3(1.0, 0.0, rect.position.x),
		Vector3(-1.0, 0.0, -rect.end.x),
		Vector3(0.0, 1.0, rect.position.y),
		Vector3(0.0, -1.0, -rect.end.y),
	]
	var out := poly
	for plane in planes:
		if out.size() < 3:
			break
		var input := out
		out = PackedVector2Array()
		var n := Vector2(plane.x, plane.y)
		var d: float = plane.z
		for i in range(input.size()):
			var cur := input[i]
			var nxt := input[(i + 1) % input.size()]
			var dc := n.dot(cur) - d
			var dn := n.dot(nxt) - d
			if dc >= 0.0:
				out.append(cur)
			if (dc >= 0.0) != (dn >= 0.0):
				var t := dc / (dc - dn)
				out.append(cur.lerp(nxt, t))
	return out


# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	if sim == null:
		return
	var shake_amount := _shake * 5.0
	var offset := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amount
	draw_set_transform(offset, 0.0, Vector2.ONE)

	_draw_frame()
	_draw_tiles()
	_draw_specials()
	_draw_gates()
	_draw_field_links()
	_draw_plates()
	_draw_switches()
	_draw_entities()
	_draw_ghosts()
	_draw_cursor()
	_draw_effects()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash * 0.18))
	if _rewind > 0.0:
		var y := size.y * (1.0 - _rewind)
		draw_rect(Rect2(0, y - 40, size.x, 40), Color(Palette.SWITCH.r, Palette.SWITCH.g, Palette.SWITCH.b, _rewind * 0.10))


func _draw_frame() -> void:
	var pad := 18.0
	var rect := Rect2(origin - Vector2(pad, pad), board_size + Vector2(pad * 2, pad * 2))
	if not _sb.has("frame"):
		_sb["frame"] = UIKit.panel_style(Color(0.07, 0.11, 0.19), 18.0, true)
	draw_style_box(_sb["frame"], rect)
	# containment field line
	var inner := rect.grow(-6.0)
	draw_rect(inner, Color(Palette.SWITCH.r, Palette.SWITCH.g, Palette.SWITCH.b, 0.14), false, 1.0)
	# corner brackets
	var bl := 14.0
	var bc := Color(Palette.SWITCH.r, Palette.SWITCH.g, Palette.SWITCH.b, 0.55)
	draw_line(inner.position, inner.position + Vector2(bl, 0), bc, 2.0)
	draw_line(inner.position, inner.position + Vector2(0, bl), bc, 2.0)
	draw_line(inner.position + Vector2(inner.size.x, 0), inner.position + Vector2(inner.size.x - bl, 0), bc, 2.0)
	draw_line(inner.position + Vector2(inner.size.x, 0), inner.position + Vector2(inner.size.x, bl), bc, 2.0)
	draw_line(inner.position + Vector2(0, inner.size.y), inner.position + Vector2(bl, inner.size.y), bc, 2.0)
	draw_line(inner.position + Vector2(0, inner.size.y), inner.position + Vector2(0, inner.size.y - bl), bc, 2.0)
	draw_line(inner.position + inner.size, inner.position + inner.size - Vector2(bl, 0), bc, 2.0)
	draw_line(inner.position + inner.size, inner.position + inner.size - Vector2(0, bl), bc, 2.0)


func _draw_tiles() -> void:
	var r := tile_size * 0.14
	for y in range(sim.height):
		for x in range(sim.width):
			var pos := Vector2i(x, y)
			var t := sim.tile_at(pos)
			if t == MagnetSim.VOID:
				continue
			var rect := tile_rect(pos).grow(-1.5)
			var pop := float(_pop.get(pos, 0.0))
			if pop > 0.0:
				rect = rect.grow(pop * 2.5)
			if t == MagnetSim.WALL:
				_draw_wall(rect, pos)
				continue
			var checker := (x + y) % 2 == 0
			var floor_col := Palette.FLOOR_A if checker else Palette.FLOOR_B
			if t == MagnetSim.HAZARD and not sim.inert.has(pos):
				floor_col = Palette.HAZARD_DEEP
			elif t == MagnetSim.EXIT:
				floor_col = Palette.EXIT_DEEP.darkened(0.35)
			draw_style_box(_style("floor%d" % int(r), floor_col, r, Palette.FLOOR_EDGE, 1.0), rect)
			# subtle inner sheen
			if checker:
				draw_rect(rect.grow(-3.0), Color(1, 1, 1, 0.020))
			# corner ticks
			var tick := Color(Palette.SWITCH.r, Palette.SWITCH.g, Palette.SWITCH.b, 0.10)
			draw_line(rect.position + Vector2(4, 4), rect.position + Vector2(9, 4), tick, 1.0)
			draw_line(rect.position + Vector2(4, 4), rect.position + Vector2(4, 9), tick, 1.0)


func _draw_wall(rect: Rect2, pos: Vector2i) -> void:
	var r := tile_size * 0.12
	var body := rect.grow(-1.0)
	var top := Rect2(body.position + Vector2(0, -4.0), body.size)
	draw_style_box(_style("wallbody%d" % int(r), Palette.WALL_BODY, r, Palette.WALL_BODY.darkened(0.35), 1.0), body)
	draw_style_box(_style("walltop%d" % int(r), Palette.WALL_TOP, r, Palette.WALL_EDGE, 1.0), top)
	draw_line(top.position + Vector2(6, 3), top.position + Vector2(top.size.x - 6, 3), Color(1, 1, 1, 0.09), 1.0)
	# rivet
	draw_circle(top.position + Vector2(top.size.x * 0.5, top.size.y * 0.5), maxf(tile_size * 0.045, 1.4), Color(1, 1, 1, 0.05))


func _draw_specials() -> void:
	for y in range(sim.height):
		for x in range(sim.width):
			var pos := Vector2i(x, y)
			var t := sim.tile_at(pos)
			if t == MagnetSim.HAZARD:
				_draw_hazard(pos)
			elif t == MagnetSim.EXIT:
				_draw_exit(pos)


func _draw_hazard(pos: Vector2i) -> void:
	var rect := tile_rect(pos).grow(-2.0)
	if sim.inert.has(pos):
		draw_style_box(_style("dead", Palette.HAZARD_DEAD.darkened(0.3), tile_size * 0.12, Color(0.25, 0.12, 0.18), 1.0), rect)
		draw_line(rect.position + Vector2(6, 6), rect.position + rect.size - Vector2(6, 6), Color(0.6, 0.2, 0.3, 0.35), 2.0)
		draw_line(rect.position + Vector2(rect.size.x - 6, 6), rect.position + Vector2(6, rect.size.y - 6), Color(0.6, 0.2, 0.3, 0.35), 2.0)
		_text_center("OFF", rect.position + rect.size * 0.5, maxi(int(tile_size * 0.2), 8), Color(0.5, 0.3, 0.38, 0.8), "mono")
		return
	var pulse := 0.5 + 0.5 * sin(_heartbeat * 3.0 + float(pos.x + pos.y) * 0.6)
	draw_style_box(_style("haz", Palette.HAZARD_DEEP, tile_size * 0.12, Palette.HAZARD, 2.0), rect)
	# animated hazard stripes, clipped to the tile
	var phase := fmod(_heartbeat * 34.0, 13.0)
	var w := rect.size.x
	var h := rect.size.y
	var thick := tile_size * 0.11
	var d := phase
	while d < w + h:
		var p1: Vector2 = Vector2(d, 0) if d <= w else Vector2(w, d - w)
		var p2: Vector2 = Vector2(0, d) if d <= h else Vector2(d - h, h)
		var dir := (p2 - p1).normalized()
		var perp := Vector2(-dir.y, dir.x) * thick * 0.5
		var quad := PackedVector2Array([
			rect.position + p1 + perp, rect.position + p2 + perp,
			rect.position + p2 - perp, rect.position + p1 - perp,
		])
		var clipped := _clip_poly(quad, rect)
		if clipped.size() >= 3:
			draw_colored_polygon(clipped, Color(Palette.HAZARD.r, Palette.HAZARD.g, Palette.HAZARD.b, 0.20 + 0.18 * pulse))
		d += 13.0
	# crackle
	for i in range(3):
		var ang := _heartbeat * (1.2 + float(i) * 0.5) + float(i) * 2.1
		var c := rect.position + rect.size * 0.5 + Vector2(cos(ang), sin(ang * 1.7)) * tile_size * 0.26
		draw_circle(c, 1.8, Color(1, 0.7, 0.85, 0.5 + 0.4 * pulse))


func _draw_exit(pos: Vector2i) -> void:
	var c := _tile_center(pos, Vector2.ZERO)
	var rect := tile_rect(pos).grow(-2.0)
	draw_style_box(_style("exitbg", Palette.EXIT_DEEP.darkened(0.5), tile_size * 0.2, Palette.EXIT_DEEP, 1.0), rect)
	var pulse := 0.5 + 0.5 * sin(_heartbeat * 2.2)
	draw_circle(c, tile_size * (0.16 + 0.05 * pulse), Color(Palette.EXIT.r, Palette.EXIT.g, Palette.EXIT.b, 0.22))
	for i in range(3):
		var rad := tile_size * (0.14 + float(i) * 0.09)
		var start := _heartbeat * (0.6 + float(i) * 0.35) * (1.0 if i % 2 == 0 else -1.0)
		var a := 0.55 - float(i) * 0.12
		draw_arc(c, rad, start, start + PI * 1.25, 20, Color(Palette.EXIT.r, Palette.EXIT.g, Palette.EXIT.b, a), maxf(tile_size * 0.035, 1.4), true)
	draw_circle(c, tile_size * 0.07, Palette.EXIT)
	for i in range(4):
		var t := fmod(_heartbeat * 0.7 + float(i) * 0.25, 1.0)
		var y := c.y + tile_size * 0.3 - t * tile_size * 0.6
		draw_circle(Vector2(c.x + sin(t * 6.0 + float(i)) * tile_size * 0.12, y), 1.6 * (1.0 - t), Color(Palette.EXIT.r, Palette.EXIT.g, Palette.EXIT.b, 0.5 * (1.0 - t)))


func _draw_plates() -> void:
	for pos in sim.tiles:
		var t := sim.tile_at(pos)
		if not MagnetSim.PLATE_LETTERS.has(t):
			continue
		var rect := tile_rect(pos).grow(-tile_size * 0.22)
		var pressed := sim.plate_pressed(pos)
		var glow := absf(float(_plate_glow.get(pos, 0.0)))
		var pulse := 0.5 + 0.5 * sin(_heartbeat * 2.6 + float(pos.x))
		if pressed:
			draw_style_box(_style("plateOn", Palette.PLATE, tile_size * 0.2, Palette.PLATE.lightened(0.3), 2.0), rect)
			draw_style_box(_style("plateIn", Palette.PLATE_DEEP, tile_size * 0.16, Color(0, 0, 0, 0), 0.0), rect.grow(-tile_size * 0.12))
			_text_center(t.to_upper(), rect.position + rect.size * 0.5, maxi(int(tile_size * 0.34), 9), Palette.TEXT_DARK)
			if sim.occupied(pos):
				# the plate is buried under an object - ring it so "held" still reads
				draw_arc(rect.position + rect.size * 0.5, tile_size * 0.45, 0.0, TAU, 28,
					Color(Palette.PLATE.r, Palette.PLATE.g, Palette.PLATE.b, 0.30 + 0.20 * pulse), 3.0, true)
			if glow > 0.0:
				draw_arc(rect.position + rect.size * 0.5, tile_size * 0.5 + glow * 6.0, 0.0, TAU, 24, Color(Palette.PLATE.r, Palette.PLATE.g, Palette.PLATE.b, glow * 0.6), 2.0, true)
		else:
			var edge := Color(Palette.PLATE.r, Palette.PLATE.g, Palette.PLATE.b, 0.45 + 0.2 * pulse)
			draw_style_box(_style("plateOff", Palette.PLATE_DEEP.darkened(0.55), tile_size * 0.2, edge, 2.0), rect)
			draw_style_box(_style("plateOffIn", Palette.PLATE_DEEP.darkened(0.25), tile_size * 0.16, Color(0, 0, 0, 0), 0.0), rect.grow(-tile_size * 0.13))
			_text_center(t.to_upper(), rect.position + rect.size * 0.5, maxi(int(tile_size * 0.32), 9), Color(Palette.PLATE.r, Palette.PLATE.g, Palette.PLATE.b, 0.55))


func _draw_switches() -> void:
	for pos in sim.tiles:
		if sim.tile_at(pos) != MagnetSim.SWITCH:
			continue
		var c := _tile_center(pos, Vector2.ZERO)
		var rect := tile_rect(pos).grow(-tile_size * 0.14)
		draw_style_box(_style("swBg", Palette.SWITCH_DEEP.darkened(0.4), tile_size * 0.24, Palette.SWITCH_DEEP, 2.0), rect)
		var pulse := 0.5 + 0.5 * sin(_heartbeat * 2.0)
		draw_circle(c, tile_size * 0.30, Color(Palette.SWITCH.r, Palette.SWITCH.g, Palette.SWITCH.b, 0.08 + 0.06 * pulse))
		var rad := tile_size * 0.22
		var start := _heartbeat * 1.6
		draw_arc(c, rad, start, start + PI * 1.45, 22, Palette.SWITCH, maxf(tile_size * 0.05, 2.0), true)
		draw_arc(c, rad, start + PI, start + PI * 1.6, 12, Color(Palette.SWITCH.r, Palette.SWITCH.g, Palette.SWITCH.b, 0.45), maxf(tile_size * 0.05, 2.0), true)
		# arrow head
		var tip_ang := start + PI * 1.45
		var tip := c + Vector2(cos(tip_ang), sin(tip_ang)) * rad
		var tangent := Vector2(-sin(tip_ang), cos(tip_ang))
		var normal := Vector2(cos(tip_ang), sin(tip_ang))
		draw_colored_polygon(PackedVector2Array([
			tip + tangent * tile_size * 0.07,
			tip - tangent * tile_size * 0.07,
			tip + normal * tile_size * 0.09,
		]), Palette.SWITCH)


func _draw_gates() -> void:
	for letter in MagnetSim.GATE_LETTERS:
		var positions := sim.gate_positions(letter)
		if positions.is_empty():
			continue
		var open := sim.gate_open(letter)
		var glow := float(_gate_glow.get(letter, 0.0))
		for pos in positions:
			var rect := tile_rect(pos).grow(-2.0)
			var c := _tile_center(pos, Vector2.ZERO)
			if open:
				draw_rect(rect.grow(-4.0), Color(Palette.GATE.r, Palette.GATE.g, Palette.GATE.b, 0.06), false, 1.0)
				# retracted stubs top and bottom
				var stub := Rect2(rect.position + Vector2(rect.size.x * 0.18, 0), Vector2(rect.size.x * 0.64, rect.size.y * 0.14))
				draw_style_box(_style("gateStub", Palette.GATE_DEEP.darkened(0.2), 3.0, Color(0, 0, 0, 0), 0.0), stub)
				draw_style_box(_style("gateStub2", Palette.GATE_DEEP.darkened(0.2), 3.0, Color(0, 0, 0, 0), 0.0), Rect2(rect.position + Vector2(rect.size.x * 0.18, rect.size.y * 0.86), Vector2(rect.size.x * 0.64, rect.size.y * 0.14)))
				_text_center(letter, c, maxi(int(tile_size * 0.24), 8), Color(Palette.GATE.r, Palette.GATE.g, Palette.GATE.b, 0.30))
			else:
				draw_style_box(_style("gateBg", Palette.GATE_DEEP.darkened(0.55), tile_size * 0.14, Palette.GATE_DEEP, 1.5), rect)
				var bars := 3
				for i in range(bars):
					var bx := rect.position.x + rect.size.x * (0.16 + 0.30 * float(i))
					var bar := Rect2(bx, rect.position.y + rect.size.y * 0.08, rect.size.x * 0.14, rect.size.y * 0.84)
					var tint := Palette.GATE if i == 1 else Palette.GATE.darkened(0.12)
					draw_style_box(_style("gateBar", tint, 3.0, Palette.GATE.lightened(0.4), 1.0), bar)
				if glow > 0.0:
					draw_rect(rect, Color(Palette.GATE.r, Palette.GATE.g, Palette.GATE.b, glow * 0.35), false, 3.0)
				_text_center(letter, c, maxi(int(tile_size * 0.26), 8), Color(Palette.TEXT_DARK.r, Palette.TEXT_DARK.g, Palette.TEXT_DARK.b, 0.8))


func _draw_field_links() -> void:
	if not show_field_links or sim == null:
		return
	var pc := _tile_center_f(_player_render, Vector2.ZERO)
	for entry in _vis_items:
		if String(entry["kind"]) != "magnet":
			continue
		var pos: Vector2i = entry["pos"]
		var delta := pos - sim.player
		if absi(delta.x) + absi(delta.y) != 1:
			continue
		var mc := _tile_center_f(entry["render"], Vector2.ZERO)
		var bolt_a: Vector2 = _player_render
		var bolt_b: Vector2 = entry["render"]
		var same := String(entry["pol"]) == sim.polarity
		var col := Palette.polarity_color(String(entry["pol"]))
		if same:
			# repulsion: a jagged bolt pushing away
			if randf() < 0.22:
				_lightning(bolt_a, bolt_b, col)
			var mid := (pc + mc) * 0.5
			var dir := (mc - pc).normalized()
			var perp := Vector2(-dir.y, dir.x)
			var push := 3.0 + 3.0 * sin(_heartbeat * 6.0)
			draw_line(mid + perp * 8.0 - dir * push, mid - perp * 8.0 - dir * push, Color(1, 1, 1, 0.22), 2.0)
			draw_line(mid + perp * 8.0, mid - perp * 8.0, Color(col.r, col.g, col.b, 0.35), 2.0)
		else:
			# attraction: bright dotted pull
			var dir2 := (mc - pc).normalized()
			var dist := pc.distance_to(mc)
			var steps := 5
			for i in range(steps):
				var t := (float(i) + fmod(_heartbeat * 1.6, 1.0)) / float(steps)
				var p := pc + dir2 * dist * t
				draw_circle(p, 2.2, Color(col.r, col.g, col.b, 0.35 + 0.3 * t))


func _draw_cursor() -> void:
	if _hover.x < 0 or _hover.x >= sim.width or _hover.y < 0 or _hover.y >= sim.height:
		return
	var delta := _hover - sim.player
	if absi(delta.x) + absi(delta.y) != 1:
		return
	if not sim.player_can_enter(_hover):
		return
	var rect := tile_rect(_hover).grow(-3.0)
	var pulse := 0.5 + 0.5 * sin(_heartbeat * 4.0)
	draw_rect(rect, Color(Palette.SWITCH.r, Palette.SWITCH.g, Palette.SWITCH.b, 0.18 + 0.12 * pulse), false, 2.0)


func _draw_entities() -> void:
	# magnets and crates first, then the player on top
	var ordered := _vis_items.duplicate()
	ordered.sort_custom(func(a, b): return float(a["render"].y) < float(b["render"].y))
	for entry in ordered:
		var pos: Vector2 = entry["render"]
		var pop := float(entry["pop"])
		var scale := 1.0 + pop * 0.12
		if String(entry["kind"]) == "metal":
			_draw_crate(pos, scale)
		else:
			_draw_magnet(pos, String(entry["pol"]), scale)
	_draw_player()


func _entity_rect(render: Vector2, scale: float) -> Rect2:
	var s := tile_size * 0.78 * scale
	return Rect2(origin + render * tile_size + Vector2(tile_size, tile_size) * 0.5 - Vector2(s, s) * 0.5, Vector2(s, s))


func _draw_crate(render: Vector2, scale: float) -> void:
	var rect := _entity_rect(render, scale)
	var r := rect.size.x * 0.18
	draw_style_box(_style("crateShadow", Color(0, 0, 0, 0.30), r, Color(0, 0, 0, 0), 0.0), _offset(rect, Vector2(0, 3)))
	draw_style_box(_style("crateBody", Palette.METAL_DEEP, r, Palette.METAL_EDGE.darkened(0.2), 2.0), rect)
	var inner := rect.grow(-rect.size.x * 0.16)
	draw_style_box(_style("crateInner", Palette.METAL, r * 0.7, Color(0, 0, 0, 0), 0.0), inner)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.34)), Color(1, 1, 1, 0.13))
	# rivets
	var rv := maxf(rect.size.x * 0.045, 1.4)
	for corner in [Vector2(0.16, 0.16), Vector2(0.84, 0.16), Vector2(0.16, 0.84), Vector2(0.84, 0.84)]:
		draw_circle(rect.position + rect.size * corner, rv, Palette.METAL_DEEP.darkened(0.3))
	# weld cross
	draw_line(inner.position + Vector2(4, inner.size.y * 0.5), inner.position + Vector2(inner.size.x - 4, inner.size.y * 0.5), Color(0, 0, 0, 0.16), 1.5)


func _draw_magnet(render: Vector2, pol: String, scale: float) -> void:
	var rect := _entity_rect(render, scale)
	var r := rect.size.x * 0.24
	var col := Palette.polarity_color(pol)
	var deep := Palette.polarity_deep(pol)
	var pulse := 0.5 + 0.5 * sin(_heartbeat * 2.4 + render.x + render.y)
	var center := rect.position + rect.size * 0.5
	# field aura
	draw_circle(center, rect.size.x * (0.70 + 0.05 * pulse), Color(col.r, col.g, col.b, 0.11))
	draw_circle(center, rect.size.x * 0.56, Color(col.r, col.g, col.b, 0.07))
	# shadow + casing
	draw_style_box(_style("magShadow", Color(0, 0, 0, 0.34), r, Color(0, 0, 0, 0), 0.0), _offset(rect, Vector2(0, 3)))
	draw_style_box(_style("magCase", deep.darkened(0.35), r, col.lightened(0.35), 2.0), rect)
	# polarised face
	var face := rect.grow(-rect.size.x * 0.11)
	draw_style_box(_style("magFace" + pol, col, r * 0.6, Color(0, 0, 0, 0), 0.0), face)
	draw_rect(Rect2(face.position, Vector2(face.size.x, face.size.y * 0.34)), Color(1, 1, 1, 0.16))
	draw_rect(Rect2(face.position + Vector2(0, face.size.y * 0.66), Vector2(face.size.x, face.size.y * 0.34)), Color(0, 0, 0, 0.12))
	# pole marks
	var pip := maxf(rect.size.x * 0.07, 1.5)
	draw_circle(Vector2(center.x - rect.size.x * 0.26, center.y), pip, Color(1, 1, 1, 0.55))
	draw_circle(Vector2(center.x + rect.size.x * 0.26, center.y), pip, Color(0, 0, 0, 0.30))
	# the polarity letter, outlined for legibility
	var fs := maxi(int(rect.size.x * 0.52), 10)
	var f := UIKit.font("main")
	if f != null:
		var letter := "N" if pol == "N" else "S"
		var dim := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var at := center - Vector2(dim.x * 0.5, -dim.y * 0.32)
		draw_string_outline(f, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(fs / 8, 2), Color(0, 0, 0, 0.45))
		draw_string(f, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.96))


func _draw_player() -> void:
	var rect := _entity_rect(_player_render, 1.0)
	var c := rect.position + rect.size * 0.5
	var col := Palette.polarity_color(sim.polarity)
	var pulse := 0.5 + 0.5 * sin(_heartbeat * 3.0)
	var radius := rect.size.x * 0.5
	draw_circle(c, radius * (1.30 + 0.07 * pulse), Color(col.r, col.g, col.b, 0.13))
	draw_circle(c, radius * (1.05 + 0.04 * pulse), Color(col.r, col.g, col.b, 0.16))
	draw_circle(c, radius, Palette.PANEL_EDGE.darkened(0.45))
	draw_arc(c, radius * 0.86, 0.0, TAU, 36, col, radius * 0.30, true)
	# field ticks around the ring
	for i in range(4):
		var ang := _heartbeat * 1.2 + TAU * float(i) / 4.0
		var d := Vector2(cos(ang), sin(ang))
		draw_line(c + d * radius * 0.66, c + d * radius * 0.42, Color(1, 1, 1, 0.35), maxf(radius * 0.10, 1.4), true)
	draw_circle(c, radius * 0.42, Palette.PLAYER_CORE)
	draw_circle(c - Vector2(radius * 0.13, radius * 0.15), radius * 0.16, Color(1, 1, 1, 0.95))
	draw_circle(c + Vector2(radius * 0.16, radius * 0.18), radius * 0.12, Color(col.r, col.g, col.b, 0.35))
	# facing notch
	var dir := Vector2(_player_facing)
	if dir != Vector2.ZERO:
		var n := c + dir * radius * 1.04
		var perp := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			n + dir * radius * 0.30,
			n + perp * radius * 0.24 - dir * radius * 0.1,
			n - perp * radius * 0.24 - dir * radius * 0.1,
		]), col.lightened(0.45))


func _draw_ghosts() -> void:
	for ghost in _ghosts:
		var f := clampf(float(ghost["life"]) / float(ghost["max_life"]), 0.0, 1.0)
		var rect := _entity_rect(ghost["render"], 1.0 + (1.0 - f) * 0.5)
		var col := Palette.polarity_color(String(ghost["pol"])) if String(ghost["kind"]) == "magnet" else Palette.METAL
		draw_rect(rect, Color(col.r, col.g, col.b, f * 0.5), false, 2.0)
		draw_circle(rect.position + rect.size * 0.5, rect.size.x * 0.4 * f, Color(col.r, col.g, col.b, f * 0.25))


func _draw_effects() -> void:
	for r in _rings:
		var f := 1.0 - float(r["life"]) / float(r["max_life"])
		var ring_pos := _tile_center_f(r["pos"], Vector2.ZERO)
		draw_arc(ring_pos, float(r["radius"]) * tile_size, 0.0, TAU, 32, Color(r["color"].r, r["color"].g, r["color"].b, (1.0 - f) * 0.7), 3.0 * (1.0 - f) + 1.0, true)
	for b in _bolts:
		var f := float(b["life"]) / float(b["max_life"])
		var a := _tile_center_f(b["a"], Vector2.ZERO)
		var bp := _tile_center_f(b["b"], Vector2.ZERO)
		var segments := 5
		var points := PackedVector2Array()
		for i in range(segments + 1):
			var t := float(i) / float(segments)
			var p := a.lerp(bp, t)
			var dir := bp - a
			var perp := Vector2(-dir.y, dir.x).normalized()
			p += perp * sin(float(b["seed"]) + t * 9.0) * (1.0 - absf(t - 0.5) * 2.0) * 9.0
			points.append(p)
		draw_polyline(points, Color(1, 1, 1, f * 0.75), 2.0, true)
		draw_polyline(points, Color(b["color"].r, b["color"].g, b["color"].b, f * 0.6), 4.0, true)
	for p in _particles:
		var f := clampf(float(p["life"]) / float(p["max_life"]), 0.0, 1.0)
		var col: Color = p["color"]
		draw_circle(_tile_center_f(p["pos"], Vector2.ZERO), float(p["size"]) * tile_size * f, Color(col.r, col.g, col.b, f * 0.85))
