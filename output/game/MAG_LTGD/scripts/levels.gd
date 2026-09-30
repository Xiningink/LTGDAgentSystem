extends RefCounted
class_name LevelsData

## Chamber definitions for Puzzle Magnet Lab.
##
## Legend used by the row strings:
##   #  wall            .  floor           o  iron block (immovable)
##   H  plasma vent     P  pressure plate  S  polarity switch pad
##   G  gate            X  extraction pad  +  charged crate (+ field)
##   -  charged crate (- field)            1  core start (+)  2  core start (-)
##
## "solution" holds one shortest solution (verified with an exhaustive search
## over the exact movement rules implemented in board.gd).

const DATA: Array = [
	{
		"name": "Calibration Bay",
		"hint": "Same fields repel. Walk into the aligned crate to shove it onto the plate, then take the pad.",
		"rows": [
			"##########",
			"#........#",
			"#.1+..Po.#",
			"#........#",
			"#.......X#",
			"##########",
		],
		"solution": ["right", "right", "right", "down", "down", "right", "right", "right"],
	},
	{
		"name": "Attraction",
		"hint": "Opposite fields attract. Keep walking straight away and the crate trails behind you.",
		"rows": [
			"##########",
			"#........#",
			"#.-1...P.#",
			"#........#",
			"#.......X#",
			"##########",
		],
		"solution": ["right", "right", "right", "right", "right", "down", "down"],
	},
	{
		"name": "Sealed Door",
		"hint": "Loaded plates unseal every gate in the chamber.",
		"rows": [
			"###########",
			"#.....#...#",
			"#.1+..#...#",
			"#.....#...#",
			"#..P..G..X#",
			"#.....#...#",
			"###########",
		],
		"solution": ["up", "right", "down", "down", "right", "down", "right", "right", "right", "right", "right"],
	},
	{
		"name": "Polarity Shift",
		"hint": "Switch pads invert the field of whatever crosses them - including you.",
		"rows": [
			"############",
			"#..........#",
			"#.1.S.-..P.#",
			"#........#.#",
			"#.......GX##",
			"############",
		],
		"solution": ["right", "right", "right", "right", "right", "right", "down", "down", "right"],
	},
	{
		"name": "Hazard Protocol",
		"hint": "Plasma vents destroy crates and the core. Line up the drag path clear of them.",
		"rows": [
			"###########",
			"#.........#",
			"#.-1......#",
			"#.HH......#",
			"#.HH......#",
			"#.........#",
			"#..P......#",
			"#........##",
			"#....#..GX#",
			"###########",
		],
		"solution": ["right", "right", "down", "left", "down", "down", "down", "down", "left", "up",
			"left", "down", "right", "right", "right", "right", "down", "right", "right", "right"],
	},
	{
		"name": "Switchback",
		"hint": "A crate that crosses a switch pad flips too. Push it on, take the long way, drag it off.",
		"rows": [
			"#############",
			"#...........#",
			"#.1+.S....P.#",
			"#...........#",
			"#...........#",
			"#.....#...X.#",
			"#############",
		],
		"solution": ["right", "right", "up", "right", "right", "down", "right", "right", "right",
			"right", "right", "down", "down", "down", "left"],
	},
	{
		"name": "Chain Reaction",
		"hint": "Aligned crates pass force along: one push can drive a whole line onto three plates.",
		"rows": [
			"############",
			"#..........#",
			"#.1+++..PPP#",
			"#..........#",
			"#.........X#",
			"############",
		],
		"solution": ["right", "right", "right", "right", "right", "down", "down", "right", "right", "right"],
	},
	{
		"name": "Locked Quarters",
		"hint": "Two plates, two crates. Route the whole plan before you commit a single turn.",
		"rows": [
			"#############",
			"#...........#",
			"#.1+...-....#",
			"#...........#",
			"#..P.....P..#",
			"#...........#",
			"#.....#G#...#",
			"#.....#X#...#",
			"#############",
		],
		"solution": ["up", "right", "down", "down", "right", "right", "right", "right", "down", "down",
			"right", "up", "right", "right", "down", "left", "left", "left", "down", "down"],
	},
	{
		"name": "Crossfire",
		"hint": "Push, drag, dodge. Vents cut the chamber in half, so pick your lanes early.",
		"rows": [
			"###########",
			"#.........#",
			"#.1+....-.#",
			"#...HH....#",
			"#.........#",
			"#..P...P.##",
			"#.......GX#",
			"###########",
		],
		"solution": ["up", "right", "down", "down", "down", "up", "up", "right", "right", "right",
			"right", "left", "down", "right", "down", "down", "down", "right", "right"],
	},
	{
		"name": "The Containment Core",
		"hint": "Everything at once: push, drag, swap fields on the pad, and thread the vents.",
		"rows": [
			"#############",
			"#...........#",
			"#.1+....+...#",
			"#....S......#",
			"#..H.....H..#",
			"#..P.....P..#",
			"#.....##G##.#",
			"#......#X#..#",
			"#############",
		],
		"solution": ["right", "up", "right", "down", "down", "down", "right", "down", "left", "up",
			"up", "up", "up", "right", "right", "right", "right", "down", "down", "down",
			"left", "down", "right", "down", "down"],
	},
]


static func count() -> int:
	return DATA.size()


static func get_level(index: int) -> Dictionary:
	return DATA[clampi(index, 0, DATA.size() - 1)]


static func slug(index: int) -> String:
	var n: String = String(DATA[index]["name"]).to_lower()
	var out := ""
	for ch in n:
		if ch >= "a" and ch <= "z":
			out += ch
		elif ch >= "0" and ch <= "9":
			out += ch
		elif out.length() > 0 and out[out.length() - 1] != "_":
			out += "_"
	return out.strip_edges().trim_suffix("_")
