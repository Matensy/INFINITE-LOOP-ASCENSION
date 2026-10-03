class_name PieceCatalog
extends RefCounted
## Classifies connector masks into named piece shapes. Pieces are pure data:
## the shape is fully defined by its mask, the orientation by its rotation.

const SQUARE_NAMES := {
	0b0000: "empty",
	0b0001: "end",
	0b0101: "straight",
	0b0011: "corner",
	0b0111: "tee",
	0b1111: "cross",
}

const HEX_NAMES := {
	0b000000: "empty",
	0b000001: "end",
	0b000011: "bend_sharp",
	0b000101: "bend_wide",
	0b001001: "straight",
	0b000111: "fan",
	0b001011: "hook",
	0b001101: "hook_mirror",
	0b010101: "tri",
	0b001111: "quad_fan",
	0b010111: "quad_split",
	0b011011: "quad_cross",
	0b011111: "penta",
	0b111111: "star",
}


## Human readable shape name for a mask.
static func shape_name(mask: int, dir_count: int) -> String:
	var canon := Topology.canonical(mask, dir_count)
	var table: Dictionary = HEX_NAMES if dir_count == 6 else SQUARE_NAMES
	if table.has(canon):
		return table[canon]
	return "shape_%d" % canon


## Stable integer id of the shape (the canonical mask).
static func shape_id(mask: int, dir_count: int) -> int:
	return Topology.canonical(mask, dir_count)


## True if rotating the piece can change anything.
static func is_rotatable(mask: int, dir_count: int) -> bool:
	return Topology.period(mask, dir_count) > 1


## Histogram of piece shapes in a puzzle's solution, keyed by shape name.
static func histogram(puzzle: Puzzle) -> Dictionary:
	var hist := {}
	var n := puzzle.topology.dir_count
	for c in puzzle.cell_count():
		if puzzle.active[c] == 0:
			continue
		var key := shape_name(puzzle.masks[c], n)
		hist[key] = int(hist.get(key, 0)) + 1
	return hist
