class_name SolutionBuilder
extends RefCounted
## Generator layers 1-2: builds a *valid solved network* for the plan's mode.
## Puzzles are always derived from a known solution, so they can never be
## impossible.


## Fills puzzle.masks / cores / portal_pairs. Returns false if the attempt
## produced a degenerate network and should be discarded.
static func build(puzzle: Puzzle, plan: LevelPlan, rng: SeededRng) -> bool:
	puzzle.masks.fill(0)
	puzzle.cores = PackedInt32Array()
	puzzle.portal_pairs = PackedInt32Array()
	puzzle.finalize()
	var ok := false
	match plan.mode:
		GameMode.DARK:
			ok = _build_dark(puzzle, plan.density, rng)
		GameMode.CORE, GameMode.MULTI:
			ok = _build_forest(puzzle, plan, rng)
		_:
			ok = _build_loop(puzzle, plan.density, rng)
	puzzle.finalize()
	return ok and _rotatable_tiles(puzzle) >= 2


## LOOP: any subset of edges is a valid solution; every endpoint pair of a
## chosen edge gets facing connectors.
static func _build_loop(puzzle: Puzzle, density: float, rng: SeededRng) -> bool:
	var topo := puzzle.topology
	var dc := topo.dir_count
	for c in topo.cell_count:
		if puzzle.active[c] == 0:
			continue
		for d in dc:
			var n := puzzle.nbr[c * dc + d]
			if n > c and rng.chance(density):
				puzzle.masks[c] |= 1 << d
				puzzle.masks[n] |= 1 << topo.opposite(d)
	return true


## DARK: each chosen edge carries exactly one connector, on a random side,
## so no two connectors ever face each other in the solution.
static func _build_dark(puzzle: Puzzle, density: float, rng: SeededRng) -> bool:
	var topo := puzzle.topology
	var dc := topo.dir_count
	for c in topo.cell_count:
		if puzzle.active[c] == 0:
			continue
		for d in dc:
			var n := puzzle.nbr[c * dc + d]
			if n > c and rng.chance(density):
				if rng.chance(0.5):
					puzzle.masks[c] |= 1 << d
				else:
					puzzle.masks[n] |= 1 << topo.opposite(d)
	return true


## CORE / MULTI: a forest grown simultaneously from every core with a
## "growing tree" algorithm. `branching` mixes newest-first (long corridors)
## and random (bushy) frontier selection. Portals join two cells atomically.
static func _build_forest(puzzle: Puzzle, plan: LevelPlan, rng: SeededRng) -> bool:
	var topo := puzzle.topology
	var dc := topo.dir_count
	var n := topo.cell_count
	var active_cells := PackedInt32Array()
	for c in n:
		if puzzle.active[c] == 1:
			active_cells.append(c)
	var core_count := maxi(1, plan.cores)
	if active_cells.size() < core_count * 3:
		return false
	var roots := _spread_cells(puzzle, active_cells, core_count, rng)
	var portal_of := PackedInt32Array()
	portal_of.resize(n)
	portal_of.fill(-1)
	var pairs := _choose_portals(puzzle, active_cells, roots, plan.portals, rng)
	for i in range(0, pairs.size(), 2):
		portal_of[pairs[i]] = pairs[i + 1]
		portal_of[pairs[i + 1]] = pairs[i]

	var owner := PackedInt32Array()
	owner.resize(n)
	owner.fill(-1)
	var f_cell := PackedInt32Array()
	var f_dir := PackedInt32Array()
	var target := clampi(int(round(plan.density * active_cells.size())), core_count * 2, active_cells.size())
	var size := 0
	var join := func(cell: int, who: int) -> int:
		# Adds `cell` (and its portal partner) to tree `who`; returns cells added.
		var added := 0
		var todo := PackedInt32Array([cell])
		while not todo.is_empty():
			var x := todo[todo.size() - 1]
			todo.remove_at(todo.size() - 1)
			if owner[x] >= 0:
				continue
			owner[x] = who
			added += 1
			for d in dc:
				var y := puzzle.nbr[x * dc + d]
				if y >= 0 and owner[y] < 0:
					f_cell.append(x)
					f_dir.append(d)
			if portal_of[x] >= 0 and owner[portal_of[x]] < 0:
				todo.append(portal_of[x])
		return added
	for i in roots.size():
		size += join.call(roots[i], i)
	while size < target and not f_cell.is_empty():
		var idx := f_cell.size() - 1
		if rng.chance(plan.branching):
			idx = rng.range_int(0, f_cell.size() - 1)
		var c := f_cell[idx]
		var d := f_dir[idx]
		f_cell[idx] = f_cell[f_cell.size() - 1]
		f_dir[idx] = f_dir[f_dir.size() - 1]
		f_cell.resize(f_cell.size() - 1)
		f_dir.resize(f_dir.size() - 1)
		var other := puzzle.nbr[c * dc + d]
		if other < 0 or owner[other] >= 0:
			continue
		puzzle.masks[c] |= 1 << d
		puzzle.masks[other] |= 1 << topo.opposite(d)
		size += join.call(other, owner[c])

	# Every core needs a real network around it.
	var tree_size := PackedInt32Array()
	tree_size.resize(core_count)
	for c in n:
		if owner[c] >= 0:
			tree_size[owner[c]] += 1
	for s in tree_size:
		if s < 2:
			return false
	puzzle.cores = roots
	var kept := PackedInt32Array()
	for i in range(0, pairs.size(), 2):
		if owner[pairs[i]] >= 0:
			kept.append(pairs[i])
			kept.append(pairs[i + 1])
	puzzle.portal_pairs = kept
	return true


## Picks `count` cells spread over the board (farthest-point sampling).
static func _spread_cells(puzzle: Puzzle, cells: PackedInt32Array, count: int, rng: SeededRng) -> PackedInt32Array:
	var topo := puzzle.topology
	var chosen := PackedInt32Array()
	if count == 1:
		# Single core: prefer the central region so energy radiates outwards.
		var centre := topo.board_size() * 0.5
		var best := cells[0]
		var best_score := INF
		for i in mini(cells.size(), 24):
			var c := cells[rng.range_int(0, cells.size() - 1)]
			var score := topo.cell_center(c).distance_to(centre) + rng.next_float() * 1.5
			if score < best_score:
				best_score = score
				best = c
		chosen.append(best)
		return chosen
	chosen.append(cells[rng.range_int(0, cells.size() - 1)])
	while chosen.size() < count:
		var best := -1
		var best_d := -1.0
		for i in mini(cells.size(), 40):
			var c := cells[rng.range_int(0, cells.size() - 1)]
			if chosen.has(c):
				continue
			var nearest := INF
			for k in chosen:
				nearest = minf(nearest, topo.cell_center(c).distance_to(topo.cell_center(k)))
			if nearest > best_d:
				best_d = nearest
				best = c
		if best < 0:
			break
		chosen.append(best)
	return chosen


## Picks portal pairs between distant, non-adjacent, non-core cells.
static func _choose_portals(puzzle: Puzzle, cells: PackedInt32Array, roots: PackedInt32Array, count: int, rng: SeededRng) -> PackedInt32Array:
	var pairs := PackedInt32Array()
	if count <= 0:
		return pairs
	var topo := puzzle.topology
	var used := {}
	for r in roots:
		used[r] = true
	var min_dist := topo.board_size().length() * 0.3
	var tries := 0
	while pairs.size() / 2 < count and tries < count * 30:
		tries += 1
		var a := cells[rng.range_int(0, cells.size() - 1)]
		var b := cells[rng.range_int(0, cells.size() - 1)]
		if a == b or used.has(a) or used.has(b):
			continue
		if topo.cell_center(a).distance_to(topo.cell_center(b)) < min_dist:
			continue
		var touching := false
		for k in used.keys():
			var p: Vector2 = topo.cell_center(k)
			if p.distance_to(topo.cell_center(a)) < 1.9 or p.distance_to(topo.cell_center(b)) < 1.9:
				touching = true
				break
		if touching:
			continue
		used[a] = true
		used[b] = true
		pairs.append(a)
		pairs.append(b)
	return pairs


static func _rotatable_tiles(puzzle: Puzzle) -> int:
	var count := 0
	for c in puzzle.cell_count():
		if puzzle.active[c] == 1 and puzzle.period_of(c) > 1:
			count += 1
	return count
