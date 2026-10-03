extends SceneTree
## Prints fingerprints of a level range (generator regression check).
##   godot --headless --path . --script res://tools/fingerprints.gd -- --from=1 --to=300

func _init() -> void:
	GameLog.enabled = false
	DifficultyConfig.load_config()
	ThemeCatalog.load_catalog()
	var from := 1
	var to := 300
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--from="):
			from = arg.substr(7).to_int()
		elif arg.begins_with("--to="):
			to = arg.substr(5).to_int()
	var gen := PuzzleGenerator.new()
	for lv in range(from, to + 1):
		var p := gen.generate(SeedManager.level_request(lv))
		print("%d %s %s" % [lv, p.meta["fingerprint"], str(Array(p.start_rot).hash())])
	for lv in [5000, 12345, 100000, 7777777]:
		var p := gen.generate(SeedManager.level_request(lv))
		print("%d %s %s" % [lv, p.meta["fingerprint"], str(Array(p.start_rot).hash())])
	quit()
