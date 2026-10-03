extends TestCase


func test_curve_is_monotonic_and_unbounded() -> void:
	var prev := 0.0
	for lv in [1, 2, 5, 10, 100, 1000, 10000, 100000, 1000000, 100000000, 1000000000000]:
		var t := DifficultyCurve.target(lv)
		assert_true(t > prev, "T(%d)=%f grows" % [lv, t])
		prev = t
	assert_true(DifficultyCurve.target(100000000) > 2.0 * DifficultyCurve.target(10000))


func test_level_for_target_inverts_curve() -> void:
	for lv in [1, 7, 120, 5000, 123456]:
		var t := DifficultyCurve.target(lv)
		var back := DifficultyCurve.level_for_target(t)
		assert_between(back, lv - 1, lv, "inverse of level %d" % lv)


func test_tiers() -> void:
	assert_eq(DifficultyCurve.tier_id(3.0), "tutorial")
	assert_eq(DifficultyCurve.tier_id(30.0), "normal")
	assert_eq(DifficultyCurve.tier_id(174.0), "brutal")
	assert_eq(DifficultyCurve.tier_id(287.0), "insane")
	assert_eq(DifficultyCurve.tier_id(9999.0), "ascension")
	assert_eq(DifficultyCurve.tier_key(60.0), "TIER_HARD")


func test_analyzer_components() -> void:
	var p := PuzzleGenerator.new().generate(SeedManager.level_request(777))
	var a: Dictionary = p.meta["analysis"]
	assert_true(float(a["score"]) > 0.0)
	assert_true(int(a["decisions"]) > 0)
	assert_true(int(a["min_moves"]) > 0)
	assert_eq(int(a["min_moves"]), DifficultyAnalyzer.min_moves(p))


func test_min_moves_matches_board_state_distance() -> void:
	var p := PuzzleGenerator.new().generate(SeedManager.level_request(42))
	var s := BoardState.new(p)
	var total := 0
	for c in p.cell_count():
		if p.is_rotatable(c) and p.link_of[c] < 0:
			total += s.distance_to(c, 0)
	if p.link_groups.is_empty():
		assert_eq(total, DifficultyAnalyzer.min_moves(p))


func test_planner_respects_overrides() -> void:
	var req := SeedManager.level_request(50)
	req.force_mode = GameMode.MULTI
	req.force_topology = Topology.Kind.HEX
	req.force_target = 120.0
	var plan := LevelPlanner.plan(req)
	assert_eq(plan.mode, GameMode.MULTI)
	assert_eq(plan.topology, Topology.Kind.HEX)
	assert_true(plan.cores >= 2)
	assert_between(plan.target, 119.9, 120.1)


func test_bias_changes_target() -> void:
	var easy := LevelPlanner.plan(SeedManager.level_request(1001, -20))
	var hard := LevelPlanner.plan(SeedManager.level_request(1001, 20))
	assert_true(hard.target > easy.target)


func test_consecutive_levels_vary() -> void:
	# Macro features (mode, topology, shape, size) of neighbouring levels
	# should rarely be identical.
	var same := 0
	var prev := ""
	for lv in range(300, 400):
		var p := LevelPlanner.plan(SeedManager.level_request(lv))
		var key := "%d|%d|%d|%dx%d" % [p.mode, p.topology, p.shape, p.width, p.height]
		if key == prev:
			same += 1
		prev = key
	assert_true(same <= 5, "identical consecutive macro plans: %d" % same)
