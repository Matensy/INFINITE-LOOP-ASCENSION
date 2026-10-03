extends SceneTree
## Generator stress test.
##
##   godot --headless --path . --script res://tests/performance/stress_test.gd -- \
##       --count=100000 [--start=1] [--step=1] [--shard=0/4] [--sample=log] \
##       [--no-verify] [--json=res://tests/output/stress.json]
##
## For every puzzle: structural validation, stored-solution validation, an
## independent solver pass (unless --no-verify), exact duplicate detection
## (canonical fingerprints), timing, difficulty and memory tracking.
## Exit code 1 if any puzzle is invalid/impossible or any engine error occurs.

class ErrorCounter:
	extends Logger
	var count := 0
	var samples: PackedStringArray = PackedStringArray()
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		count += 1
		if samples.size() < 10:
			samples.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
		_mutex.unlock()


func _init() -> void:
	GameLog.enabled = false
	DifficultyConfig.load_config()
	ThemeCatalog.load_catalog()
	var count := 1000
	var start := 1
	var step := 1
	var shard := 0
	var shards := 1
	var verify := true
	var log_sample := false
	var json_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			count = arg.substr(8).to_int()
		elif arg.begins_with("--start="):
			start = arg.substr(8).to_int()
		elif arg.begins_with("--step="):
			step = maxi(1, arg.substr(7).to_int())
		elif arg.begins_with("--shard="):
			var parts := arg.substr(8).split("/")
			shard = parts[0].to_int()
			shards = maxi(1, parts[1].to_int())
		elif arg == "--no-verify":
			verify = false
		elif arg == "--sample=log":
			log_sample = true
		elif arg.begins_with("--json="):
			json_path = arg.substr(7)

	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var gen := PuzzleGenerator.new()
	var fingerprints := {}
	var stats := {
		"generated": 0, "valid": 0, "invalid": 0, "impossible": 0, "duplicates": 0,
		"solver_limited": 0, "unique": 0, "total_ms": 0.0, "max_ms": 0.0, "max_ms_level": 0,
		"total_difficulty": 0.0, "max_difficulty": 0.0, "tiers": {}, "modes": {}, "topologies": {},
		"duplicate_examples": [], "invalid_examples": [],
	}
	var mem_start := OS.get_static_memory_usage()
	var mem_peak := mem_start
	var t_all := Time.get_ticks_msec()
	var i := shard
	while i < count:
		var level := start + i * step
		if log_sample:
			# Spread samples log-uniformly over [1, 10^9]; index i keeps the
			# low end strictly increasing so no level is sampled twice.
			level = maxi(i + 1, int(pow(10.0, 9.0 * float(i) / float(maxi(1, count - 1)))))
		i += shards
		var req := SeedManager.level_request(level)
		var t0 := Time.get_ticks_usec()
		var p := gen.generate(req)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		stats["generated"] += 1
		stats["total_ms"] += ms
		if ms > float(stats["max_ms"]):
			stats["max_ms"] = ms
			stats["max_ms_level"] = level
		var ok := Validator.structural_errors(p) == "" and Validator.verify_stored_solution(p) \
				and not Validator.is_solved_rot(p, p.start_rot)
		if verify and ok:
			var res := PuzzleSolver.new(p).solve(1, 4000)
			if int(res["count"]) == 0 and bool(res["complete"]):
				stats["impossible"] += 1
				ok = false
			elif bool(res["hit_limit"]):
				stats["solver_limited"] += 1
		if ok:
			stats["valid"] += 1
		else:
			stats["invalid"] += 1
			if stats["invalid_examples"].size() < 10:
				stats["invalid_examples"].append(level)
		var fp: String = p.meta["fingerprint"]
		if fingerprints.has(fp):
			stats["duplicates"] += 1
			if stats["duplicate_examples"].size() < 10:
				stats["duplicate_examples"].append([fingerprints[fp], level])
		else:
			fingerprints[fp] = level
		if p.unique:
			stats["unique"] += 1
		var diff := float(p.meta["difficulty"])
		stats["total_difficulty"] += diff
		stats["max_difficulty"] = maxf(float(stats["max_difficulty"]), diff)
		_bump(stats["tiers"], str(p.meta["tier"]))
		_bump(stats["modes"], GameMode.id_of(p.mode))
		_bump(stats["topologies"], p.topology.kind_name())
		mem_peak = maxi(mem_peak, OS.get_static_memory_usage())
		if int(stats["generated"]) % 1000 == 0:
			print("... %d generated (%.1f ms avg, level %d)" % [stats["generated"], float(stats["total_ms"]) / float(stats["generated"]), level])

	OS.remove_logger(counter)
	var n := maxi(1, int(stats["generated"]))
	var report := {
		"generated": stats["generated"],
		"valid": stats["valid"],
		"invalid": stats["invalid"],
		"impossible": stats["impossible"],
		"duplicates": stats["duplicates"],
		"duplicate_examples": stats["duplicate_examples"],
		"invalid_examples": stats["invalid_examples"],
		"solver_limited": stats["solver_limited"],
		"unique_fraction": snappedf(float(stats["unique"]) / n, 0.001),
		"average_generation_ms": snappedf(float(stats["total_ms"]) / n, 0.01),
		"max_generation_ms": snappedf(float(stats["max_ms"]), 0.01),
		"max_generation_level": stats["max_ms_level"],
		"average_difficulty": snappedf(float(stats["total_difficulty"]) / n, 0.1),
		"max_difficulty": stats["max_difficulty"],
		"tiers": stats["tiers"],
		"modes": stats["modes"],
		"topologies": stats["topologies"],
		"engine_errors": counter.count,
		"error_samples": counter.samples,
		"memory_start_mb": snappedf(mem_start / 1048576.0, 0.01),
		"memory_end_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.01),
		"memory_peak_mb": snappedf(mem_peak / 1048576.0, 0.01),
		"wall_seconds": snappedf((Time.get_ticks_msec() - t_all) / 1000.0, 0.1),
		"shard": "%d/%d" % [shard, shards],
	}
	print("")
	print("Generated: %d" % report["generated"])
	print("Valid: %d" % report["valid"])
	print("Invalid: %d" % report["invalid"])
	print("Impossible: %d" % report["impossible"])
	print("Duplicate: %d" % report["duplicates"])
	print("Average Difficulty: %.1f" % report["average_difficulty"])
	print("Average Generation Time: %.1fms" % report["average_generation_ms"])
	print("Errors: %d" % report["engine_errors"])
	print(JSON.stringify(report, "  "))
	if json_path != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(json_path.get_base_dir()))
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(report, "  "))
	var failed := int(report["invalid"]) > 0 or int(report["impossible"]) > 0 or counter.count > 0
	quit(1 if failed else 0)


func _bump(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1
