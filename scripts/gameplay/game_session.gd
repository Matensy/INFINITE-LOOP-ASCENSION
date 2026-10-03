class_name GameSession
extends RefCounted
## One play-through of a puzzle: moves, undo, timer, hints, pins and the
## replay log. Pure logic (no nodes), so it is fully unit testable.

signal tiles_changed(cells: PackedInt32Array, steps: int)
signal solved_changed(solved: bool)

const MAX_UNDO := 2048

var puzzle: Puzzle
var request: PuzzleRequest
var state: BoardState
var moves: int = 0
var elapsed: float = 0.0
var hints_used: int = 0
var max_hint_level: int = 0
var mistakes: int = 0
var undos: int = 0
var resets: int = 0
var solved: bool = false
var paused: bool = false
## Cells the player marked as "done" (double tap). Pinned cells ignore taps.
var pinned: PackedByteArray = PackedByteArray()
## Gestures used during the session (for achievements like One Handed).
var gestures: Dictionary = {}

# Undo stack: flattened [cell, steps, ...].
var _undo: PackedInt32Array = PackedInt32Array()
# Replay log: parallel arrays.
var replay_times: PackedFloat32Array = PackedFloat32Array()
var replay_cells: PackedInt32Array = PackedInt32Array()
var replay_steps: PackedInt32Array = PackedInt32Array()


func _init(p: Puzzle, req: PuzzleRequest = null) -> void:
	puzzle = p
	request = req
	state = BoardState.new(p)
	pinned.resize(p.cell_count())
	solved = state.is_solved()


func code() -> String:
	return str(puzzle.meta.get("code", ""))


func difficulty() -> float:
	return float(puzzle.meta.get("difficulty", 0.0))


func tick(delta: float) -> void:
	if not solved and not paused:
		elapsed += delta


## Player rotation. Returns {refused, changed, matched_delta, solved}.
func rotate(cell: int, steps: int = 1) -> Dictionary:
	var result := {"refused": true, "changed": PackedInt32Array(), "matched_delta": 0, "solved": solved}
	if solved or cell < 0 or cell >= puzzle.cell_count():
		return result
	if pinned[cell] == 1 or not state.can_rotate(cell):
		return result
	var group := state.group_of(cell)
	var before := _matched_around(group)
	var was_correct := puzzle.unique and _group_correct(group)
	var changed := state.rotate(cell, steps)
	if changed.is_empty():
		return result
	moves += 1
	_push_undo(cell, steps)
	replay_times.append(elapsed)
	replay_cells.append(cell)
	replay_steps.append(steps)
	if was_correct and not _group_correct(group):
		mistakes += 1
	result["refused"] = false
	result["changed"] = changed
	result["matched_delta"] = _matched_around(group) - before
	_check_solved()
	result["solved"] = solved
	tiles_changed.emit(changed, steps)
	return result


func undo() -> PackedInt32Array:
	if solved or _undo.size() < 2:
		return PackedInt32Array()
	var steps := _undo[_undo.size() - 1]
	var cell := _undo[_undo.size() - 2]
	_undo.resize(_undo.size() - 2)
	var changed := state.rotate(cell, -steps)
	undos += 1
	replay_times.append(elapsed)
	replay_cells.append(cell)
	replay_steps.append(-steps)
	_check_solved()
	tiles_changed.emit(changed, -steps)
	return changed


func can_undo() -> bool:
	return not solved and _undo.size() >= 2


func reset() -> void:
	if solved:
		return
	state.reset()
	_undo.clear()
	pinned.fill(0)
	resets += 1
	replay_times.append(elapsed)
	replay_cells.append(-1)
	replay_steps.append(0)
	_check_solved()
	var all := PackedInt32Array()
	for c in puzzle.cell_count():
		if puzzle.active[c] == 1:
			all.append(c)
	tiles_changed.emit(all, 0)


func toggle_pin(cell: int) -> bool:
	if cell < 0 or cell >= puzzle.cell_count() or puzzle.active[cell] == 0:
		return false
	pinned[cell] = 1 - pinned[cell]
	return pinned[cell] == 1


## Applies a hint computed by HintSystem: rotates the listed cells to their
## target rotations. Hint moves are not counted as player moves.
func apply_hint(hint: Dictionary) -> PackedInt32Array:
	var level: int = hint.get("level", 1)
	hints_used += 1
	max_hint_level = maxi(max_hint_level, level)
	var changed := PackedInt32Array()
	var targets: Dictionary = hint.get("rotations", {})
	var dc := puzzle.dir_count()
	var done_groups := {}
	for key in targets.keys():
		var cell := int(key)
		var g := puzzle.link_of[cell]
		if g >= 0:
			if done_groups.has(g):
				continue
			done_groups[g] = true
		var steps := posmod(int(targets[key]) - state.rot[cell], dc)
		if steps == 0:
			continue
		if steps > dc / 2:
			steps -= dc
		pinned[cell] = 0
		var ch := state.rotate(cell, steps)
		changed.append_array(ch)
		replay_times.append(elapsed)
		replay_cells.append(cell)
		replay_steps.append(steps)
	_check_solved()
	if not changed.is_empty():
		tiles_changed.emit(changed, 1)
	return changed


## Rating used by stats: solved with no hints and at most the minimum taps.
func is_perfect() -> bool:
	return solved and hints_used == 0 and moves <= int(puzzle.meta.get("min_moves", 0))


func _check_solved() -> void:
	var now := state.is_solved()
	if now != solved:
		solved = now
		solved_changed.emit(solved)


func _push_undo(cell: int, steps: int) -> void:
	_undo.append(cell)
	_undo.append(steps)
	if _undo.size() > MAX_UNDO * 2:
		_undo = _undo.slice(_undo.size() - MAX_UNDO * 2)


func _group_correct(group: PackedInt32Array) -> bool:
	for c in group:
		if not state.matches(c, 0):
			return false
	return true


## Number of matched connector pairs touching the given cells.
func _matched_around(cells: PackedInt32Array) -> int:
	var count := 0
	var dc := puzzle.dir_count()
	var topo := puzzle.topology
	for c in cells:
		var m := state.mask(c)
		for d in dc:
			if (m >> d) & 1 == 0:
				continue
			var other := puzzle.nbr[c * dc + d]
			if other >= 0 and (state.mask(other) >> topo.opposite(d)) & 1 == 1:
				count += 1
	return count


# --- Persistence ----------------------------------------------------------

func to_save() -> Dictionary:
	return {
		"request": request.to_dict() if request else {},
		"fingerprint": puzzle.meta.get("fingerprint", ""),
		"rot": Array(state.rot),
		"moves": moves,
		"elapsed": elapsed,
		"hints": hints_used,
		"max_hint": max_hint_level,
		"mistakes": mistakes,
		"undos": undos,
		"resets": resets,
		"pinned": Marshalls.raw_to_base64(pinned),
		"undo": Array(_undo),
	}


## Restores progress saved by to_save() onto a regenerated puzzle. Returns
## false if the saved data does not belong to this puzzle.
func restore(data: Dictionary) -> bool:
	if str(data.get("fingerprint", "")) != str(puzzle.meta.get("fingerprint", "")):
		return false
	var rot := PackedInt32Array(data.get("rot", []))
	if rot.size() != puzzle.cell_count():
		return false
	for c in rot.size():
		if puzzle.locked[c] == 1:
			rot[c] = puzzle.start_rot[c]
	state = BoardState.new(puzzle, rot)
	moves = int(data.get("moves", 0))
	elapsed = float(data.get("elapsed", 0.0))
	hints_used = int(data.get("hints", 0))
	max_hint_level = int(data.get("max_hint", 0))
	mistakes = int(data.get("mistakes", 0))
	undos = int(data.get("undos", 0))
	resets = int(data.get("resets", 0))
	var pins := Marshalls.base64_to_raw(str(data.get("pinned", "")))
	if pins.size() == puzzle.cell_count():
		pinned = pins
	var undo_data := PackedInt32Array(data.get("undo", []))
	if undo_data.size() % 2 == 0:
		_undo = undo_data
	solved = state.is_solved()
	return true
