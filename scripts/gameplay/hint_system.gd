class_name HintSystem
extends RefCounted
## Progressive hints that never simply "solve everything" until asked:
##   1  highlight a problematic tile
##   2  show one valid rotation (prefers a logically forced tile)
##   3  fix a small region around a wrong tile
##   4  fix a larger group
##   5  reveal the complete solution
## Hints target the solution closest to the player's current board.

const MAX_LEVEL := 5
const SOLVER_BUDGET := 4000


## Builds a hint. Returns {level, focus, highlight: PackedInt32Array,
## rotations: {cell: rotation}} or {} when the board is already solved.
static func make_hint(level: int, session: GameSession) -> Dictionary:
	var puzzle := session.puzzle
	var state := session.state
	if state.is_solved():
		return {}
	var target := closest_solution(puzzle, state)
	var wrong := wrong_cells(puzzle, state, target)
	if wrong.is_empty():
		return {}
	var lvl := clampi(level, 1, MAX_LEVEL)
	var focus := _pick_focus(puzzle, state, wrong, target)
	var hint := {"level": lvl, "focus": focus, "highlight": PackedInt32Array([focus]), "rotations": {}}
	match lvl:
		1:
			pass
		2:
			hint["rotations"] = _targets(puzzle, PackedInt32Array([focus]), target)
		3:
			hint["rotations"] = _targets(puzzle, _within(puzzle, wrong, focus, 1.2), target)
		4:
			hint["rotations"] = _targets(puzzle, _within(puzzle, wrong, focus, 2.8), target)
		_:
			hint["rotations"] = _targets(puzzle, wrong, target)
	if lvl >= 2:
		var cells := PackedInt32Array()
		for k in (hint["rotations"] as Dictionary).keys():
			cells.append(int(k))
		hint["highlight"] = cells
	return hint


## Solution that keeps as many of the player's current rotations as the
## search order allows. Falls back to the generator's stored solution.
static func closest_solution(puzzle: Puzzle, state: BoardState) -> PackedInt32Array:
	var res := PuzzleSolver.new(puzzle).solve(1, SOLVER_BUDGET, state.rot)
	var sols: Array = res.get("solutions", [])
	if not sols.is_empty():
		return sols[0]
	return puzzle.solution_rotations()


static func wrong_cells(puzzle: Puzzle, state: BoardState, target: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in puzzle.cell_count():
		if puzzle.active[c] == 1 and puzzle.locked[c] == 0 and not state.matches(c, target[c]):
			out.append(c)
	return out


## Prefers a wrong tile whose orientation is logically forced (a real
## deduction the player could have made), then one with a dangling connector.
static func _pick_focus(puzzle: Puzzle, state: BoardState, wrong: PackedInt32Array, target: PackedInt32Array) -> int:
	var forced := PuzzleSolver.new(puzzle).forced_rotations()
	var best := wrong[0]
	var best_score := -1
	var matched := Connectivity.matched_mask(puzzle, state.masks())
	for c in wrong:
		var score := 0
		if forced[c] >= 0 and puzzle.mask_at(c, forced[c]) == puzzle.mask_at(c, target[c]):
			score += 4
		if matched[c] != state.mask(c):
			score += 2
		if puzzle.link_of[c] < 0:
			score += 1
		if score > best_score:
			best_score = score
			best = c
	return best


static func _within(puzzle: Puzzle, wrong: PackedInt32Array, focus: int, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var topo := puzzle.topology
	var centre := topo.cell_center(focus)
	var scale := topo.apothem() * 2.0
	for c in wrong:
		if topo.cell_center(c).distance_to(centre) <= radius * scale:
			out.append(c)
	return out


static func _targets(puzzle: Puzzle, cells: PackedInt32Array, target: PackedInt32Array) -> Dictionary:
	var out := {}
	for c in cells:
		out[c] = target[c]
		var g := puzzle.link_of[c]
		if g >= 0:
			for m in puzzle.link_groups[g]:
				out[m] = target[m]
	return out
