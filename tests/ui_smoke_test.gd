extends SceneTree
## End-to-end smoke test of the real UI (headless):
##   menu -> continue -> solve level by taps -> victory -> results -> next
##   -> hints -> pause -> settings -> profile -> debug -> zen -> daily -> menu
## Fails on any engine/script error.
##   godot --headless --path . --script res://tests/ui_smoke_test.gd -- --ephemeral-save

class ErrorCounter:
	extends Logger
	var errors: PackedStringArray = PackedStringArray()
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
		_mutex.unlock()


var _counter := ErrorCounter.new()
var _main: Node
var _save: Node
var _game: Node
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	OS.add_logger(_counter)
	GameLog.enabled = false
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   " + msg)
	else:
		print("  FAIL " + msg)
		_failures.append(msg)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait_for(cond: Callable, max_frames: int = 600) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await process_frame
	return false


func _screen() -> Node:
	return _main.current


func _run() -> void:
	_save = root.get_node("Save")
	_game = root.get_node("Game")
	var scene: PackedScene = load("res://scenes/main/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)
	await _frames(5)
	_check(_main.current_name == "menu", "main menu shown")

	# --- Continue: play level 1 to completion by tapping tiles. -------------
	_main.goto("game")
	await _frames(2)
	var game := _screen()
	_check(await _wait_for(func(): return game.session != null), "level generated")
	var session: GameSession = game.session
	_check(session.request.kind == PuzzleRequest.Kind.LEVEL, "continue opens a LEVEL")
	await _solve_by_taps(game)
	_check(session.solved, "level solved through the UI tap path")
	_check(await _wait_for(func(): return game._overlay != null, 900), "results overlay after victory sequence")
	_check(_save.current_level() == 2, "progress advanced to level 2")
	_check(int(_save.stats().get("total_solved", 0)) == 1, "stats recorded")
	_check((_save.data["achievements"] as Dictionary).has("first_loop"), "achievement unlocked")

	# --- Next level, hints, undo, pause. --------------------------------------
	game._on_next()
	_check(await _wait_for(func(): return game.session != null and game.session.request.level == 2), "next level loaded")
	session = game.session
	var cell := _first_rotatable(session.puzzle)
	game._on_cell_tapped(cell, 1)
	_check(session.moves == 1, "tap counted")
	game._on_undo()
	_check(session.undos == 1, "undo works")
	game._on_cell_double_tapped(cell)
	_check(session.pinned[cell] == 1, "double tap pins")
	game._on_cell_double_tapped(cell)
	game._use_hint(1)
	game._use_hint(2)
	_check(session.hints_used == 2, "hints applied")
	game._open_pause()
	_check(game._overlay != null and session.paused, "pause overlay")
	game._close_overlay()
	game._use_hint(5)
	_check(session.solved, "hint 5 solves")
	await _wait_for(func(): return game._overlay != null, 900)
	game._on_share()
	game._on_favorite()
	_check(_game.is_favorite(game.session.code()), "favourite stored")
	game._on_replay()
	_check(await _wait_for(func(): return game._overlay != null and not game._replaying, 1500), "replay finished")

	# --- Other screens. --------------------------------------------------------
	for screen in ["settings", "profile", "debug", "menu"]:
		_main.goto(screen)
		await _frames(8)
		_check(_main.current_name == screen, "screen " + screen)
	_save.set_setting("left_handed", true)
	_save.set_setting("high_contrast", true)
	_save.set_setting("colorblind", true)
	_save.set_setting("language", "pt_BR")
	await _frames(4)
	_check(TranslationServer.get_locale().begins_with("pt"), "language switch")
	_save.set_setting("language", "en_US")

	# --- Zen, daily, challenge, shared code. -------------------------------------
	for req in [_game.zen_request(), _game.daily_request(), _game.challenge_request(0), SeedManager.parse_code("ASCENSION-5000-123456789012")]:
		_game.pending_request = req
		_main.goto("game")
		await _frames(2)
		var g := _screen()
		_check(await _wait_for(func(): return g.session != null, 2400), "%s puzzle loads" % req.kind_id())
		await _frames(30)
	_main.goto("menu")
	await _frames(5)

	var errs := _counter.errors
	for e in errs:
		print("  ENGINE ERROR " + e)
	OS.remove_logger(_counter)
	var ok := _failures.is_empty() and errs.is_empty()
	print("UI SMOKE TEST: %s (%d failures, %d engine errors)" % ["PASS" if ok else "FAIL", _failures.size(), errs.size()])
	quit(0 if ok else 1)


func _first_rotatable(p: Puzzle) -> int:
	for c in p.cell_count():
		if p.is_rotatable(c):
			return c
	return 0


func _solve_by_taps(game: Node) -> void:
	var s: GameSession = game.session
	var dc := s.puzzle.dir_count()
	var groups := {}
	for c in s.puzzle.cell_count():
		if not s.puzzle.is_rotatable(c) or s.solved:
			continue
		var g := s.puzzle.link_of[c]
		if g >= 0:
			if groups.has(g):
				continue
			groups[g] = true
		var guard := 0
		while not s.state.matches(c, 0) and guard < dc and not s.solved:
			game._on_cell_tapped(c, 1)
			guard += 1
			await process_frame
