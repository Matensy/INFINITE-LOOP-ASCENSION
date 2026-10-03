extends SceneTree
## Prints a generation report for a range of levels (calibration tool).
##   godot --headless --path . --script res://tools/gen_report.gd -- --levels=1,10,100 --kind=level

func _init() -> void:
	GameLog.enabled = false
	DifficultyConfig.load_config()
	ThemeCatalog.load_catalog()
	var levels: Array = [1, 2, 3, 5, 8, 12, 20, 35, 50, 80, 120, 200, 350, 500, 800, 1000, 2000, 5000, 10000, 50000, 100000, 1000000]
	var forced_mode := -1
	var forced_topo := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--levels="):
			levels = []
			for s in arg.substr(9).split(","):
				levels.append(s.to_int())
		elif arg.begins_with("--mode="):
			forced_mode = GameMode.from_id(arg.substr(7))
		elif arg.begins_with("--topology="):
			forced_topo = TopologyFactory.kind_from_name(arg.substr(11))
	var gen := PuzzleGenerator.new()
	print("level  target  score  tier       mode   topo   shape     size   rot  uniq  nodes  att  ms")
	for lv in levels:
		var req := SeedManager.level_request(int(lv))
		req.force_mode = forced_mode
		req.force_topology = forced_topo
		var p := gen.generate(req)
		var a: Dictionary = p.meta["analysis"]
		print("%-6d %-7.1f %-6.1f %-10s %-6s %-6s %-9s %-6s %-4d %-5s %-6d %-4d %.0f %s" % [
			int(lv), float(p.meta["target"]), float(p.meta["difficulty"]), str(p.meta["tier"]),
			GameMode.id_of(p.mode), p.topology.kind_name(), str(p.meta["shape"]),
			"%dx%d" % [p.topology.width, p.topology.height], int(a["decisions"]), str(p.unique),
			int(p.meta["solver_nodes"]), int(p.meta["attempts"]), float(p.meta["gen_ms"]), str(p.meta["event"])])
	quit()
