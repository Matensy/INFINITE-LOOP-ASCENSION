extends SceneTree
## Captures real rendered screenshots (needs a display, e.g. xvfb-run).
##   xvfb-run -s "-screen 0 720x1280x24" godot --path . --resolution 720x1280 \
##       --script res://tools/screenshot.gd -- --ephemeral-save --out=/tmp/shots
## Shots: menu, game (several levels/modes), victory, results, settings,
## profile, debug.

var _out := "user://screenshots"
var _main: Node
var _game_node: Node


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _out.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)


func _wait_session(g: Node) -> void:
	for i in 1200:
		if g.session != null:
			return
		await process_frame


func _run() -> void:
	var save := root.get_node("Save")
	_game_node = root.get_node("Game")
	save.set_setting("music", false)
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(40)
	await _shot("01_menu")

	var shots := [
		["02_level_1", SeedManager.level_request(1)],
		["03_level_12_core", SeedManager.level_request(12)],
		["04_level_44_dark", SeedManager.level_request(44)],
		["05_level_333_multi", SeedManager.level_request(333)],
		["06_level_444_hex", SeedManager.level_request(444)],
		["07_level_2500_chaos", SeedManager.level_request(2500)],
		["08_level_7001_portals", _portal_request()],
		["09_level_33333_big", SeedManager.level_request(33333)],
	]
	for s in shots:
		_game_node.pending_request = s[1]
		_main.goto("game")
		await _frames(2)
		var g: Node = _main.current
		await _wait_session(g)
		await _frames(10)
		g._close_overlay()
		# Rotate a few tiles so some connections are visibly open/closed.
		await _frames(30)
		await _shot(s[0])

	# Victory sequence + results on a mid-size puzzle.
	_game_node.pending_request = SeedManager.level_request(80)
	_main.goto("game")
	await _frames(2)
	var game: Node = _main.current
	await _wait_session(game)
	await _frames(5)
	game._close_overlay()
	var hint := HintSystem.make_hint(5, game.session)
	var all: Dictionary = hint["rotations"]
	var keys := all.keys()
	# Apply all but one tile, then solve with a real tap.
	var last: int = keys[keys.size() - 1]
	all.erase(last)
	game.session.apply_hint(hint)
	game.board.refresh()
	await _frames(10)
	await _shot("10_almost_solved")
	var target := HintSystem.closest_solution(game.session.puzzle, game.session.state)
	var guard := 0
	while not game.session.solved and guard < 6:
		game._on_cell_tapped(last, 1)
		guard += 1
		if not game.session.state.matches(last, target[last]):
			continue
	await _frames(18)
	await _shot("11_victory_wave")
	await _frames(70)
	await _shot("12_results")

	for screen in ["settings", "profile", "debug"]:
		_main.goto(screen)
		await _frames(25)
		await _shot("13_" + screen)
	quit()


func _portal_request() -> PuzzleRequest:
	var r := SeedManager.level_request(7001)
	r.force_mode = GameMode.CORE
	return r
