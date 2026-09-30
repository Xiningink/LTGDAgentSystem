extends Node2D
class_name BoardView

## Renders a Board and animates the results of each turn.

const Ui := preload("res://scripts/ui_kit.gd")
const AssetLib := preload("res://scripts/assets.gd")

var board = null
var tile := 56.0
var origin := Vector2.ZERO
var powered := true

var _time := 0.0
var _disp := {}                 ## crate id -> pixel centre
var _core_disp := Vector2.ZERO
var _core_ready := false
var _particles: Array = []
var _shake := 0.0
var _beam: Array = []           ## transient field beams
var _flash := 0.0
var _flash_color := Color.WHITE


func setup(b: Variant) -> void:
	board = b
	_disp.clear()
	_particles.clear()
	_beam.clear()
	_shake = 0.0
	_flash = 0.0
	_core_ready = false
	if board != null:
		powered = board.is_powered()
		fit(Vector2(1152.0, 540.0))


func fit(area: Vector2) -> void:
	if board == null or board.width <= 0 or board.height <= 0:
		return
	var t: float = minf(area.x / float(board.width), area.y / float(board.height))
	tile = clampf(floorf(t), 18.0, 96.0)
	var board_size := Vector2(float(board.width), float(board.height)) * tile
	origin = ((area - board_size) * 0.5).floor()


func cell_center(cell: Vector2i) -> Vector2:
	return origin + Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) * tile


func cell_rect(cell: Vector2i, inset: float = 0.0) -> Rect2:
	return Rect2(origin + Vector2(cell) * tile + Vector2(inset, inset),
		Vector2(tile, tile) - Vector2(inset * 2.0, inset * 2.0))


func _process(delta: float) -> void:
	if board == null:
		return
	_time += delta
	_shake = maxf(0.0, _shake - delta * 26.0)
	_flash = maxf(0.0, _flash - delta * 2.4)
	_update_display(delta)
	_update_particles(delta)
	queue_redraw()


func _update_display(delta: float) -> void:
	var k := 1.0 - exp(-delta * 26.0)
	var alive := {}
	for c in board.crates:
		alive[c.id] = true
		var target := cell_center(c.pos)
		if not _disp.has(c.id):
			_disp[c.id] = target
		else:
			var cur: Vector2 = _disp[c.id]
			_disp[c.id] = cur if cur.distance_to(target) < 0.4 else cur.lerp(target, k)
	for id in _disp.keys():
		if not alive.has(id):
			_disp.erase(id)
	var core_target := cell_center(board.player_pos)
	if not _core_ready:
		_core_disp = core_target
		_core_ready = true
	else:
		_core_disp = _core_disp if _core_disp.distance_to(core_target) < 0.4 else _core_disp.lerp(core_target, k)


# ---------------------------------------------------------------- particles --

func _update_particles(delta: float) -> void:
	var keep: Array = []
	for p in _particles:
		p.life -= delta
		if p.life <= 0.0:
			continue
		p.pos += p.vel * delta
		p.vel *= pow(0.14, delta)
		p.vel.y += p.grav * delta
		p.rot += p.spin * delta
		keep.append(p)
	_particles = keep
	var beams: Array = []
	for b in _beam:
		b.life -= delta
		if b.life > 0.0:
			beams.append(b)
	_beam = beams


func _burst(pos: Vector2, color: Color, count: int, speed: float, size_mul: float = 1.0, tex_path: String = "") -> void:
	var tex: Texture2D = null
	if tex_path != "":
		tex = AssetLib.texture(tex_path)
	for i in count:
		var a := randf() * TAU
		var sp := speed * randf_range(0.35, 1.0)
		_particles.append({
			"pos": pos + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)),
			"vel": Vector2(cos(a), sin(a)) * sp,
			"life": randf_range(0.28, 0.7),
			"max": 0.7,
			"size": tile * randf_range(0.10, 0.24) * size_mul,
			"color": color,
			"tex": tex,
			"grav": randf_range(30.0, 140.0),
			"spin": randf_range(-6.0, 6.0),
			"rot": randf() * TAU,
			"kind": "spark",
		})


func _ring(pos: Vector2, color: Color, radius: float, life: float = 0.45, width: float = 3.0) -> void:
	_particles.append({
		"pos": pos, "vel": Vector2.ZERO, "life": life, "max": life,
		"size": radius, "color": color, "tex": null, "grav": 0.0,
		"spin": 0.0, "rot": 0.0, "kind": "ring", "width": width,
	})


func _smoke(pos: Vector2, color: Color, count: int) -> void:
	var tex := AssetLib.texture(AssetLib.P_SMOKE)
	for i in count:
		_particles.append({
			"pos": pos + Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0)),
			"vel": Vector2(randf_range(-30.0, 30.0), randf_range(-70.0, -20.0)),
			"life": randf_range(0.5, 1.1), "max": 1.1,
			"size": tile * randf_range(0.5, 0.95),
			"color": color, "tex": tex, "grav": -20.0,
			"spin": randf_range(-2.0, 2.0), "rot": randf_range(0.0, TAU), "kind": "smoke",
		})


func apply_events(ev: Dictionary) -> void:
	if board == null:
		return
	if ev.get("destroyed", []).size() > 0:
		for c in ev.destroyed:
			var p := cell_center(c.pos)
			_burst(p, Color(1.0, 0.55, 0.2), 16, 190.0, 1.1, AssetLib.P_FLARE)
			_burst(p, Color(1.0, 0.85, 0.4), 8, 120.0, 0.7)
			_smoke(p, Color(0.35, 0.3, 0.3, 0.55), 6)
			_ring(p, Color(1.0, 0.6, 0.25, 0.9), tile * 0.7, 0.4, 4.0)
		_shake = 9.0
		_flash = 0.5
		_flash_color = Color(1.0, 0.5, 0.2)
		Sfx.play("hazard", 2.0)
	if ev.get("death", false):
		var p2 := cell_center(board.player_pos)
		_burst(p2, Color(1.0, 0.4, 0.25), 26, 250.0, 1.4, AssetLib.P_FLARE)
		_smoke(p2, Color(0.25, 0.22, 0.22, 0.6), 10)
		_ring(p2, Color(1.0, 0.45, 0.3, 0.95), tile * 1.4, 0.6, 6.0)
		_shake = 16.0
		_flash = 1.0
		_flash_color = Color(1.0, 0.25, 0.2)
		Sfx.play("fail", 3.0)
	if ev.get("push", 0) > 0:
		var cells: Array = ev.cells
		if cells.size() > 0:
			var last: Vector2i = cells[cells.size() - 1]
			_burst(cell_center(last), Color(0.85, 0.93, 1.0), 5, 90.0, 0.55, AssetLib.P_SPARK)
		_shake = maxf(_shake, 3.0)
		Sfx.play("push", -1.0, 1.0 + 0.06 * float(ev.push))
	if ev.get("pull", false):
		Sfx.play("pull", -3.0)
	if ev.get("bump", false):
		var cells2: Array = ev.cells
		if cells2.size() > 0:
			var c: Vector2i = cells2[0]
			_ring(cell_center(c), Color(1.0, 0.85, 0.5, 0.8), tile * 0.42, 0.25, 3.0)
			_burst(cell_center(c), Color(1.0, 0.8, 0.45), 4, 70.0, 0.4)
		_shake = maxf(_shake, 4.0)
		Sfx.play("bump" if not ev.get("repel", false) else "switch", -3.0,
			0.85 if ev.get("repel", false) else 1.0)
	if ev.get("flips", []).size() > 0:
		for cell in ev.flips:
			var pos := cell_center(cell)
			_ring(pos, Ui.ACCENT, tile * 0.6, 0.45, 4.0)
			_burst(pos, Ui.ACCENT, 12, 150.0, 0.8, AssetLib.P_SPARK)
		Sfx.play("flip", 1.0)
	if ev.get("power_changed", false):
		powered = ev.powered
		Sfx.play("exit_on" if ev.powered else "plate_off", 0.0)
		for g in board.gates:
			_ring(cell_center(g), Ui.GOOD if ev.powered else Ui.AMBER, tile * 0.8, 0.5, 4.0)
		if ev.powered:
			_flash = 0.35
			_flash_color = Ui.GOOD
	if ev.get("dormant", false):
		_ring(cell_center(board.exit_cell), Color(1.0, 0.75, 0.35, 0.9), tile * 0.8, 0.5, 4.0)
		Sfx.play("dormant", -1.0)
	if ev.get("win", false):
		var p3 := cell_center(board.exit_cell)
		_ring(p3, Ui.GOOD, tile * 1.1, 0.8, 6.0)
		_burst(p3, Ui.GOOD, 28, 220.0, 1.2, AssetLib.P_SPARK)
		_burst(p3, Color.WHITE, 12, 130.0, 0.8, AssetLib.P_FLARE)
		_flash = 0.7
		_flash_color = Ui.GOOD
		Sfx.play("win", 1.0)


func add_field_beam(from_cell: Vector2i, to_cell: Vector2i, color: Color) -> void:
	_beam.append({
		"from": cell_center(from_cell), "to": cell_center(to_cell),
		"color": color, "life": 0.35, "max": 0.35,
	})


# ------------------------------------------------------------------- drawing --

func _draw() -> void:
	if board == null or board.width <= 0:
		return
	var shake_off := Vector2.ZERO
	if _shake > 0.05:
		shake_off = Vector2(sin(_time * 71.0), cos(_time * 63.0)) * _shake * 0.5
	draw_set_transform(shake_off, 0.0, Vector2.ONE)

	_draw_chamber()
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			if board.is_void(cell):
				continue
			if board.is_iron(cell):
				_draw_iron(cell)
	for cell in board.hazards:
		_draw_hazard(cell)
	for cell in board.plates:
		_draw_plate(cell, board.crate_at(cell) != null)
	for cell in board.switches:
		_draw_switch(cell)
	for cell in board.gates:
		_draw_gate(cell, board.is_powered())
	if board.exit_cell != Vector2i(-1, -1):
		_draw_exit(board.exit_cell, board.is_powered())

	_draw_field_links()
	_draw_beams()
	for c in board.crates:
		_draw_crate(c)
	_draw_core()
	_draw_particles()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _flash > 0.01:
		draw_rect(Rect2(origin - Vector2(tile, tile), Vector2(board.width + 2, board.height + 2) * tile),
			Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash * 0.28), true)


func _draw_chamber() -> void:
	var pad := tile * 0.35
	var area := Rect2(origin - Vector2(pad, pad), Vector2(board.width, board.height) * tile + Vector2(pad, pad) * 2.0)
	draw_rect(area, Color(0.043, 0.06, 0.086, 0.92), true)
	draw_rect(area, Color(Ui.ACCENT.r, Ui.ACCENT.g, Ui.ACCENT.b, 0.20), false, maxf(1.0, tile * 0.04))

	var floor_a := AssetLib.texture(AssetLib.FLOOR_A)
	var floor_b := AssetLib.texture(AssetLib.FLOOR_B)
	var wall_tex := AssetLib.texture(AssetLib.WALL_B)
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			if board.is_void(cell):
				continue
			var rect := cell_rect(cell)
			var ch: String = board.char_at(cell)
			if ch == "#":
				draw_texture_rect(wall_tex, rect, false, Color(0.34, 0.43, 0.58))
				draw_rect(rect, Color(0.62, 0.76, 0.95, 0.22), false, maxf(1.0, tile * 0.03))
				draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 4.0), Vector2(rect.size.x, 4.0)),
					Color(0.0, 0.0, 0.0, 0.26), true)
			else:
				var tex := floor_a if (x + y) % 2 == 0 else floor_b
				var tint := Color(0.50, 0.58, 0.70) if (x + y) % 2 == 0 else Color(0.38, 0.46, 0.58)
				draw_texture_rect(tex, rect, false, tint)
	# chamber outline where the room meets the void
	var edge := Color(Ui.ACCENT.r, Ui.ACCENT.g, Ui.ACCENT.b, 0.55)
	var lw := maxf(1.5, tile * 0.045)
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			if board.is_void(cell):
				continue
			var r := cell_rect(cell)
			if board.is_void(cell + Vector2i(0, -1)):
				draw_line(r.position, r.position + Vector2(r.size.x, 0), edge, lw)
			if board.is_void(cell + Vector2i(0, 1)):
				draw_line(r.position + Vector2(0, r.size.y), r.position + r.size, edge, lw)
			if board.is_void(cell + Vector2i(-1, 0)):
				draw_line(r.position, r.position + Vector2(0, r.size.y), edge, lw)
			if board.is_void(cell + Vector2i(1, 0)):
				draw_line(r.position + Vector2(r.size.x, 0), r.position + r.size, edge, lw)


func _draw_iron(cell: Vector2i) -> void:
	var r := cell_rect(cell, tile * 0.06)
	draw_rect(r, Color(0.13, 0.16, 0.22, 0.95), true)
	draw_rect(r, Color(0.44, 0.54, 0.68, 0.95), false, maxf(2.0, tile * 0.055))
	var inner := r.grow(-tile * 0.17)
	draw_rect(inner, Color(0.26, 0.32, 0.41, 1.0), true)
	draw_rect(inner, Color(0.60, 0.71, 0.86, 0.5), false, maxf(1.0, tile * 0.026))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := inner.get_center() + Vector2(sx, sy) * (inner.size * 0.5 - Vector2(tile * 0.14, tile * 0.14))
			draw_circle(p, maxf(2.0, tile * 0.07), Color(0.68, 0.78, 0.92, 0.85))


func _draw_plate(cell: Vector2i, loaded: bool) -> void:
	var c := cell_center(cell)
	var s := tile * 0.44
	var rect := Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0)
	draw_rect(rect, Color(0.05, 0.07, 0.10, 0.85), true)
	var col := Ui.GOOD if loaded else Color(Ui.ACCENT.r, Ui.ACCENT.g, Ui.ACCENT.b, 0.55)
	var lw := maxf(2.0, tile * 0.05)
	# corner brackets
	var b := s * 0.55
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			var corner := c + Vector2(sign_x * (s - b), sign_y * (s - b))
			draw_line(corner, corner + Vector2(sign_x * b, 0), col, lw)
			draw_line(corner, corner + Vector2(0, sign_y * b), col, lw)
	if loaded:
		var pulse := 0.75 + 0.25 * sin(_time * 5.0)
		draw_circle(c, s * 0.95, Color(col.r, col.g, col.b, 0.16 * pulse))
		draw_circle(c, s * 0.42, col)
		draw_circle(c, s * 0.42, Color(1, 1, 1, 0.35), false, maxf(1.5, tile * 0.04))
	else:
		draw_arc(c, s * 0.42, 0.0, TAU, 24, col, lw)
		draw_circle(c, s * 0.12, Color(col.r, col.g, col.b, 0.7))


func _draw_switch(cell: Vector2i) -> void:
	var c := cell_center(cell)
	var s := tile * 0.4
	var rect := Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0)
	draw_rect(rect, Color(0.06, 0.08, 0.12, 0.9), true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-s, -s), c + Vector2(s, -s), c + Vector2(-s, s)]),
		Color(Ui.POS.r, Ui.POS.g, Ui.POS.b, 0.85))
	draw_colored_polygon(PackedVector2Array([c + Vector2(s, -s), c + Vector2(s, s), c + Vector2(-s, s)]),
		Color(Ui.NEG.r, Ui.NEG.g, Ui.NEG.b, 0.85))
	draw_rect(rect, Color(0.85, 0.92, 1.0, 0.35), false, maxf(1.0, tile * 0.03))
	var a := _time * 1.6
	draw_arc(c, s * 1.25, a, a + PI * 0.75, 18, Color(1, 1, 1, 0.65), maxf(2.0, tile * 0.05))
	draw_arc(c, s * 1.25, a + PI, a + PI * 1.75, 18, Color(1, 1, 1, 0.65), maxf(2.0, tile * 0.05))


func _draw_gate(cell: Vector2i, open: bool) -> void:
	var r := cell_rect(cell, tile * 0.02)
	draw_rect(r, Color(0.05, 0.07, 0.10, 0.92), true)
	var col := Ui.GOOD if open else Ui.AMBER
	draw_rect(r, Color(col.r, col.g, col.b, 0.75), false, maxf(2.0, tile * 0.05))
	if open:
		draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, tile * 0.12)),
			Color(col.r, col.g, col.b, 0.65), true)
		draw_rect(Rect2(r.position + Vector2(2, r.size.y - tile * 0.12 - 2), Vector2(r.size.x - 4, tile * 0.12)),
			Color(col.r, col.g, col.b, 0.65), true)
		draw_circle(cell_center(cell), tile * 0.14, Color(col.r, col.g, col.b, 0.5))
	else:
		var bars := 4
		var h := r.size.y / float(bars)
		for i in bars:
			var bar := Rect2(r.position + Vector2(tile * 0.14, h * float(i) + h * 0.16),
				Vector2(r.size.x - tile * 0.28, h * 0.62))
			draw_rect(bar, Color(1.0, 0.72, 0.38, 0.9), true)
			draw_rect(bar, Color(1.0, 0.9, 0.6, 0.5), false, 1.0)


func _draw_exit(cell: Vector2i, live: bool) -> void:
	var c := cell_center(cell)
	var s := tile * 0.42
	var col := Ui.GOOD if live else Color(0.42, 0.48, 0.58)
	draw_rect(Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), Color(0.02, 0.05, 0.07, 0.85), true)
	var pulse := 0.7 + 0.3 * sin(_time * 3.4)
	if live:
		draw_circle(c, s * 1.5, Color(col.r, col.g, col.b, 0.10 * pulse))
		draw_rect(Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), Color(col.r, col.g, col.b, 0.85), false,
			maxf(2.0, tile * 0.05))
		draw_circle(c, s * 0.5 * pulse, Color(col.r, col.g, col.b, 0.85))
		draw_arc(c, s * 0.72, -PI * 0.5, PI * 0.5, 18, Color(col.r, col.g, col.b, 0.9), maxf(2.0, tile * 0.05))
		var beam := Rect2(c.x - tile * 0.12, c.y - tile * 0.5, tile * 0.24, tile * 0.9)
		draw_rect(beam, Color(col.r, col.g, col.b, 0.10 + 0.06 * pulse), true)
	else:
		draw_rect(Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), Color(col.r, col.g, col.b, 0.5), false,
			maxf(1.5, tile * 0.04))
		draw_arc(c, s * 0.45, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.8), maxf(1.5, tile * 0.04))
		draw_line(c + Vector2(-s * 0.6, s * 0.6), c + Vector2(s * 0.6, -s * 0.6),
			Color(0.95, 0.6, 0.35, 0.85), maxf(1.5, tile * 0.05))


func _draw_hazard(cell: Vector2i) -> void:
	var c := cell_center(cell)
	var s := tile * 0.46
	var pts := PackedVector2Array()
	for i in 6:
		var a := TAU * float(i) / 6.0 + PI / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * s)
	var pulse := 0.55 + 0.45 * sin(_time * 4.0 + float(cell.x) * 0.7)
	draw_circle(c, s * 1.35, Color(1.0, 0.35, 0.15, 0.10 + 0.10 * pulse))
	draw_colored_polygon(pts, Color(0.10, 0.06, 0.09, 0.95))
	for i in 6:
		var a1 := TAU * float(i) / 6.0 + PI / 6.0
		var a2 := TAU * float(i + 1) / 6.0 + PI / 6.0
		draw_line(c + Vector2(cos(a1), sin(a1)) * s, c + Vector2(cos(a2), sin(a2)) * s,
			Color(1.0, 0.42, 0.2, 0.75), maxf(1.5, tile * 0.04))
	for i in 3:
		var t := fmod(_time * 0.8 + float(i) * 0.33, 1.0)
		var flame := Vector2(c.x + sin(t * 8.0 + float(i) * 2.1) * s * 0.3, c.y + s * 0.35 - t * s * 1.0)
		draw_circle(flame, s * 0.16 * (1.0 - t) + s * 0.05, Color(1.0, 0.72, 0.3, 0.75 * (1.0 - t)))
	draw_circle(c, s * 0.22 * pulse, Color(1.0, 0.55, 0.25, 0.85))


func _draw_field_links() -> void:
	if board == null:
		return
	var pc := cell_center(board.player_pos)
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var c: Variant = board.crate_at(board.player_pos + d)
		if c == null:
			continue
		var target := cell_center(c.pos)
		var col := Ui.pol_color(c.pol)
		var attract: bool = int(c.pol) != int(board.player_pol)
		var w := maxf(2.0, tile * 0.06)
		for i in 3:
			var off := Vector2(0.0, float(i - 1) * w * 2.0)
			draw_line(pc + off, target + off, Color(col.r, col.g, col.b, 0.22 if attract else 0.16), w)
		var mid := (pc + target) * 0.5
		draw_circle(mid, w * 1.6, Color(col.r, col.g, col.b, 0.6 if attract else 0.45))


func _draw_beams() -> void:
	for b in _beam:
		var a: float = clampf(b.life / b.max, 0.0, 1.0)
		var col: Color = b.color
		for i in 3:
			var off := Vector2(0.0, float(i - 1) * tile * 0.1)
			draw_line(b["from"] + off, b["to"] + off, Color(col.r, col.g, col.b, 0.55 * a), maxf(2.0, tile * 0.08))


func _draw_crate(c: Dictionary) -> void:
	var center: Vector2 = _disp.get(c.id, cell_center(c.pos))
	var col := Ui.pol_color(c.pol)
	var s := tile * 0.84
	var rect := Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s))
	draw_circle(center, tile * 0.5, Color(col.r, col.g, col.b, 0.12))
	draw_rect(Rect2(rect.position + Vector2(0, tile * 0.06), rect.size), Color(0, 0, 0, 0.30), true)
	draw_texture_rect(AssetLib.texture(AssetLib.CRATE), rect, false, col.lerp(Color(1, 1, 1), 0.30))
	draw_rect(rect, Color(col.r, col.g, col.b, 0.9), false, maxf(2.0, tile * 0.045))
	# polarity glyph
	var g := tile * 0.17
	var lw := maxf(3.0, tile * 0.075)
	draw_circle(center, tile * 0.2, Color(0.04, 0.06, 0.09, 0.55))
	draw_line(center - Vector2(g, 0), center + Vector2(g, 0), Color.WHITE, lw)
	if c.pol > 0:
		draw_line(center - Vector2(0, g), center + Vector2(0, g), Color.WHITE, lw)


func _draw_core() -> void:
	var c := _core_disp
	var col := Ui.pol_color(board.player_pol)
	var r := tile * 0.42
	var pulse := 0.75 + 0.25 * sin(_time * 3.0)
	draw_circle(c, r * 1.7, Color(col.r, col.g, col.b, 0.09 * pulse))
	draw_circle(c, r * 1.22, Color(col.r, col.g, col.b, 0.14))
	draw_arc(c, r * 1.22, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.75), maxf(2.0, tile * 0.06))
	var a := -_time * 2.0
	draw_arc(c, r * 0.98, a, a + PI * 1.2, 20, Color(1, 1, 1, 0.55), maxf(2.0, tile * 0.05))
	draw_arc(c, r * 0.98, a + PI, a + PI * 1.2, 20, Color(1, 1, 1, 0.55), maxf(2.0, tile * 0.05))
	var pts := PackedVector2Array()
	for i in 6:
		var ang := TAU * float(i) / 6.0 + PI / 6.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * r * 0.72)
	draw_colored_polygon(pts, Color(0.05, 0.07, 0.11, 0.98))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(col.r, col.g, col.b, 0.9), maxf(2.0, tile * 0.045))
	var g := tile * 0.16
	var lw := maxf(3.0, tile * 0.075)
	draw_line(c - Vector2(g, 0), c + Vector2(g, 0), col.lightened(0.4), lw)
	if board.player_pol > 0:
		draw_line(c - Vector2(0, g), c + Vector2(0, g), col.lightened(0.4), lw)
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var tip := c + Vector2(d) * r * 1.45
		draw_circle(tip, maxf(2.0, tile * 0.045), Color(col.r, col.g, col.b, 0.85))


func _draw_particles() -> void:
	for p in _particles:
		var a: float = clampf(p.life / p.max, 0.0, 1.0)
		if p.kind == "ring":
			var grow := 1.0 - a
			var radius: float = p.size * (0.35 + 1.15 * grow)
			var col: Color = p.color
			draw_arc(p.pos, radius, 0.0, TAU, 40, Color(col.r, col.g, col.b, col.a * a), p.get("width", 3.0))
		elif p.kind == "smoke":
			var tex: Texture2D = p.tex
			if tex != null:
				var sz: float = p.size * (1.6 - a * 0.6)
				var tr := Transform2D(p.rot, p.pos)
				draw_set_transform_matrix(tr)
				draw_texture_rect(tex, Rect2(Vector2(-sz, -sz) * 0.5, Vector2(sz, sz)), false,
					Color(p.color.r, p.color.g, p.color.b, p.color.a * a * 0.5))
				draw_set_transform_matrix(Transform2D.IDENTITY)
		else:
			var tex2: Texture2D = p.tex
			var sz2: float = p.size * (0.4 + a * 0.9)
			if tex2 != null:
				var tr2 := Transform2D(p.rot, p.pos)
				draw_set_transform_matrix(tr2)
				draw_texture_rect(tex2, Rect2(Vector2(-sz2, -sz2) * 0.5, Vector2(sz2, sz2)), false,
					Color(p.color.r, p.color.g, p.color.b, a))
				draw_set_transform_matrix(Transform2D.IDENTITY)
			else:
				var col2: Color = p.color
				draw_rect(Rect2(p.pos - Vector2(sz2, sz2) * 0.35, Vector2(sz2, sz2) * 0.7),
					Color(col2.r, col2.g, col2.b, a), true)
