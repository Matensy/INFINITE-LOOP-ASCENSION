class_name DifficultyAnalyzer
extends RefCounted
## Generator layer 7: measures how hard a puzzle actually is.
##
## DifficultyScore = ((tiles + reasoning + steps) * mode * topology
##                    + specials) * uniqueness
##   tiles      real decisions (rotatable units), sub-linear
##   reasoning  units that local deduction cannot settle + search effort
##   steps      estimated human steps (minimum taps from the scramble)
##   specials   portals, linked tiles, extra cores (locked tiles discount)
## Weights live in data/difficulties/difficulty.json.


static func analyze(puzzle: Puzzle, solve: Dictionary) -> Dictionary:
	var sc := DifficultyConfig.section("score")
	var decisions := int(solve.get("decisions", 0))
	var nonlocal := int(solve.get("root_local_undecided", 0))
	var nodes := int(solve.get("nodes", 0))
	var tiles := float(sc.get("tile_weight", 0.62)) * pow(float(decisions), float(sc.get("tile_exponent", 0.9)))
	var reasoning := float(sc.get("nonlocal_weight", 0.22)) * nonlocal
	reasoning += float(sc.get("search_weight", 2.2)) * log(1.0 + nodes) / log(2.0)
	var steps_count := min_moves(puzzle)
	var steps := float(sc.get("steps_weight", 0.05)) * steps_count
	var mode_mult := float((sc.get("mode_multiplier", {}) as Dictionary).get(GameMode.id_of(puzzle.mode), 1.0))
	var topo_mult := float(sc.get("hex_multiplier", 1.3)) if puzzle.topology.kind == Topology.Kind.HEX else 1.0
	var link_members := 0
	for g in puzzle.link_groups:
		link_members += g.size()
	var locks := 0
	for c in puzzle.cell_count():
		if puzzle.locked[c] == 1 and puzzle.period_of(c) > 1:
			locks += 1
	var specials := puzzle.portal_count() * float(sc.get("portal_weight", 2.5))
	specials += link_members * float(sc.get("link_member_weight", 1.6))
	specials += maxi(0, puzzle.cores.size() - 1) * float(sc.get("extra_core_weight", 1.5))
	specials -= locks * float(sc.get("lock_discount", 0.4))
	var unique := int(solve.get("count", 0)) == 1 and bool(solve.get("complete", false))
	var uniq_mult := 1.0 + (float(sc.get("unique_bonus", 0.12)) if unique else 0.0)
	var score := maxf(1.0, ((tiles + reasoning + steps) * mode_mult * topo_mult + specials) * uniq_mult)
	return {
		"score": snappedf(score, 0.1),
		"tier": DifficultyCurve.tier_id(score),
		"decisions": decisions,
		"nonlocal": nonlocal,
		"nodes": nodes,
		"min_moves": steps_count,
		"tiles": snappedf(tiles, 0.01),
		"reasoning": snappedf(reasoning, 0.01),
		"specials": snappedf(specials, 0.01),
		"unique": unique,
		"locks": locks,
		"link_members": link_members,
	}


## Minimum taps from the scrambled state to the stored solution (tap = one
## step in either direction). Linked groups count once.
static func min_moves(puzzle: Puzzle) -> int:
	var dc := puzzle.dir_count()
	var total := 0
	for c in puzzle.cell_count():
		if puzzle.active[c] == 0 or puzzle.locked[c] == 1 or puzzle.link_of[c] >= 0:
			continue
		var period := puzzle.period_of(c)
		if period <= 1:
			continue
		var diff := posmod(-puzzle.start_rot[c], period)
		total += mini(diff, period - diff)
	for g in puzzle.link_groups:
		# Smallest shared offset t that solves every member.
		var best := dc
		for t in range(-dc + 1, dc):
			var ok := true
			for c in g:
				if posmod(puzzle.start_rot[c] + t, puzzle.period_of(c)) != 0:
					ok = false
					break
			if ok:
				best = mini(best, absi(t))
		total += best
	return total
