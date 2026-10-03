class_name Scrambler
extends RefCounted
## Generator layer 5: rotates tiles away from the solution. Locked tiles keep
## their solution orientation; linked groups share one offset so the group can
## always be rotated back together.

const MAX_TRIES := 6


static func scramble(puzzle: Puzzle, rng: SeededRng) -> void:
	for attempt in MAX_TRIES:
		_scramble_once(puzzle, rng)
		if not Validator.is_solved_rot(puzzle, puzzle.start_rot):
			return
	# Tiny boards can land on another solution by chance; force one tile off.
	for c in puzzle.cell_count():
		if puzzle.is_rotatable(c) and puzzle.link_of[c] < 0:
			puzzle.start_rot[c] = posmod(puzzle.start_rot[c] + 1, puzzle.dir_count())
			if not Validator.is_solved_rot(puzzle, puzzle.start_rot):
				return


static func _scramble_once(puzzle: Puzzle, rng: SeededRng) -> void:
	var dc := puzzle.dir_count()
	for c in puzzle.cell_count():
		if puzzle.active[c] == 0 or puzzle.locked[c] == 1:
			puzzle.start_rot[c] = 0
			continue
		if puzzle.link_of[c] >= 0:
			continue
		var period := puzzle.period_of(c)
		if period <= 1:
			puzzle.start_rot[c] = rng.range_int(0, dc - 1)
			continue
		# Any rotation that is not equivalent to the solution orientation.
		var r := rng.range_int(1, dc - 1)
		while r % period == 0:
			r = rng.range_int(1, dc - 1)
		puzzle.start_rot[c] = r
	for group in puzzle.link_groups:
		var t := _group_offset(puzzle, group, rng)
		for c in group:
			# start + t must be a multiple of the member's period.
			var period := puzzle.period_of(c)
			var extra := rng.range_int(0, dc / period - 1) * period
			puzzle.start_rot[c] = posmod(-t + extra, dc)


## Shared offset that leaves at least one member visibly out of place.
static func _group_offset(puzzle: Puzzle, group: PackedInt32Array, rng: SeededRng) -> int:
	var dc := puzzle.dir_count()
	var options := PackedInt32Array()
	for t in range(1, dc):
		for c in group:
			if t % puzzle.period_of(c) != 0:
				options.append(t)
				break
	if options.is_empty():
		return rng.range_int(1, dc - 1)
	return options[rng.range_int(0, options.size() - 1)]
