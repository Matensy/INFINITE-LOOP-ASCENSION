class_name BoardState
extends RefCounted
## Mutable play state of a puzzle: the current rotation of every tile.

var puzzle: Puzzle
var rot: PackedInt32Array = PackedInt32Array()
var _masks: PackedInt32Array = PackedInt32Array()


func _init(p: Puzzle, rotations: PackedInt32Array = PackedInt32Array()) -> void:
	puzzle = p
	if rotations.size() == p.cell_count():
		rot = rotations.duplicate()
	else:
		rot = p.start_rot.duplicate()
	_normalize()
	_masks = Validator.current_masks(puzzle, rot)


func _normalize() -> void:
	var dc := puzzle.dir_count()
	for c in rot.size():
		rot[c] = posmod(rot[c], dc)


func mask(cell: int) -> int:
	return _masks[cell]


func masks() -> PackedInt32Array:
	return _masks


## Cells that rotate together with `cell` (its link group, or itself).
func group_of(cell: int) -> PackedInt32Array:
	var g := puzzle.link_of[cell] if puzzle.link_of.size() > 0 else -1
	if g >= 0:
		return puzzle.link_groups[g]
	return PackedInt32Array([cell])


func can_rotate(cell: int) -> bool:
	return cell >= 0 and cell < puzzle.cell_count() and puzzle.active[cell] == 1 and puzzle.locked[cell] == 0


## Rotates a tile (and its link group) by `steps` clockwise steps (negative
## for counter-clockwise). Returns the cells that changed; empty if refused.
func rotate(cell: int, steps: int) -> PackedInt32Array:
	if not can_rotate(cell) or steps == 0:
		return PackedInt32Array()
	var dc := puzzle.dir_count()
	var changed := group_of(cell)
	for c in changed:
		rot[c] = posmod(rot[c] + steps, dc)
		_masks[c] = Topology.rotate_mask(puzzle.masks[c], rot[c], dc)
	return changed


func set_rotation(cell: int, value: int) -> void:
	var dc := puzzle.dir_count()
	rot[cell] = posmod(value, dc)
	_masks[cell] = Topology.rotate_mask(puzzle.masks[cell], rot[cell], dc)


func reset() -> void:
	rot = puzzle.start_rot.duplicate()
	_normalize()
	_masks = Validator.current_masks(puzzle, rot)


func is_solved() -> bool:
	return Validator.is_solved(puzzle, _masks)


## True when the tile already shows the same mask it has in `target`.
func matches(cell: int, target_rot: int) -> bool:
	return _masks[cell] == puzzle.mask_at(cell, target_rot)


## Minimum single-step taps needed to turn `cell` from its current rotation
## to `target_rot` (counter-clockwise taps allowed).
func distance_to(cell: int, target_rot: int) -> int:
	var period := puzzle.period_of(cell)
	var diff := posmod(target_rot - rot[cell], period)
	return mini(diff, period - diff)


func snapshot() -> PackedInt32Array:
	return rot.duplicate()
