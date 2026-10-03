class_name PuzzleSolver
extends RefCounted
## Independent constraint solver (separate from the generator).
##
## Model: one variable per rotatable unit (a tile, or a whole linked group).
## A variable's options are its distinct orientations. Local edge rules come
## from the RuleSet and are enforced by arc-consistency propagation; forest
## rules (cores, no cycles, no closed core-less islands) are pruned globally.
## Search is depth-first with MRV ordering and an explicit stack, so it is
## deterministic and bounded only by a node budget (never by wall time —
## generation must give identical results on every device).

const MAX_OPTIONS := 6

var puzzle: Puzzle
var rules: RuleSet

var _n := 0
var _dc := 0
var _exclusive := false
var _forest := false
var _single_core := false
var _opp := PackedInt32Array()

var _var_count := 0
var _var_cells: Array[PackedInt32Array] = []
var _var_nbrs: Array[PackedInt32Array] = []
var _var_opts := PackedInt32Array()
var _cell_var := PackedInt32Array()
var _opt_mask := PackedInt32Array()
var _opt_rot := PackedInt32Array()
var _network_total := 0

# Search state (snapshotted on branching).
var _dom := PackedInt32Array()
var _must := PackedInt32Array()
var _may := PackedInt32Array()

# Scratch buffers.
var _queue := PackedInt32Array()
var _in_queue := PackedByteArray()
var _parent := PackedInt32Array()


func _init(p: Puzzle) -> void:
	puzzle = p
	rules = RuleSet.for_mode(p.mode)
	_n = p.cell_count()
	_dc = p.dir_count()
	_exclusive = rules.relation() == RuleSet.RELATION_EXCLUSIVE
	_forest = rules.requires_forest()
	_single_core = _forest and p.cores.size() == 1
	_opp.resize(_dc)
	for d in _dc:
		_opp[d] = p.topology.opposite(d)
	_build_variables()


func _build_variables() -> void:
	_cell_var.resize(_n)
	_cell_var.fill(-1)
	_opt_mask.resize(_n * MAX_OPTIONS)
	_opt_rot.resize(_n * MAX_OPTIONS)
	_var_cells.clear()
	var opts: Array[int] = []
	for group in puzzle.link_groups:
		var v := _var_cells.size()
		_var_cells.append(group)
		var seen := {}
		var count := 0
		for t in _dc:
			var key := PackedInt32Array()
			for c in group:
				key.append(puzzle.mask_at(c, puzzle.start_rot[c] + t))
			var k := str(key)
			if seen.has(k):
				continue
			seen[k] = true
			for i in group.size():
				var c := group[i]
				_opt_mask[c * MAX_OPTIONS + count] = key[i]
				_opt_rot[c * MAX_OPTIONS + count] = posmod(puzzle.start_rot[c] + t, _dc)
			count += 1
		for c in group:
			_cell_var[c] = v
		opts.append(count)
	for c in _n:
		if puzzle.active[c] == 0 or _cell_var[c] >= 0:
			continue
		var v := _var_cells.size()
		_var_cells.append(PackedInt32Array([c]))
		_cell_var[c] = v
		if puzzle.locked[c] == 1:
			_opt_mask[c * MAX_OPTIONS] = puzzle.mask_at(c, puzzle.start_rot[c])
			_opt_rot[c * MAX_OPTIONS] = posmod(puzzle.start_rot[c], _dc)
			opts.append(1)
			continue
		var period := puzzle.period_of(c)
		for k in period:
			_opt_mask[c * MAX_OPTIONS + k] = puzzle.mask_at(c, k)
			_opt_rot[c * MAX_OPTIONS + k] = k
		opts.append(period)
	_var_count = _var_cells.size()
	_var_opts = PackedInt32Array(opts)
	_var_nbrs.clear()
	for v in _var_count:
		var seen := {}
		var list := PackedInt32Array()
		for c in _var_cells[v]:
			for d in _dc:
				var other := puzzle.nbr[c * _dc + d]
				if other < 0:
					continue
				var ov := _cell_var[other]
				if ov != v and not seen.has(ov):
					seen[ov] = true
					list.append(ov)
		_var_nbrs.append(list)
	_network_total = 0
	for c in _n:
		_network_total += puzzle.network_cell[c]
	_in_queue.resize(_var_count)
	_parent.resize(_n)


## Number of variables with more than one option (the real decisions).
func decision_count() -> int:
	var count := 0
	for v in _var_count:
		if _var_opts[v] > 1:
			count += 1
	return count


func _reset_state() -> void:
	_dom.resize(_var_count)
	_must.resize(_n)
	_may.resize(_n)
	_must.fill(0)
	_may.fill(0)
	for v in _var_count:
		_dom[v] = (1 << _var_opts[v]) - 1
		_update_cells(v)


func _update_cells(v: int) -> void:
	var dom := _dom[v]
	for c in _var_cells[v]:
		var all_on := (1 << _dc) - 1
		var any_on := 0
		var bits := dom
		var o := 0
		var base := c * MAX_OPTIONS
		while bits != 0:
			if bits & 1:
				var m := _opt_mask[base + o]
				all_on &= m
				any_on |= m
			bits >>= 1
			o += 1
		if dom == 0:
			all_on = 0
		_must[c] = all_on
		_may[c] = any_on


## Filters the options of `v` against its neighbours. Returns -1 on
## contradiction, 1 if the domain shrank, 0 otherwise.
func _revise(v: int) -> int:
	var dom := _dom[v]
	if dom == 0:
		return -1
	var new_dom := dom
	for c in _var_cells[v]:
		var on := 0
		var off := 0
		var base := c * _dc
		for d in _dc:
			var other := puzzle.nbr[base + d]
			var bit := 1 << d
			if other < 0:
				off |= bit
				continue
			var ob := 1 << _opp[d]
			if _must[other] & ob:
				if _exclusive:
					off |= bit
				else:
					on |= bit
			elif (_may[other] & ob) == 0 and not _exclusive:
				off |= bit
		if on == 0 and off == 0:
			continue
		var obase := c * MAX_OPTIONS
		var bits := new_dom
		var o := 0
		while bits != 0:
			if bits & 1:
				var m := _opt_mask[obase + o]
				if (m & on) != on or (m & off) != 0:
					new_dom &= ~(1 << o)
			bits >>= 1
			o += 1
		if new_dom == 0:
			break
	if new_dom == dom:
		return 0
	_dom[v] = new_dom
	_update_cells(v)
	return -1 if new_dom == 0 else 1


## Arc-consistency fixpoint starting from the queued variables.
func _propagate_from(start_vars: PackedInt32Array) -> bool:
	_queue.clear()
	_in_queue.fill(0)
	for v in start_vars:
		if _in_queue[v] == 0:
			_in_queue[v] = 1
			_queue.append(v)
	var head := 0
	while head < _queue.size():
		var v := _queue[head]
		head += 1
		_in_queue[v] = 0
		var res := _revise(v)
		if res < 0:
			return false
		if res > 0:
			for nv in _var_nbrs[v]:
				if _in_queue[nv] == 0:
					_in_queue[nv] = 1
					_queue.append(nv)
			# Linked groups may constrain their own members.
			if _var_cells[v].size() > 1 and _in_queue[v] == 0:
				_in_queue[v] = 1
				_queue.append(v)
	return true


func _all_vars() -> PackedInt32Array:
	var all := PackedInt32Array()
	all.resize(_var_count)
	for v in _var_count:
		all[v] = v
	return all


## Global pruning for forest modes on the certainly-connected sub-graph.
func _global_ok() -> bool:
	if not _forest:
		return true
	for c in _n:
		_parent[c] = c
	for c in _n:
		var m := _must[c]
		if m == 0:
			continue
		var base := c * _dc
		for d in _dc:
			if (m >> d) & 1 == 0:
				continue
			var other := puzzle.nbr[base + d]
			if other <= c:
				continue
			var ra := _find(c)
			var rb := _find(other)
			if ra == rb:
				return false  # cycle
			_parent[rb] = ra
	for i in range(0, puzzle.portal_pairs.size() - 1, 2):
		var ra := _find(puzzle.portal_pairs[i])
		var rb := _find(puzzle.portal_pairs[i + 1])
		if ra == rb:
			return false
		_parent[rb] = ra
	var cores_in := {}
	for c in puzzle.cores:
		var r := _find(c)
		if cores_in.has(r):
			return false  # two cores joined
		cores_in[r] = true
	# Closed components: no undecided direction left on any member.
	var open := {}
	var size := {}
	for c in _n:
		if puzzle.network_cell[c] == 0:
			continue
		var r := _find(c)
		size[r] = int(size.get(r, 0)) + 1
		if _must[c] != _may[c]:
			open[r] = true
	for r in size.keys():
		if open.has(r):
			continue
		if not cores_in.has(r):
			return false
		if _single_core and int(size[r]) < _network_total:
			return false
	return true


func _find(x: int) -> int:
	var root := x
	while _parent[root] != root:
		root = _parent[root]
	var cur := x
	while _parent[cur] != root:
		var nxt := _parent[cur]
		_parent[cur] = root
		cur = nxt
	return root


func _undecided_count() -> int:
	var count := 0
	for v in _var_count:
		var d := _dom[v]
		if d & (d - 1) != 0:
			count += 1
	return count


## Minimum-remaining-values variable choice; -1 when everything is decided.
func _pick_var() -> int:
	var best := -1
	var best_size := 99
	for v in _var_count:
		var d := _dom[v]
		if d & (d - 1) == 0:
			continue
		var s := Topology.popcount(d)
		if s < best_size:
			best_size = s
			best = v
			if s == 2:
				break
	return best


func _option_order(v: int, preferred: PackedInt32Array) -> PackedInt32Array:
	var order := PackedInt32Array()
	var d := _dom[v]
	var first := -1
	if preferred.size() == _n:
		var c := _var_cells[v][0]
		var want := puzzle.mask_at(c, preferred[c])
		for o in _var_opts[v]:
			if (d >> o) & 1 == 1 and _opt_mask[c * MAX_OPTIONS + o] == want:
				first = o
				order.append(o)
				break
	for o in _var_opts[v]:
		if (d >> o) & 1 == 1 and o != first:
			order.append(o)
	return order


func _extract_rotations() -> PackedInt32Array:
	var rot := PackedInt32Array()
	rot.resize(_n)
	for v in _var_count:
		var d := _dom[v]
		var o := 0
		while (d >> o) & 1 == 0 and o < MAX_OPTIONS:
			o += 1
		for c in _var_cells[v]:
			rot[c] = _opt_rot[c * MAX_OPTIONS + o]
	return rot


## Solves the puzzle.
##   max_solutions: stop after this many solutions (2 = uniqueness test).
##   node_limit:    maximum branching nodes explored.
##   preferred:     rotations to try first (hints: closest solution).
## Returns a Dictionary, see SolveResult keys below.
func solve(max_solutions: int = 2, node_limit: int = 6000, preferred: PackedInt32Array = PackedInt32Array()) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var result := {
		"solutions": [],
		"count": 0,
		"complete": false,
		"nodes": 0,
		"backtracks": 0,
		"max_depth": 0,
		"decisions": decision_count(),
		"root_undecided": 0,
		"root_local_undecided": 0,
		"contradiction": false,
		"hit_limit": false,
		"time_ms": 0.0,
	}
	_reset_state()
	if not _propagate_from(_all_vars()):
		result["contradiction"] = true
		result["complete"] = true
		result["time_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
		return result
	result["root_local_undecided"] = _undecided_count()
	if not _global_ok():
		result["contradiction"] = true
		result["complete"] = true
		result["time_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
		return result
	result["root_undecided"] = _undecided_count()

	var solutions: Array[PackedInt32Array] = []
	var frames: Array = []
	var nodes := 0
	var backtracks := 0
	var max_depth := 0
	var descend := true
	var hit_limit := false
	while true:
		if descend:
			descend = false
			var v := _pick_var()
			if v < 0:
				var rot := _extract_rotations()
				if Validator.is_solved_rot(puzzle, rot):
					solutions.append(rot)
					if solutions.size() >= max_solutions:
						break
			else:
				frames.append({
					"dom": _dom.duplicate(), "must": _must.duplicate(), "may": _may.duplicate(),
					"v": v, "opts": _option_order(v, preferred), "i": 0,
				})
		if frames.is_empty():
			break
		var f: Dictionary = frames[frames.size() - 1]
		var opts: PackedInt32Array = f["opts"]
		var i: int = f["i"]
		if i >= opts.size():
			frames.pop_back()
			backtracks += 1
			continue
		f["i"] = i + 1
		nodes += 1
		if nodes > node_limit:
			hit_limit = true
			break
		_dom = (f["dom"] as PackedInt32Array).duplicate()
		_must = (f["must"] as PackedInt32Array).duplicate()
		_may = (f["may"] as PackedInt32Array).duplicate()
		var var_id: int = f["v"]
		_dom[var_id] = 1 << opts[i]
		_update_cells(var_id)
		var start := _var_nbrs[var_id].duplicate()
		start.append(var_id)
		if _propagate_from(start) and _global_ok():
			descend = true
			max_depth = maxi(max_depth, frames.size())

	result["solutions"] = solutions
	result["count"] = solutions.size()
	result["complete"] = not hit_limit and solutions.size() < max_solutions
	result["nodes"] = nodes
	result["backtracks"] = backtracks
	result["max_depth"] = max_depth
	result["hit_limit"] = hit_limit
	result["time_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return result


## Logical deductions only (no guessing), independent of the player's board:
## returns the per-cell rotation forced by propagation, or -1 if ambiguous.
## Used by the hint system to teach real deductions first.
func forced_rotations() -> PackedInt32Array:
	var forced := PackedInt32Array()
	forced.resize(_n)
	forced.fill(-1)
	_reset_state()
	if not _propagate_from(_all_vars()) or not _global_ok():
		return forced
	for v in _var_count:
		if _var_opts[v] <= 1:
			continue
		var d := _dom[v]
		if d != 0 and d & (d - 1) == 0:
			var o := 0
			while (d >> o) & 1 == 0:
				o += 1
			for c in _var_cells[v]:
				forced[c] = _opt_rot[c * MAX_OPTIONS + o]
	return forced
