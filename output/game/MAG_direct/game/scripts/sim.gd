## Pure, headless model of one magnetic chamber.
##
## The rules are deliberately tiny so every consequence is predictable:
##
##  * Metal crates are inert. They are shoved one tile at a time and can chain
##    into each other. A live hazard consumes them (and is itself shorted out).
##  * Magnets carry a polarity. Push one whose polarity MATCHES the player's
##    field and it is repelled ahead of you, passing the shove on to whatever
##    it strikes (same-polarity magnets continue the cascade).
##  * Push one whose polarity OPPOSES you and the two of you swap tiles - a
##    magnetic pull that drops the magnet onto the tile you just left.
##  * The player is destroyed by nothing, but cannot enter a live hazard.
##  * Every plate sharing a gate's letter must be held down at once.
class_name MagnetSim
extends RefCounted

const WALL := "#"
const VOID := "~"
const HAZARD := "x"
const EXIT := "E"
const SWITCH := "*"
const FLOOR := "."

const GATE_LETTERS := ["A", "B", "C", "D"]
const PLATE_LETTERS := ["a", "b", "c", "d"]

enum Entry { BLOCKED, FREE, DESTROY }

var width: int = 0
var height: int = 0
var tiles: Dictionary = {}          # Vector2i -> single-char String
var player: Vector2i = Vector2i.ZERO
var polarity: String = "N"          # "N" (red) or "S" (blue)
var items: Dictionary = {}          # Vector2i -> {"kind": String, "pol": String}
var inert: Dictionary = {}          # Vector2i -> true (hazard shorted out)

# --- construction ------------------------------------------------------------

func load_level(level: Dictionary) -> void:
	width = 0
	height = 0
	tiles.clear()
	items.clear()
	inert.clear()
	player = Vector2i.ZERO
	polarity = String(level.get("player_polarity", "N"))
	var rows: Array = level.get("map", [])
	height = rows.size()
	for y in range(height):
		var row: String = String(rows[y])
		width = maxi(width, row.length())
	for y in range(height):
		var row: String = String(rows[y])
		for x in range(width):
			var ch := row.substr(x, 1) if x < row.length() else VOID
			var pos := Vector2i(x, y)
			match ch:
				"@":
					player = pos
					tiles[pos] = FLOOR
				"C":
					items[pos] = {"kind": "metal", "pol": ""}
					tiles[pos] = FLOOR
				"R":
					items[pos] = {"kind": "magnet", "pol": "N"}
					tiles[pos] = FLOOR
				"B":
					items[pos] = {"kind": "magnet", "pol": "S"}
					tiles[pos] = FLOOR
				_:
					tiles[pos] = ch


func clone() -> MagnetSim:
	var other := MagnetSim.new()
	other.width = width
	other.height = height
	other.tiles = tiles.duplicate()
	other.player = player
	other.polarity = polarity
	other.items = duplicate_items()
	other.inert = inert.duplicate()
	return other


func duplicate_items() -> Dictionary:
	var out := {}
	for key in items:
		out[key] = (items[key] as Dictionary).duplicate()
	return out


func snapshot() -> Dictionary:
	return {
		"player": player,
		"polarity": polarity,
		"items": duplicate_items(),
		"inert": inert.duplicate(),
	}


func restore(state: Dictionary) -> void:
	player = state["player"]
	polarity = state["polarity"]
	items = (state["items"] as Dictionary).duplicate()
	inert = (state["inert"] as Dictionary).duplicate()


# --- queries -----------------------------------------------------------------

func tile_at(pos: Vector2i) -> String:
	return String(tiles.get(pos, VOID))


func has_tile(pos: Vector2i) -> bool:
	return tiles.has(pos)


func is_walkable_floor(pos: Vector2i) -> bool:
	var t := tile_at(pos)
	return t != WALL and t != VOID


func is_gate_char(c: String) -> bool:
	return GATE_LETTERS.has(c)


func is_plate_char(c: String) -> bool:
	return PLATE_LETTERS.has(c)


func is_live_hazard(pos: Vector2i) -> bool:
	return tile_at(pos) == HAZARD and not inert.has(pos)


func item_at(pos: Vector2i) -> Dictionary:
	return items.get(pos, {})


func occupied(pos: Vector2i) -> bool:
	return items.has(pos)


func plate_pressed(pos: Vector2i) -> bool:
	return items.has(pos) or pos == player


func gate_open(letter: String) -> bool:
	var plate := letter.to_lower()
	var found := false
	for pos in tiles:
		if tile_at(pos) == plate:
			found = true
			if not plate_pressed(pos):
				return false
	return found


func open_gate_letters() -> Array:
	var out := []
	for letter in GATE_LETTERS:
		if _any_gate_tile(letter) and gate_open(letter):
			out.append(letter)
	return out


func _any_gate_tile(letter: String) -> bool:
	for pos in tiles:
		if tile_at(pos) == letter:
			return true
	return false


func gate_positions(letter: String) -> Array:
	var out := []
	for pos in tiles:
		if tile_at(pos) == letter:
			out.append(pos)
	return out


func plate_positions(letter: String) -> Array:
	var out := []
	for pos in tiles:
		if tile_at(pos) == letter:
			out.append(pos)
	return out


func player_can_enter(pos: Vector2i) -> bool:
	var t := tile_at(pos)
	if t == WALL or t == VOID:
		return false
	if is_gate_char(t) and not gate_open(t):
		return false
	if t == HAZARD and not inert.has(pos):
		return false
	return true


## Where an object (crate or magnet) can go.
func object_entry(pos: Vector2i) -> Entry:
	var t := tile_at(pos)
	if t == WALL or t == VOID:
		return Entry.BLOCKED
	if is_gate_char(t) and not gate_open(t):
		return Entry.BLOCKED
	if t == EXIT:
		return Entry.BLOCKED          # the airlock refuses solid matter
	if t == HAZARD and not inert.has(pos):
		return Entry.DESTROY
	return Entry.FREE


# --- movement ----------------------------------------------------------------

## Repel `start` one tile along `dir`, cascading through whatever it strikes.
## Returns null when the shove cannot resolve, otherwise a description of the
## group move.
func resolve_push(start: Vector2i, dir: Vector2i) -> Variant:
	var moves: Array = []
	var destroys: Array = []
	var pos: Vector2i = start
	var kind: Dictionary = items[pos]
	while true:
		var nxt := pos + dir
		var entry := object_entry(nxt)
		if entry == Entry.BLOCKED:
			return null
		if entry == Entry.DESTROY:
			destroys.append({"at": pos, "item": kind, "dest": nxt})
			break
		var other: Dictionary = items.get(nxt, {})
		if other.is_empty():
			moves.append({"from": pos, "to": nxt})
			break
		var verdict := _chain_verdict(kind, other)
		if verdict == "block":
			return null
		moves.append({"from": pos, "to": nxt})
		pos = nxt
		kind = other
	return {"moves": moves, "destroys": destroys}


func _chain_verdict(cur: Dictionary, other: Dictionary) -> String:
	if String(cur.get("kind")) == "metal":
		# Inert steel can only shove more steel - a magnet stops it dead.
		return "continue" if String(other.get("kind")) == "metal" else "block"
	if String(other.get("kind")) == "metal":
		return "continue"
	return "continue" if String(other.get("pol")) == String(cur.get("pol")) else "block"


## Attempt to move the player. Returns a result dictionary; `ok` tells whether
## anything happened. The result doubles as an animation/audio cue sheet.
func try_move(dir: Vector2i) -> Dictionary:
	var result := {
		"ok": false,
		"reason": "",
		"player_from": player,
		"player_to": player,
		"moves": [],
		"destroys": [],
		"cleared": [],
		"swapped": false,
		"cascaded": false,
		"flipped": false,
		"gates_opened": [],
		"gates_closed": [],
		"reached_exit": false,
	}
	var gates_before := open_gate_letters()
	var target := player + dir

	var t := tile_at(target)
	if t == WALL or t == VOID:
		result["reason"] = "wall"
		return result
	if is_gate_char(t) and not gate_open(t):
		result["reason"] = "sealed"
		return result
	if t == HAZARD and not inert.has(target):
		result["reason"] = "hazard"
		return result

	var occupant: Dictionary = items.get(target, {})
	if not occupant.is_empty():
		var is_repelled := String(occupant.get("kind")) == "metal" \
			or String(occupant.get("pol")) == polarity
		if is_repelled:
			var push: Variant = resolve_push(target, dir)
			if push == null:
				result["reason"] = "blocked"
				return result
			result["moves"] = push["moves"]
			result["destroys"] = push["destroys"]
			if push["moves"].size() > 1:
				result["cascaded"] = true
			_apply_moves(push["moves"])
			_apply_destroys(push["destroys"], result)
		else:
			# Opposite polarity: the two of you trade tiles.
			items.erase(target)
			items[player] = occupant
			result["swapped"] = true
			result["moves"].append({"from": target, "to": player})

	result["player_from"] = player
	player = target
	result["player_to"] = target
	result["ok"] = true

	if tile_at(player) == SWITCH:
		polarity = "S" if polarity == "N" else "N"
		result["flipped"] = true

	var gates_after := open_gate_letters()
	for letter in gates_after:
		if not gates_before.has(letter):
			result["gates_opened"].append(letter)
	for letter in gates_before:
		if not gates_after.has(letter):
			result["gates_closed"].append(letter)

	result["reached_exit"] = tile_at(player) == EXIT
	return result


func _apply_moves(moves: Array) -> void:
	var staged: Array = []
	for move in moves:
		staged.append({"to": move["to"], "item": items[move["from"]]})
	for move in moves:
		items.erase(move["from"])
	for entry in staged:
		items[entry["to"]] = entry["item"]


func _apply_destroys(destroys: Array, result: Dictionary) -> void:
	for entry in destroys:
		var at: Vector2i = entry["at"]
		var item: Dictionary = entry["item"]
		if items.get(at, {}) == item:
			items.erase(at)
		if String(item.get("kind")) == "metal":
			# Molten steel welds the hazard shut - the corridor is safe forever.
			inert[entry["dest"]] = true
			result["cleared"].append(entry["dest"])
		else:
			result["destroyed_at"] = entry["dest"]


## Distance-free utility used by hints: is the chamber already solved?
func solved() -> bool:
	return tile_at(player) == EXIT
