extends TestCase
## Coarse performance guards (generous bounds so CI machines never flake;
## the stress test reports precise numbers).


func _ms(start_usec: int) -> float:
	return (Time.get_ticks_usec() - start_usec) / 1000.0


func test_generation_time_by_tier() -> void:
	var budgets := {50: 400.0, 5000: 2500.0, 100000: 6000.0}
	for lv in budgets.keys():
		var t0 := Time.get_ticks_usec()
		var p := PuzzleGenerator.new().generate(SeedManager.level_request(lv))
		var ms := _ms(t0)
		assert_true(ms < float(budgets[lv]), "level %d generated in %.0f ms (budget %.0f)" % [lv, ms, budgets[lv]])
		assert_true(Validator.verify_stored_solution(p))


func test_solver_on_large_board() -> void:
	var req := SeedManager.level_request(60000)
	req.force_mode = GameMode.CORE
	var p := PuzzleGenerator.new().generate(req)
	var t0 := Time.get_ticks_usec()
	var res := PuzzleSolver.new(p).solve(1, 6000)
	var ms := _ms(t0)
	assert_true(ms < 4000.0, "solver on %dx%d took %.0f ms" % [p.topology.width, p.topology.height, ms])
	assert_true(int(res["count"]) == 1 or bool(res["hit_limit"]))


func test_win_check_is_cheap() -> void:
	var p := PuzzleGenerator.new().generate(SeedManager.level_request(200000))
	var s := BoardState.new(p)
	var t0 := Time.get_ticks_usec()
	for i in 50:
		s.is_solved()
	var per_check := _ms(t0) / 50.0
	assert_true(per_check < 25.0, "win check on %d cells: %.2f ms" % [p.cell_count(), per_check])


func test_hint_on_big_board() -> void:
	var req := SeedManager.level_request(40000)
	var s := GameSession.new(PuzzleGenerator.new().generate(req), req)
	var t0 := Time.get_ticks_usec()
	var h := HintSystem.make_hint(2, s)
	var ms := _ms(t0)
	assert_false(h.is_empty())
	assert_true(ms < 5000.0, "hint computed in %.0f ms" % ms)


func test_no_memory_growth_over_many_generations() -> void:
	var gen := PuzzleGenerator.new()
	for i in 20:
		gen.generate(SeedManager.level_request(1000 + i))
	var before := OS.get_static_memory_usage()
	for i in 150:
		gen.generate(SeedManager.level_request(2000 + i))
	var growth_mb := (OS.get_static_memory_usage() - before) / 1048576.0
	assert_true(growth_mb < 8.0, "static memory grew %.2f MB over 150 generations" % growth_mb)
