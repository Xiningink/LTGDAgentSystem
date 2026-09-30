## Shared colour language for Puzzle Magnet Lab.
##
## Every screen and the board renderer pull from here so the laboratory reads
## as one consistent place.
class_name Palette
extends RefCounted

# --- shell -------------------------------------------------------------------
const BG_TOP := Color("0b1020")
const BG_BOTTOM := Color("05070f")
const PANEL := Color("131c2e")
const PANEL_SOFT := Color("182339")
const PANEL_EDGE := Color("2a3a58")
const PANEL_EDGE_HOT := Color("49e0d0")

# --- board -------------------------------------------------------------------
const FLOOR_A := Color("161f36")
const FLOOR_B := Color("1a2440")
const FLOOR_EDGE := Color("26334f")
const VOID := Color("0a0f1c")

const WALL_TOP := Color("44587f")
const WALL_BODY := Color("1d2740")
const WALL_EDGE := Color("63779f")

const NORTH := Color("ff4d6a")
const NORTH_DEEP := Color("8e1f36")
const SOUTH := Color("3d8bff")
const SOUTH_DEEP := Color("1c4a9c")

const METAL := Color("9aa9c0")
const METAL_DEEP := Color("59677f")
const METAL_EDGE := Color("c3cfe0")

const PLATE := Color("ffb545")
const PLATE_DEEP := Color("6d4a18")

const GATE := Color("ffd166")
const GATE_DEEP := Color("7a5a1c")

const HAZARD := Color("ff2d6f")
const HAZARD_DEEP := Color("5d0f2c")
const HAZARD_DEAD := Color("3a2634")

const EXIT := Color("46e6a0")
const EXIT_DEEP := Color("0f5a44")

const PLAYER_CORE := Color("eaf4ff")
const SWITCH := Color("49e0d0")
const SWITCH_DEEP := Color("14615f")

# --- type --------------------------------------------------------------------
const TEXT := Color("dce7f7")
const TEXT_DIM := Color("8b9ab5")
const TEXT_FAINT := Color("5b6880")
const TEXT_DARK := Color("0b1020")
const GOLD := Color("ffc857")


static func polarity_color(pol: String) -> Color:
	return NORTH if pol == "N" else SOUTH


static func polarity_deep(pol: String) -> Color:
	return NORTH_DEEP if pol == "N" else SOUTH_DEEP


static func polarity_label(pol: String) -> String:
	return "NORTH" if pol == "N" else "SOUTH"


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## Slight vertical gradient imitation: returns a lightened copy.
static func lighten(c: Color, amount: float) -> Color:
	return c.lerp(Color.WHITE, amount)


static func darken(c: Color, amount: float) -> Color:
	return c.lerp(Color.BLACK, amount)
