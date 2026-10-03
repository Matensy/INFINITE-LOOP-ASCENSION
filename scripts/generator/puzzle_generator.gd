class_name PuzzleGenerator
extends RefCounted
## Orchestrates the layered pipeline:
##   Seed -> Plan (difficulty vector) -> Topology -> Valid solution
##   -> Special mechanics -> Scramble -> Validate -> Solve
##   -> Difficulty analysis -> Anti-repetition -> Final puzzle
##
## Fully deterministic for a given PuzzleRequest: no wall-clock limits, no
## global RNG. Candidates that miss the target difficulty steer the board
## size of the next attempt (closed loop) and the closest one is kept.

const FALLBACK_SALT := 0x46414C4C

## Optional anti-repetition memory (zen / random modes). Level puzzles leave
## these empty so they stay identical for every player.
var avoid_fingerprints: Dictionary = {}
var avoid_features: Array[PackedFloat32Array] = []

var last_report: Dictionary = {}


func generate(request: PuzzleRequest) -> Puzzle:
	var t0 := Time.get_ticks_usec()
	var plan := LevelPlanner.plan(request)
	var rng := SeededRng.new(request.seed)
	GameLog.info("GENERATOR", "seed=%d level=%d kind=%s target=%.1f mode=%s %dx%d %s" % [
		request.seed, request.level, request.kind_id(), plan.target, GameMode.id_of(plan.mode),
		plan.width, plan.height, BoardShapes.shape_name(plan.shape)])
	var best: Puzzle = null
	var best_err := INF
	var best_analysis: Dictionary = {}
	var best_solve: Dictionary = {}
	var rejected_similar := 0
	var invalid := 0
	var attempts := 0
	var current := plan
	for attempt in plan.max_attempts:
		attempts += 1
		var cand_rng := rng.fork(attempt + 1)
		var puzzle := build_candidate(current, cand_rng)
		if puzzle == null:
			invalid += 1
			continue
		var problem := Validator.structural_errors(puzzle)
		if problem != "" or not Validator.verify_stored_solution(puzzle):
			invalid += 1
			GameLog.error("VALIDATOR", "candidate rejected: %s" % (problem if problem != "" else "stored solution invalid"))
			continue
		var solve := _solve_and_disambiguate(puzzle, current, cand_rng)
		var analysis := DifficultyAnalyzer.analyze(puzzle, solve)
		var score: float = analysis["score"]
		var fp := Fingerprint.compute(puzzle)
		if _is_repeat(fp, puzzle):
			rejected_similar += 1
			GameLog.debug("GENERATOR", "attempt %d rejected as repeat" % attempt)
			continue
		var err := absf(log(score / plan.target))
		if current.require_unique and not puzzle.unique:
			err += 0.6
		GameLog.debug("DIFFICULTY", "attempt %d score=%.1f target=%.1f err=%.2f" % [attempt, score, plan.target, err])
		if err < best_err:
			best_err = err
			best = puzzle
			best_analysis = analysis
			best_solve = solve
			best.meta["fingerprint"] = fp
		if err <= plan.tolerance:
			break
		if current.require_unique and not puzzle.unique and attempts >= 3:
			# Uniqueness keeps failing for this layout: relax PERFECT rather
			# than burn the remaining attempts (bounded generation time).
			current = current.duplicate_plan()
			current.require_unique = false
		var expo := float(DifficultyConfig.value("planner", "expected_tile_exponent", 0.9))
		var next := LevelPlanner.rescale(current, pow(plan.target / maxf(score, 0.5), 1.0 / expo))
		if next.width == current.width and next.height == current.height and not (current.require_unique and not puzzle.unique):
			# The board cannot be steered any further (e.g. maximum size for an
			# extreme target): keep the best candidate instead of spinning.
			break
		current = next

	if best == null:
		GameLog.warn("GENERATOR", "all attempts failed, using fallback puzzle")
		best = _fallback(request)
		best_solve = PuzzleSolver.new(best).solve(2, plan.node_limit)
		best_analysis = DifficultyAnalyzer.analyze(best, best_solve)
		best.meta["fingerprint"] = Fingerprint.compute(best)

	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
	best.meta.merge({
		"seed": request.seed,
		"level": request.level,
		"kind": request.kind_id(),
		"bias": request.bias,
		"code": SeedManager.make_code(request),
		"label": request.label,
		"target": snappedf(plan.target, 0.1),
		"difficulty": best_analysis.get("score", 1.0),
		"tier": best_analysis.get("tier", "tutorial"),
		"min_moves": best_analysis.get("min_moves", 0),
		"theme": plan.theme,
		"shape": BoardShapes.shape_name(plan.shape),
		"event": plan.event,
		"boss": plan.boss,
		"plan": plan.to_dict(),
		"analysis": best_analysis,
		"solver_nodes": best_solve.get("nodes", 0),
		"solver_limited": best_solve.get("hit_limit", false),
		"attempts": attempts,
		"gen_ms": snappedf(gen_ms, 0.01),
	}, true)
	last_report = {
		"attempts": attempts, "invalid": invalid, "rejected_similar": rejected_similar,
		"error": best_err, "gen_ms": gen_ms,
	}
	GameLog.info("DIFFICULTY", "score=%.1f tier=%s unique=%s attempts=%d %.1fms" % [
		float(best_analysis.get("score", 0)), str(best_analysis.get("tier", "")), str(best.unique), attempts, gen_ms])
	GameLog.info("VALIDATOR", "PASS fingerprint=%s" % best.meta["fingerprint"])
	return best


## Layers 1-5 for one candidate. Returns null for degenerate attempts.
static func build_candidate(plan: LevelPlan, rng: SeededRng) -> Puzzle:
	var topo := TopologyFactory.create(plan.topology, plan.width, plan.height)
	var puzzle := Puzzle.create(topo)
	puzzle.mode = plan.mode
	puzzle.active = BoardShapes.build(plan.shape, topo, rng)
	puzzle.finalize()
	if not SolutionBuilder.build(puzzle, plan, rng):
		return null
	SpecialMechanics.apply(puzzle, plan, rng)
	Scrambler.scramble(puzzle, rng)
	return puzzle


## Layers 6-7: solve, and for PERFECT plans lock distinguishing tiles until
## the solution is unique (bounded).
func _solve_and_disambiguate(puzzle: Puzzle, plan: LevelPlan, rng: SeededRng) -> Dictionary:
	var solver := PuzzleSolver.new(puzzle)
	var res := solver.solve(2, plan.node_limit)
	if plan.require_unique:
		var max_locks := clampi(2 + puzzle.rotatable_count() / 25, 2, 10)
		var locks := 0
		while int(res["count"]) > 1 and locks < max_locks:
			var cell := _distinguishing_cell(puzzle, res["solutions"], rng)
			if cell < 0:
				break
			puzzle.locked[cell] = 1
			puzzle.start_rot[cell] = 0
			puzzle.finalize()
			locks += 1
			solver = PuzzleSolver.new(puzzle)
			res = solver.solve(2, plan.node_limit)
		if Validator.is_solved_rot(puzzle, puzzle.start_rot):
			Scrambler.scramble(puzzle, rng)
	puzzle.unique = int(res["count"]) == 1 and bool(res["complete"])
	return res


## A free tile whose orientation differs between the stored solution and an
## alternative solution found by the solver.
static func _distinguishing_cell(puzzle: Puzzle, solutions: Array, rng: SeededRng) -> int:
	var candidates := PackedInt32Array()
	for sol in solutions:
		var rot: PackedInt32Array = sol
		for c in puzzle.cell_count():
			if puzzle.active[c] == 0 or puzzle.locked[c] == 1 or puzzle.link_of[c] >= 0:
				continue
			if puzzle.mask_at(c, rot[c]) != puzzle.masks[c]:
				candidates.append(c)
		if not candidates.is_empty():
			break
	if candidates.is_empty():
		return -1
	return candidates[rng.range_int(0, candidates.size() - 1)]


func _is_repeat(fp: String, puzzle: Puzzle) -> bool:
	if avoid_fingerprints.has(fp):
		return true
	if avoid_features.is_empty():
		return false
	var f := Fingerprint.features(puzzle)
	for other in avoid_features:
		if Fingerprint.too_similar(f, other):
			return true
	return false


## Guaranteed-valid tiny LOOP puzzle (only reached if every attempt failed).
static func _fallback(request: PuzzleRequest) -> Puzzle:
	var rng := SeededRng.new(request.seed ^ FALLBACK_SALT)
	var plan := LevelPlan.new()
	plan.mode = GameMode.LOOP
	plan.width = 4
	plan.height = 5
	plan.density = 0.7
	for i in 32:
		var p := build_candidate(plan, rng)
		if p != null and Validator.verify_stored_solution(p) and not Validator.is_solved_rot(p, p.start_rot):
			return p
	# Last resort: a single straight pair, always solvable.
	var topo := TopologyFactory.create(Topology.Kind.SQUARE, 2, 1)
	var p := Puzzle.create(topo)
	p.masks[0] = 0b0010
	p.masks[1] = 0b1000
	p.start_rot[0] = 1
	p.start_rot[1] = 1
	p.finalize()
	return p
