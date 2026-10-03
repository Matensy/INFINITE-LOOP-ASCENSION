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

# Incremental state (begin / step / result). Each step runs exactly one
# candidate attempt, so callers can spread generation across frames on the
# main thread without changing the (deterministic) outcome.
var _request: PuzzleRequest
var _plan: LevelPlan
var _rng: SeededRng
var _current: LevelPlan
var _attempt := 0
var _attempts := 0
var _invalid := 0
var _rejected_similar := 0
var _best: Puzzle
var _best_err := INF
var _best_analysis: Dictionary = {}
var _best_solve: Dictionary = {}
var _elapsed_usec := 0
var _done := true
var _result: Puzzle


## Generates the whole puzzle synchronously.
func generate(request: PuzzleRequest) -> Puzzle:
	begin(request)
	while not step():
		pass
	return result()


## Starts an incremental generation.
func begin(request: PuzzleRequest) -> void:
	var t0 := Time.get_ticks_usec()
	_request = request
	_plan = LevelPlanner.plan(request)
	_rng = SeededRng.new(request.seed)
	_current = _plan
	_attempt = 0
	_attempts = 0
	_invalid = 0
	_rejected_similar = 0
	_best = null
	_best_err = INF
	_best_analysis = {}
	_best_solve = {}
	_result = null
	_done = false
	GameLog.info("GENERATOR", "seed=%d level=%d kind=%s target=%.1f mode=%s %dx%d %s" % [
		request.seed, request.level, request.kind_id(), _plan.target, GameMode.id_of(_plan.mode),
		_plan.width, _plan.height, BoardShapes.shape_name(_plan.shape)])
	_elapsed_usec = Time.get_ticks_usec() - t0


func is_done() -> bool:
	return _done


func result() -> Puzzle:
	return _result


## Runs one candidate attempt. Returns true when the puzzle is finished.
func step() -> bool:
	if _done:
		return true
	var t0 := Time.get_ticks_usec()
	var finished := _run_attempt()
	_attempt += 1
	if finished or _attempt >= _plan.max_attempts:
		_finish()
	_elapsed_usec += Time.get_ticks_usec() - t0
	if _done and _result:
		_result.meta["gen_ms"] = snappedf(_elapsed_usec / 1000.0, 0.01)
		last_report["gen_ms"] = _elapsed_usec / 1000.0
	return _done


## One attempt of the closed loop. Returns true to stop early.
func _run_attempt() -> bool:
	var plan := _plan
	var current := _current
	_attempts += 1
	var cand_rng := _rng.fork(_attempt + 1)
	var puzzle := build_candidate(current, cand_rng)
	if puzzle == null:
		_invalid += 1
		return false
	var problem := Validator.structural_errors(puzzle)
	if problem != "" or not Validator.verify_stored_solution(puzzle):
		_invalid += 1
		GameLog.error("VALIDATOR", "candidate rejected: %s" % (problem if problem != "" else "stored solution invalid"))
		return false
	var solve := _solve_and_disambiguate(puzzle, current, cand_rng)
	var analysis := DifficultyAnalyzer.analyze(puzzle, solve)
	var score: float = analysis["score"]
	var fp := Fingerprint.compute(puzzle)
	if _is_repeat(fp, puzzle):
		_rejected_similar += 1
		GameLog.debug("GENERATOR", "attempt %d rejected as repeat" % _attempt)
		return false
	var err := absf(log(score / plan.target))
	if current.require_unique and not puzzle.unique:
		err += 0.6
	GameLog.debug("DIFFICULTY", "attempt %d score=%.1f target=%.1f err=%.2f" % [_attempt, score, plan.target, err])
	if err < _best_err:
		_best_err = err
		_best = puzzle
		_best_analysis = analysis
		_best_solve = solve
		_best.meta["fingerprint"] = fp
	if err <= plan.tolerance:
		return true
	if current.require_unique and not puzzle.unique and _attempts >= 3:
		# Uniqueness keeps failing for this layout: relax PERFECT rather
		# than burn the remaining attempts (bounded generation time).
		current = current.duplicate_plan()
		current.require_unique = false
	var expo := float(DifficultyConfig.value("planner", "expected_tile_exponent", 0.9))
	var next := LevelPlanner.rescale(current, pow(plan.target / maxf(score, 0.5), 1.0 / expo))
	if next.width == current.width and next.height == current.height and not (current.require_unique and not puzzle.unique):
		# The board cannot be steered any further (e.g. maximum size for an
		# extreme target): keep the best candidate instead of spinning.
		_current = current
		return true
	_current = next
	return false


func _finish() -> void:
	var request := _request
	var plan := _plan
	if _best == null:
		GameLog.warn("GENERATOR", "all attempts failed, using fallback puzzle")
		_best = _fallback(request)
		_best_solve = PuzzleSolver.new(_best).solve(2, plan.node_limit)
		_best_analysis = DifficultyAnalyzer.analyze(_best, _best_solve)
		_best.meta["fingerprint"] = Fingerprint.compute(_best)
	var best := _best
	best.meta.merge({
		"seed": request.seed,
		"level": request.level,
		"kind": request.kind_id(),
		"bias": request.bias,
		"code": SeedManager.make_code(request),
		"label": request.label,
		"target": snappedf(plan.target, 0.1),
		"difficulty": _best_analysis.get("score", 1.0),
		"tier": _best_analysis.get("tier", "tutorial"),
		"min_moves": _best_analysis.get("min_moves", 0),
		"theme": plan.theme,
		"shape": BoardShapes.shape_name(plan.shape),
		"event": plan.event,
		"boss": plan.boss,
		"plan": plan.to_dict(),
		"analysis": _best_analysis,
		"solver_nodes": _best_solve.get("nodes", 0),
		"solver_limited": _best_solve.get("hit_limit", false),
		"attempts": _attempts,
	}, true)
	last_report = {
		"attempts": _attempts, "invalid": _invalid, "rejected_similar": _rejected_similar,
		"error": _best_err,
	}
	GameLog.info("DIFFICULTY", "score=%.1f tier=%s unique=%s attempts=%d" % [
		float(_best_analysis.get("score", 0)), str(_best_analysis.get("tier", "")), str(best.unique), _attempts])
	GameLog.info("VALIDATOR", "PASS fingerprint=%s" % best.meta["fingerprint"])
	_result = best
	_done = true


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
