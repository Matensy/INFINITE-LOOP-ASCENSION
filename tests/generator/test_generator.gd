extends TestCase
## Generator: determinism, solvability, variety and difficulty trend.


func _gen(req: PuzzleRequest) -> Puzzle:
	return PuzzleGenerator.new().generate(req)


func _assert_playable(p: Puzzle, label: String) -> void:
	assert_eq(Validator.structural_errors(p), "", label + " structure")
	assert_true(Validator.verify_stored_solution(p), label + " stored solution valid")
	assert_false(Validator.is_solved_rot(p, p.start_rot), label + " starts unsolved")
	assert_true(p.rotatable_count() >= 1, label + " has decisions")


func test_same_request_same_puzzle() -> void:
	for lv in [1, 37, 444, 5001]:
		var a := _gen(SeedManager.level_request(lv))
		var b := _gen(SeedManager.level_request(lv))
		assert_eq(a.meta["fingerprint"], b.meta["fingerprint"], "fingerprint level %d" % lv)
		assert_eq(Array(a.masks), Array(b.masks), "masks level %d" % lv)
		assert_eq(Array(a.start_rot), Array(b.start_rot), "scramble level %d" % lv)
		assert_eq(a.mode, b.mode)


func test_code_reproduces_puzzle() -> void:
	var req := SeedManager.level_request(1234, -10)
	var a := _gen(req)
	var b := _gen(SeedManager.parse_code(SeedManager.make_code(req)))
	assert_eq(Array(a.masks), Array(b.masks), "shared code rebuilds identical masks")
	assert_eq(Array(a.start_rot), Array(b.start_rot))


func test_first_levels_are_valid_and_distinct() -> void:
	var seen := {}
	for lv in range(1, 41):
		var p := _gen(SeedManager.level_request(lv))
		_assert_playable(p, "level %d" % lv)
		var fp: String = p.meta["fingerprint"]
		assert_false(seen.has(fp), "level %d duplicates level %s" % [lv, str(seen.get(fp))])
		seen[fp] = lv


func test_every_mode_and_topology() -> void:
	for mode in GameMode.COUNT:
		for topo in [Topology.Kind.SQUARE, Topology.Kind.HEX]:
			var req := SeedManager.level_request(300)
			req.force_mode = mode
			req.force_topology = topo
			var p := _gen(req)
			var label := "%s/%s" % [GameMode.id_of(mode), "hex" if topo == 1 else "square"]
			_assert_playable(p, label)
			assert_eq(p.mode, mode, label)
			assert_eq(p.topology.kind, topo, label)
			if GameMode.uses_cores(mode):
				assert_true(p.cores.size() >= 1, label + " has cores")


func test_every_shape() -> void:
	for shape in BoardShapes.NAMES.size():
		var req := SeedManager.level_request(900)
		req.force_shape = shape
		req.force_mode = GameMode.LOOP
		_assert_playable(_gen(req), "shape " + BoardShapes.shape_name(shape))


func test_special_mechanics_survive_pipeline() -> void:
	var req := SeedManager.level_request(2500)  # chaos event: linked tiles
	var p := _gen(req)
	_assert_playable(p, "chaos")
	assert_true(p.link_groups.size() >= 1, "chaos has linked tiles")
	var portal_req := SeedManager.level_request(7001)
	portal_req.force_mode = GameMode.CORE
	portal_req.force_target = 160.0
	var found_portal := false
	for i in 4:
		portal_req.seed += 1
		var q := _gen(portal_req)
		_assert_playable(q, "portal puzzle")
		if q.portal_count() > 0:
			found_portal = true
			var owner := Connectivity.power(q, Validator.current_masks(q, q.solution_rotations()))
			for c in q.cell_count():
				if q.network_cell[c] == 1:
					assert_true(owner[c] >= 0, "solution powers every cell")
	assert_true(found_portal, "portals generated at high difficulty")


func test_huge_levels_generate() -> void:
	for lv in [100000000, 999999999999]:
		var p := _gen(SeedManager.level_request(lv))
		_assert_playable(p, "level %d" % lv)
		assert_true(float(p.meta["difficulty"]) > 250.0, "huge level is hard")


func test_difficulty_trends_upward() -> void:
	var bands := [[1, 6], [150, 155], [3001, 3006]]
	var means: Array[float] = []
	for band in bands:
		var total := 0.0
		for lv in range(band[0], band[1]):
			total += float(_gen(SeedManager.level_request(lv)).meta["difficulty"])
		means.append(total / (band[1] - band[0]))
	assert_true(means[0] < means[1] and means[1] < means[2], "means %s" % str(means))


func test_unique_puzzles_are_really_unique() -> void:
	var checked := 0
	for lv in range(400, 430):
		var p := _gen(SeedManager.level_request(lv))
		if not p.unique:
			continue
		checked += 1
		var res := PuzzleSolver.new(p).solve(2, 20000)
		assert_eq(int(res["count"]), 1, "level %d unique claim" % lv)
	assert_true(checked > 0, "some unique puzzles in range")


func test_zen_anti_repetition() -> void:
	var gen := PuzzleGenerator.new()
	var req := PuzzleRequest.make(PuzzleRequest.Kind.ZEN, 1, 555)
	var first := gen.generate(req)
	gen.avoid_fingerprints[first.meta["fingerprint"]] = true
	var second := gen.generate(req)
	assert_ne(second.meta["fingerprint"], first.meta["fingerprint"], "avoid list respected")


func test_event_levels() -> void:
	assert_eq(str(LevelPlanner.event_for_level(100).get("id", "")), "galaxy")
	assert_eq(str(LevelPlanner.event_for_level(5000).get("id", "")), "ascension")
	assert_eq(str(LevelPlanner.event_for_level(10000).get("id", "")), "ascension", "events recur forever")
	assert_true(LevelPlanner.event_for_level(101).is_empty())
	var boss := _gen(SeedManager.level_request(1000))
	assert_true(bool(boss.meta["boss"]))
	assert_eq(str(boss.meta["event"]), "void")
