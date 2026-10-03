class_name Connectivity
extends RefCounted
## Graph queries over the current board: which cells are joined by matched
## connectors (and portals), and which core powers which cell.

const UNPOWERED := -1
const CONFLICT := -2


## Union-find root per cell over matched edges and portal links.
static func components(puzzle: Puzzle, masks: PackedInt32Array) -> PackedInt32Array:
	var n := puzzle.cell_count()
	var dc := puzzle.dir_count()
	var parent := PackedInt32Array()
	parent.resize(n)
	for c in n:
		parent[c] = c
	for c in n:
		if puzzle.active[c] == 0:
			continue
		var m := masks[c]
		if m == 0:
			continue
		for d in dc:
			if (m >> d) & 1 == 0:
				continue
			var other := puzzle.nbr[c * dc + d]
			if other <= c:
				continue
			if (masks[other] >> puzzle.topology.opposite(d)) & 1 == 1:
				_union(parent, c, other)
	for i in range(0, puzzle.portal_pairs.size() - 1, 2):
		_union(parent, puzzle.portal_pairs[i], puzzle.portal_pairs[i + 1])
	for c in n:
		parent[c] = _find(parent, c)
	return parent


## Per cell: index of the powering core, UNPOWERED, or CONFLICT when two or
## more cores reach the same component.
static func power(puzzle: Puzzle, masks: PackedInt32Array) -> PackedInt32Array:
	var n := puzzle.cell_count()
	var owner := PackedInt32Array()
	owner.resize(n)
	owner.fill(UNPOWERED)
	if puzzle.cores.is_empty():
		return owner
	var comp := components(puzzle, masks)
	var comp_owner := {}
	for i in puzzle.cores.size():
		var root := comp[puzzle.cores[i]]
		if comp_owner.has(root):
			comp_owner[root] = CONFLICT
		else:
			comp_owner[root] = i
	for c in n:
		if puzzle.active[c] == 1 and comp_owner.has(comp[c]):
			owner[c] = comp_owner[comp[c]]
	return owner


## Per cell bitmask of connectors that are currently matched (LOOP sense:
## the neighbour has a facing connector).
static func matched_mask(puzzle: Puzzle, masks: PackedInt32Array) -> PackedInt32Array:
	var n := puzzle.cell_count()
	var dc := puzzle.dir_count()
	var result := PackedInt32Array()
	result.resize(n)
	for c in n:
		var m := masks[c]
		if m == 0 or puzzle.active[c] == 0:
			continue
		var good := 0
		for d in dc:
			if (m >> d) & 1 == 0:
				continue
			var other := puzzle.nbr[c * dc + d]
			if other >= 0 and (masks[other] >> puzzle.topology.opposite(d)) & 1 == 1:
				good |= 1 << d
		result[c] = good
	return result


## Breadth-first distances from the given start cells across matched edges
## and portals. Unreached cells get -1. Used by the victory animation.
static func distances(puzzle: Puzzle, masks: PackedInt32Array, starts: PackedInt32Array) -> PackedInt32Array:
	var n := puzzle.cell_count()
	var dc := puzzle.dir_count()
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var queue := PackedInt32Array()
	for s in starts:
		if s >= 0 and s < n and dist[s] < 0:
			dist[s] = 0
			queue.append(s)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var m := masks[c]
		for d in dc:
			if (m >> d) & 1 == 0:
				continue
			var other := puzzle.nbr[c * dc + d]
			if other < 0 or dist[other] >= 0:
				continue
			if (masks[other] >> puzzle.topology.opposite(d)) & 1 == 1:
				dist[other] = dist[c] + 1
				queue.append(other)
		var partner := puzzle.portal_of[c]
		if partner >= 0 and dist[partner] < 0:
			dist[partner] = dist[c] + 1
			queue.append(partner)
	return dist


static func _find(parent: PackedInt32Array, x: int) -> int:
	var root := x
	while parent[root] != root:
		root = parent[root]
	var cur := x
	while parent[cur] != root:
		var nxt := parent[cur]
		parent[cur] = root
		cur = nxt
	return root


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		if ra < rb:
			parent[rb] = ra
		else:
			parent[ra] = rb
