extends RefCounted
class_name Board

## Grid model plus the turn resolution rules of Puzzle Magnet Lab.
##
## A turn resolves in this order:
##   1. the core walks one tile (illegal moves are rejected with a bump)
##   2. same-field crates in front are shoved away; the shove chains through
##      every aligned same-field crate
##   3. an opposite-field crate directly behind the core is dragged into the
##      tile the core just left
##   4. any mover that lands on a polarity switch pad flips its field
##   5. plates are read, gates follow, vents kill, the extraction pad opens a win
##
## Keeping the whole ruleset in one tiny deterministic model makes the puzzle
## space searchable and the undo history exact.

const WALL := "#"
const VOID := " "
const IRON := "o"
const FLOOR := "."
const HAZARD := "H"
const PLATE := "P"
const SWITCH := "S"
const GATE := "G"
const EXIT := "X"
const CRATE_POS := "+"
const CRATE_NEG := "-"
const CORE_POS := "1"
const CORE_NEG := "2"

var width := 0
var height := 0

var grid: Array = []                 ## Array of row strings
var crates: Array = []               ## [{id, pos: Vector2i, pol: int}]
var player_pos := Vector2i.ZERO
var player_pol := 1
var move_count := 0
var dead := false
var won := false
var level_index := 0

var history: Array = []
var next_id := 1

var plates: Array = []
var switches: Array = []
var hazards: Array = []
var gates: Array = []
var walls: Array = []
var irons: Array = []
var exit_cell := Vector2i(-1, -1)

var _rows: Array = []


func load_level(rows: Array, index: int = 0) -> void:
	level_index = index
	_rows = rows.duplicate()
	grid = []
	for r in rows:
		grid.append(String(r))
	height = grid.size()
	width = 0
	for r in grid:
		width = maxi(width, String(r).length())

	plates = []
	switches = []
	hazards = []
	gates = []
	walls = []
	irons = []
	crates = []
	history = []
	next_id = 1
	move_count = 0
	dead = false
	won = false
	exit_cell = Vector2i(-1, -1)

	for y in height:
		var row: String = grid[y]
		for x in width:
			var cell := Vector2i(x, y)
			var ch := char_at(cell)
			match ch:
				WALL:
					walls.append(cell)
				VOID:
					pass
				IRON:
					irons.append(cell)
				HAZARD:
					hazards.append(cell)
				PLATE:
					plates.append(cell)
				SWITCH:
					switches.append(cell)
				GATE:
					gates.append(cell)
				EXIT:
					exit_cell = cell
				CRATE_POS:
					_add_crate(cell, 1)
				CRATE_NEG:
					_add_crate(cell, -1)
				CORE_POS:
					player_pos = cell
					player_pol = 1
				CORE_NEG:
					player_pos = cell
					player_pol = -1


func _add_crate(cell: Vector2i, pol: int) -> void:
	crates.append({"id": next_id, "pos": cell, "pol": pol})
	next_id += 1


func char_at(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= height:
		return WALL
	var row: String = grid[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return WALL
	return row[cell.x]


func is_wall(cell: Vector2i) -> bool:
	return char_at(cell) == WALL


func is_void(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= height:
		return true
	var row: String = grid[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return true
	return row[cell.x] == VOID


func is_hazard(cell: Vector2i) -> bool:
	return char_at(cell) == HAZARD


func is_switch(cell: Vector2i) -> bool:
	return char_at(cell) == SWITCH


func is_plate(cell: Vector2i) -> bool:
	return char_at(cell) == PLATE


func is_gate(cell: Vector2i) -> bool:
	return char_at(cell) == GATE


func is_iron(cell: Vector2i) -> bool:
	return char_at(cell) == IRON


func is_open_floor(cell: Vector2i) -> bool:
	var ch := char_at(cell)
	return ch == FLOOR or ch == PLATE or ch == SWITCH or ch == EXIT


func crate_at(cell: Vector2i) -> Variant:
	for c in crates:
		if c.pos == cell:
			return c
	return null


func crate_by_id(id: int) -> Variant:
	for c in crates:
		if c.id == id:
			return c
	return null


## Blocks the core: walls, the void, iron, and closed gates.
func blocks_player(cell: Vector2i, powered: bool) -> bool:
	var ch := char_at(cell)
	if ch == WALL or ch == VOID or ch == IRON:
		return true
	if ch == GATE and not powered:
		return true
	return false


## Blocks a crate: as above, and the extraction pad repels crates so a puzzle
## can never be soft-locked by parking metal on the goal.
func blocks_crate(cell: Vector2i, powered: bool) -> bool:
	if blocks_player(cell, powered):
		return true
	if char_at(cell) == EXIT:
		return true
	return false


func plates_total() -> int:
	return plates.size()


func plates_loaded() -> int:
	var n := 0
	for p in plates:
		if crate_at(p) != null:
			n += 1
	return n


func is_powered() -> bool:
	if plates.is_empty():
		return true
	return plates_loaded() == plates.size()


func unsolvable() -> bool:
	return crates.size() < plates.size()


func snapshot() -> Dictionary:
	var copy: Array = []
	for c in crates:
		copy.append({"id": c.id, "pos": c.pos, "pol": c.pol})
	return {
		"player_pos": player_pos,
		"player_pol": player_pol,
		"crates": copy,
		"move_count": move_count,
		"dead": dead,
		"won": won,
	}


func restore(s: Dictionary) -> void:
	player_pos = s.player_pos
	player_pol = s.player_pol
	move_count = s.move_count
	dead = s.dead
	won = s.won
	crates = []
	for c in s.crates:
		crates.append({"id": c.id, "pos": c.pos, "pol": c.pol})


func can_undo() -> bool:
	return not history.is_empty()


func undo() -> bool:
	if history.is_empty():
		return false
	restore(history.pop_back())
	return true


func reset_level() -> void:
	load_level(_rows, level_index)


## Resolve one player turn. Returns an event dictionary for the view/audio.
func try_move(dir: Vector2i) -> Dictionary:
	var ev := {
		"ok": false,
		"bump": false,
		"repel": false,
		"push": 0,
		"pull": false,
		"destroyed": [],
		"flips": [],
		"power_changed": false,
		"powered": is_powered(),
		"death": false,
		"win": false,
		"dormant": false,
		"cells": [],
	}
	if dead or won or dir == Vector2i.ZERO:
		return ev

	var was_powered := is_powered()
	var target: Vector2i = player_pos + dir
	if blocks_player(target, was_powered):
		ev["bump"] = true
		ev["cells"] = [target]
		return ev

	var first: Variant = crate_at(target)
	var moved: Array = []        # [[crate, new_pos], ...]
	var destroyed: Array = []

	if first != null:
		if first.pol != player_pol:
			# Attraction cannot be pushed - the crate would have to share our tile.
			ev["bump"] = true
			ev["repel"] = true
			ev["cells"] = [target]
			return ev
		var chain: Array = [first]
		var cur: Vector2i = target
		while true:
			var nxt: Vector2i = cur + dir
			var nxt_crate: Variant = crate_at(nxt)
			if nxt_crate != null:
				if nxt_crate.pol != player_pol:
					ev["bump"] = true
					ev["repel"] = true
					ev["cells"] = [nxt]
					return ev
				chain.append(nxt_crate)
				cur = nxt
				continue
			if blocks_crate(nxt, was_powered):
				ev["bump"] = true
				ev["cells"] = [nxt]
				return ev
			break

		ev["push"] = chain.size()
		for i in range(chain.size() - 1, 0 - 1, -1):
			var c: Dictionary = chain[i]
			var np: Vector2i = c.pos + dir
			if is_hazard(np):
				destroyed.append(c)
			else:
				moved.append([c, np])

	history.append(snapshot())

	for pair in moved:
		var c: Dictionary = pair[0]
		c.pos = pair[1]
	for c in destroyed:
		crates.erase(c)

	var old_pos := player_pos
	player_pos = target

	# Drag: an opposite-field crate directly behind the core follows into the
	# tile the core just vacated.
	var pulled: Variant = null
	var pull_dest := Vector2i.ZERO
	var behind: Vector2i = old_pos - dir
	var follower: Variant = crate_at(behind)
	if follower != null and follower.pol != player_pol:
		follower.pos = old_pos
		pulled = follower
		pull_dest = old_pos
		ev["pull"] = true

	# Field flip for every mover that lands on a switch pad.
	var entries: Array = [player_pos]
	for pair in moved:
		entries.append(pair[1])
	if pulled != null:
		entries.append(pull_dest)
	for cell in entries:
		if cell == player_pos:
			if is_switch(cell):
				player_pol = -player_pol
				ev["flips"].append(cell)
		else:
			var c: Variant = crate_at(cell)
			if c != null and is_switch(cell):
				c.pol = -c.pol
				ev["flips"].append(cell)

	move_count += 1
	ev["ok"] = true
	ev["destroyed"] = destroyed
	ev["cells"] = entries

	var now_powered := is_powered()
	if now_powered != was_powered:
		ev["power_changed"] = true
	ev["powered"] = now_powered

	if is_hazard(player_pos):
		dead = true
		ev["death"] = true
		return ev

	if player_pos == exit_cell:
		if now_powered:
			won = true
			ev["win"] = true
		else:
			ev["dormant"] = true

	return ev
