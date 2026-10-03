class_name SpecialMechanics
extends RefCounted
## Generator layer 4: adds special tiles on top of a solved network.
## Portals and cores are placed by SolutionBuilder (they shape the network);
## this layer adds locked anchors and linked tile groups. Every mechanic here
## is understood by the solver, validator, renderer and save format.


static func apply(puzzle: Puzzle, plan: LevelPlan, rng: SeededRng) -> void:
	puzzle.locked.fill(0)
	puzzle.link_groups = []
	if plan.anchors > 0:
		add_anchors(puzzle, plan.anchors, rng)
	if plan.link_groups > 0:
		add_links(puzzle, plan.link_groups, plan.link_size, rng)
	puzzle.finalize()


## Locks `count` random rotatable tiles in their solution orientation.
static func add_anchors(puzzle: Puzzle, count: int, rng: SeededRng) -> int:
	var candidates := _free_rotatable(puzzle)
	rng.shuffle_packed(candidates)
	var placed := 0
	for c in candidates:
		if placed >= count:
			break
		puzzle.locked[c] = 1
		puzzle.start_rot[c] = 0
		placed += 1
	return placed


## Creates linked groups: rotating any member rotates every member.
static func add_links(puzzle: Puzzle, groups: int, size: int, rng: SeededRng) -> int:
	var candidates := _free_rotatable(puzzle)
	rng.shuffle_packed(candidates)
	var taken := {}
	var made := 0
	var topo := puzzle.topology
	for start in candidates:
		if made >= groups:
			break
		if taken.has(start):
			continue
		var group := PackedInt32Array([start])
		for other in candidates:
			if group.size() >= size:
				break
			if taken.has(other) or group.has(other):
				continue
			# Keep members apart so the link is not visually trivial.
			var far := true
			for m in group:
				if topo.cell_center(m).distance_to(topo.cell_center(other)) < 1.9:
					far = false
					break
			if far:
				group.append(other)
		if group.size() < 2:
			continue
		for m in group:
			taken[m] = true
		puzzle.link_groups.append(group)
		made += 1
	puzzle.finalize()
	return made


static func _free_rotatable(puzzle: Puzzle) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in puzzle.cell_count():
		if puzzle.active[c] == 0 or puzzle.locked[c] == 1:
			continue
		if puzzle.link_of.size() > 0 and puzzle.link_of[c] >= 0:
			continue
		if puzzle.period_of(c) > 1:
			out.append(c)
	return out
