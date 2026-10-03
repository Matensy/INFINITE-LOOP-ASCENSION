extends TestCase
## Gameplay session: rotation, undo, reset, win, hints, replay data, pins.


func _session(level: int = 30) -> GameSession:
	var req := SeedManager.level_request(level)
	return GameSession.new(PuzzleGenerator.new().generate(req), req)


func _solve_by_taps(s: GameSession) -> void:
	# Tap every tile clockwise until it shows its stored-solution mask.
	var dc := s.puzzle.dir_count()
	var done_groups := {}
	for c in s.puzzle.cell_count():
		if not s.puzzle.is_rotatable(c):
			continue
		var g := s.puzzle.link_of[c]
		if g >= 0:
			if done_groups.has(g):
				continue
			done_groups[g] = true
		var guard := 0
		while not s.state.matches(c, 0) and guard < dc:
			s.rotate(c, 1)
			guard += 1


func test_tap_rotates_and_counts_moves() -> void:
	var s := _session()
	var c := -1
	for i in s.puzzle.cell_count():
		if s.puzzle.is_rotatable(i):
			c = i
			break
	var before := s.state.mask(c)
	var r := s.rotate(c, 1)
	assert_false(bool(r["refused"]))
	assert_eq(s.moves, 1)
	assert_ne(s.state.mask(c), before)
	s.undo()
	assert_eq(s.state.mask(c), before, "undo restores")
	assert_eq(s.undos, 1)


func test_full_solve_by_taps_triggers_win() -> void:
	var s := _session(45)
	var got := [false]
	s.solved_changed.connect(func(v: bool): got[0] = v)
	_solve_by_taps(s)
	assert_true(s.solved, "board solved")
	assert_true(got[0], "signal emitted")
	assert_true(s.moves >= int(s.puzzle.meta["min_moves"]))
	var r := s.rotate(0, 1)
	assert_true(bool(r["refused"]), "no moves after solve")


func test_reset_restores_scramble() -> void:
	var s := _session()
	var start := s.state.snapshot()
	for c in s.puzzle.cell_count():
		if s.puzzle.is_rotatable(c):
			s.rotate(c, 1)
	s.reset()
	assert_eq(Array(s.state.rot), Array(start))
	assert_false(s.can_undo())


func test_locked_and_pinned_refuse() -> void:
	var s := _session(3)
	var locked := s.puzzle.locked.find(1)
	if locked >= 0:
		assert_true(bool(s.rotate(locked, 1)["refused"]))
	var c := 0
	while not s.puzzle.is_rotatable(c):
		c += 1
	s.toggle_pin(c)
	assert_true(bool(s.rotate(c, 1)["refused"]), "pinned tile ignores taps")
	s.toggle_pin(c)
	assert_false(bool(s.rotate(c, 1)["refused"]))


func test_hint_levels() -> void:
	var s := _session(120)
	var h1 := HintSystem.make_hint(1, s)
	assert_eq(int(h1["level"]), 1)
	assert_true((h1["rotations"] as Dictionary).is_empty(), "level 1 only highlights")
	assert_true(int(h1["focus"]) >= 0)
	var wrong_before := HintSystem.wrong_cells(s.puzzle, s.state, HintSystem.closest_solution(s.puzzle, s.state)).size()
	var h2 := HintSystem.make_hint(2, s)
	assert_true((h2["rotations"] as Dictionary).size() >= 1)
	s.apply_hint(h2)
	var wrong_after := HintSystem.wrong_cells(s.puzzle, s.state, HintSystem.closest_solution(s.puzzle, s.state)).size()
	assert_true(wrong_after < wrong_before, "hint 2 fixes a tile (%d -> %d)" % [wrong_before, wrong_after])
	var h5 := HintSystem.make_hint(5, s)
	s.apply_hint(h5)
	assert_true(s.solved, "hint 5 reveals the full solution")
	assert_eq(s.hints_used, 2)
	assert_eq(s.max_hint_level, 5)
	assert_false(s.is_perfect())
	assert_true(HintSystem.make_hint(1, s).is_empty(), "no hints once solved")


func test_hint_on_core_and_linked_puzzles() -> void:
	var req := SeedManager.level_request(2500)
	var s := GameSession.new(PuzzleGenerator.new().generate(req), req)
	var h := HintSystem.make_hint(4, s)
	s.apply_hint(h)
	s.apply_hint(HintSystem.make_hint(5, s))
	assert_true(s.solved)


func test_replay_log_reconstructs_final_state() -> void:
	var s := _session(60)
	_solve_by_taps(s)
	var replay := BoardState.new(s.puzzle)
	for i in s.replay_cells.size():
		var c := s.replay_cells[i]
		if c < 0:
			replay.reset()
		else:
			replay.rotate(c, s.replay_steps[i])
	assert_true(replay.is_solved(), "replaying the log solves the board")
	assert_eq(Array(replay.rot), Array(s.state.rot))


func test_save_and_restore_progress() -> void:
	var s := _session(80)
	for c in s.puzzle.cell_count():
		if s.puzzle.is_rotatable(c):
			s.rotate(c, 1)
			break
	s.elapsed = 12.5
	var data: Dictionary = JSON.parse_string(JSON.stringify(s.to_save()))
	var req := PuzzleRequest.from_dict(data["request"])
	var s2 := GameSession.new(PuzzleGenerator.new().generate(req), req)
	assert_true(s2.restore(data))
	assert_eq(Array(s2.state.rot), Array(s.state.rot))
	assert_eq(s2.moves, 1)
	assert_between(s2.elapsed, 12.4, 12.6)
	var other := _session(81)
	assert_false(other.restore(data), "progress of another puzzle is rejected")


func test_timer_stops_when_paused_or_solved() -> void:
	var s := _session(10)
	s.tick(1.0)
	s.paused = true
	s.tick(5.0)
	s.paused = false
	assert_between(s.elapsed, 0.99, 1.01)
	_solve_by_taps(s)
	s.tick(3.0)
	assert_between(s.elapsed, 0.99, 1.01)
