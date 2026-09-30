class_name Palette
extends RefCounted

## Central monochrome + neon palette for Ivory Beats.

const BG := Color("0a0a0e")
const BOARD_BG := Color("0d0d12")
const PANEL := Color(0.055, 0.055, 0.075, 0.94)
const PANEL_EDGE := Color(1.0, 1.0, 1.0, 0.14)

const GRID := Color(1.0, 1.0, 1.0, 0.05)
const GRID_STRONG := Color(1.0, 1.0, 1.0, 0.14)

const TEXT := Color("f5f5f1")
const TEXT_DIM := Color(0.74, 0.74, 0.78, 0.9)
const TEXT_FAINT := Color(0.62, 0.62, 0.67, 0.55)

const TILE_FILL := Color("15151b")
const TILE_EDGE := Color("e9e9e3")
const STRIKE := Color("fbfbf7")
const DANGER := Color("ff3b52")

## Neon accents used only for feedback flashes / lane identity.
const NEON := [
	Color("57e6ff"), # 0 cyan
	Color("c07bff"), # 1 violet
	Color("7dffa8"), # 2 green
	Color("ffcf5c"), # 3 amber
]
