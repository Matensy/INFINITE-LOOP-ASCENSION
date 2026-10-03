class_name Validator
extends RefCounted
## Authoritative check of whether a set of tile masks solves a puzzle. Used
## by gameplay (win detection), the generator (solution sanity) and the solver
## (leaf verification).


static func current_masks(puzzle: Puzzle, rot: PackedInt32Array) -> PackedInt32Array:
	var n := puzzle.cell_count()
	var dc := puzzle.dir_count()
	var out := PackedInt32Array()
	out.resize(n)
	for c in n:
		if puzzle.active[c] == 1:
			out[c] = Topology.rotate_mask(puzzle.masks[c], rot[c], dc)
	return out


static func is_solved_rot(puzzle: Puzzle, rot: PackedInt32Array) -> bool:
	return is_solved(puzzle, current_masks(puzzle, rot))


static func is_solved(puzzle: Puzzle, masks: PackedInt32Array) -> bool:
	var rules := RuleSet.for_mode(puzzle.mode)
	return local_violations(puzzle, masks, rules, 1) == 0 and rules.check_global(puzzle, masks)


## Counts violated edge constraints (stops early once `limit` is reached,
## pass -1 for an exact count). Boundary connectors count as violations.
static func local_violations(puzzle: Puzzle, masks: PackedInt32Array, rules: RuleSet, limit: int = -1) -> int:
	var n := puzzle.cell_count()
	var dc := puzzle.dir_count()
	var topo := puzzle.topology
	var exclusive := rules.relation() == RuleSet.RELATION_EXCLUSIVE
	var bad := 0
	for c in n:
		if puzzle.active[c] == 0:
			continue
		var m := masks[c]
		for d in dc:
			var has := (m >> d) & 1 == 1
			var other := puzzle.nbr[c * dc + d]
			if other < 0:
				if has and not rules.boundary_allows_connector():
					bad += 1
			elif other > c:
				var facing := (masks[other] >> topo.opposite(d)) & 1 == 1
				var ok := not (has and facing) if exclusive else has == facing
				if not ok:
					bad += 1
			if limit > 0 and bad >= limit:
				return bad
	return bad


## Verifies that the stored solution orientation (rotation 0) is valid.
static func verify_stored_solution(puzzle: Puzzle) -> bool:
	return is_solved(puzzle, current_masks(puzzle, puzzle.solution_rotations()))


## Structural sanity checks independent of orientation. Returns "" when the
## puzzle is well formed, otherwise a description of the first problem.
static func structural_errors(puzzle: Puzzle) -> String:
	var n := puzzle.cell_count()
	if puzzle.masks.size() != n or puzzle.start_rot.size() != n or puzzle.active.size() != n:
		return "array size mismatch"
	if puzzle.active_count() == 0:
		return "no active cells"
	for c in n:
		if puzzle.active[c] == 0 and puzzle.masks[c] != 0:
			return "inactive cell %d has connectors" % c
		if puzzle.locked[c] == 1 and posmod(puzzle.start_rot[c], puzzle.period_of(c)) != 0:
			return "locked cell %d not in solution orientation" % c
	for c in puzzle.cores:
		if puzzle.active[c] == 0:
			return "core on inactive cell"
	if GameMode.uses_cores(puzzle.mode) and puzzle.cores.is_empty():
		return "core mode without cores"
	for g in puzzle.link_groups:
		if g.size() < 2:
			return "link group with fewer than 2 members"
		# All members must be satisfiable by one shared rotation offset.
		var dc := puzzle.dir_count()
		var found := false
		for t in dc:
			var all_ok := true
			for c in g:
				if posmod(puzzle.start_rot[c] + t, puzzle.period_of(c)) != 0:
					all_ok = false
					break
			if all_ok:
				found = true
				break
		if not found:
			return "link group cannot reach the solution"
	return ""
