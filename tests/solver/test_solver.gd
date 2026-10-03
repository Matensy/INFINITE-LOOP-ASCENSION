extends TestCase

const N := 1
const E := 2
const S := 4
const W := 8


func _square(w: int, h: int, masks: Array, mode: int = GameMode.LOOP) -> Puzzle:
	var p := Puzzle.create(SquareTopology.new(w, h))
	for i in masks.size():
		p.masks[i] = masks[i]
	p.mode = mode
	p.finalize()
	return p


func test_solves_simple_ring() -> void:
	var p := _square(2, 2, [E | S, W | S, N | E, N | W])
	p.start_rot = PackedInt32Array([1, 2, 3, 1])
	p.finalize()
	var res := PuzzleSolver.new(p).solve()
	assert_eq(int(res["count"]), 1)
	assert_true(bool(res["complete"]))
	var rot: PackedInt32Array = res["solutions"][0]
	assert_true(Validator.is_solved_rot(p, rot))


func test_detects_impossible() -> void:
	# A lone end cap can never be satisfied.
	var p := _square(1, 1, [N])
	var res := PuzzleSolver.new(p).solve()
	assert_eq(int(res["count"]), 0)
	assert_true(bool(res["complete"]), "proved impossible")
	# A 3-cell line with a T in the middle cannot be closed in LOOP mode.
	var q := _square(3, 1, [E, E | W | S, W])
	assert_eq(int(PuzzleSolver.new(q).solve()["count"]), 0)


func test_counts_multiple_solutions() -> void:
	# 2x2 board of two straights + two empties: the straight pair can lie in
	# column 0 vertically ... construct a 2x2 of four ends -> two solutions.
	var p := _square(2, 2, [E, W, E, W])
	var res := PuzzleSolver.new(p).solve(5)
	assert_eq(int(res["count"]), 2, "horizontal or vertical dominoes")
	assert_true(bool(res["complete"]))


func test_core_rule_prunes_islands() -> void:
	# Same four ends in CORE mode with one core: dominoes are islands, so no
	# solution can power everything.
	var p := _square(2, 2, [E, W, E, W], GameMode.CORE)
	p.cores = PackedInt32Array([0])
	p.finalize()
	assert_eq(int(PuzzleSolver.new(p).solve()["count"]), 0)


func test_linked_group_solving() -> void:
	var p := _square(2, 1, [E, W])
	p.link_groups = [PackedInt32Array([0, 1])]
	p.start_rot = PackedInt32Array([1, 1])
	p.finalize()
	var res := PuzzleSolver.new(p).solve()
	assert_eq(int(res["count"]), 1)
	var rot: PackedInt32Array = res["solutions"][0]
	assert_eq(posmod(rot[0] - rot[1], 4), 0, "group members share offset")
	# Inconsistent offsets: no shared rotation fixes both.
	p.start_rot = PackedInt32Array([1, 0])
	p.finalize()
	assert_eq(int(PuzzleSolver.new(p).solve()["count"]), 0)


func test_solver_agrees_with_generator() -> void:
	for lv in [3, 60, 250, 610, 1500]:
		var p := PuzzleGenerator.new().generate(SeedManager.level_request(lv))
		var res := PuzzleSolver.new(p).solve(1, 20000)
		if bool(res["hit_limit"]):
			continue
		assert_eq(int(res["count"]), 1, "level %d solvable" % lv)
		assert_true(Validator.is_solved_rot(p, res["solutions"][0]))


func test_preferred_rotation_guides_search() -> void:
	var p := _square(2, 2, [E, W, E, W])
	var vertical := PackedInt32Array([1, 3, 3, 1])
	assert_true(Validator.is_solved_rot(p, vertical))
	var res := PuzzleSolver.new(p).solve(1, 100, vertical)
	assert_eq(Array(res["solutions"][0]), Array(vertical), "closest solution first")


func test_forced_rotations_are_correct() -> void:
	var p := PuzzleGenerator.new().generate(SeedManager.level_request(25))
	var forced := PuzzleSolver.new(p).forced_rotations()
	var any := false
	for c in p.cell_count():
		if forced[c] >= 0:
			any = true
			if p.unique:
				assert_eq(p.mask_at(c, forced[c]), p.masks[c], "forced cell %d matches unique solution" % c)
	assert_true(any, "propagation forces at least one tile")


func test_node_limit_respected() -> void:
	var req := SeedManager.level_request(2000)
	req.force_mode = GameMode.DARK
	var p := PuzzleGenerator.new().generate(req)
	var res := PuzzleSolver.new(p).solve(1000000, 50)
	assert_true(int(res["nodes"]) <= 51)
