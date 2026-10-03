extends TestCase
## Save system: checksum, backup restore, migration, stats, achievements.

const PATH := "user://test_save/save.json"

var store: SaveStore


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://test_save"))
	store = SaveStore.new(PATH)
	store.delete_all()


func after_each() -> void:
	store.delete_all()


func test_defaults_when_missing() -> void:
	var d := store.load_data()
	assert_eq(store.last_load_source, "defaults")
	assert_eq(int(d["progress"]["current_level"]), 1)
	assert_true(d["settings"].has("haptics"))


func test_roundtrip() -> void:
	var d := SaveStore.defaults()
	d["progress"]["current_level"] = 42
	d["progress"]["highest_level"] = 42
	assert_true(store.save_data(d))
	var back := store.load_data()
	assert_eq(store.last_load_source, "main")
	assert_eq(int(back["progress"]["current_level"]), 42)


func test_corruption_restores_backup() -> void:
	var d := SaveStore.defaults()
	d["progress"]["current_level"] = 10
	store.save_data(d)
	d["progress"]["current_level"] = 11
	store.save_data(d)  # backup now holds level 10
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var back := store.load_data()
	assert_eq(store.last_load_source, "backup")
	assert_eq(int(back["progress"]["current_level"]), 10)
	assert_true(FileAccess.file_exists(PATH + ".corrupt"), "corrupt file kept for inspection")


func test_tampered_checksum_is_rejected() -> void:
	var d := SaveStore.defaults()
	store.save_data(d)
	var env: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	env["payload"] = str(env["payload"]).replace("\"current_level\":1", "\"current_level\":999")
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(env))
	f.close()
	var back := store.load_data()
	assert_ne(int(back["progress"]["current_level"]), 999)


func test_migration_from_v1() -> void:
	var old := {"current_level": 7, "highest_level": 9, "stats": {"total_solved": 3}}
	var payload := JSON.stringify(old)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "checksum": payload.sha256_text(), "payload": payload}))
	f.close()
	var d := store.load_data()
	assert_eq(int(d["version"]), SaveStore.VERSION)
	assert_eq(int(d["progress"]["current_level"]), 7)
	assert_eq(int(d["progress"]["highest_level"]), 9)
	assert_eq(int(d["stats"]["total_solved"]), 3)
	assert_true(d["stats"].has("perfect_solves"), "missing keys completed")


func test_statistics_and_streaks() -> void:
	var stats := Statistics.defaults()
	Statistics.record_solve(stats, {"difficulty": 30.0, "moves": 20, "time": 40.0, "hints": 0, "perfect": true,
		"mode": "loop", "tier": "normal", "day": "2026-10-01", "code": "A"})
	Statistics.record_solve(stats, {"difficulty": 80.0, "moves": 50, "time": 25.0, "hints": 1,
		"mode": "core", "tier": "very_hard", "day": "2026-10-02", "code": "B"})
	Statistics.record_solve(stats, {"difficulty": 12.0, "moves": 9, "time": 8.0, "hints": 0, "mode": "loop", "tier": "easy", "day": "2026-10-04"})
	assert_eq(int(stats["total_solved"]), 3)
	assert_eq(int(stats["perfect_solves"]), 1)
	assert_eq(float(stats["hardest_solve"]), 80.0)
	assert_eq(str(stats["hardest_code"]), "B")
	assert_eq(float(stats["fastest_solve"]), 8.0)
	assert_eq(int(stats["fewest_moves"]), 9)
	assert_eq(int(stats["longest_streak"]), 2)
	assert_eq(int(stats["current_streak"]), 1, "gap breaks the streak")
	assert_between(Statistics.average_moves(stats), 26.3, 26.4)


func test_achievements() -> void:
	var save := SaveStore.defaults()
	Statistics.record_solve(save["stats"], {"difficulty": 200.0, "moves": 10, "time": 12.0, "hints": 0,
		"mode": "dark", "tier": "insane", "day": "2026-10-03"})
	var fresh := AchievementSystem.evaluate(save, {"difficulty": 200.0, "hints": 0, "time": 12.0, "perfect": false,
		"mechanics": ["portal"], "gestures": {}})
	for id in ["first_loop", "first_insane", "first_brutal", "no_hint", "speed_solver", "dark_side", "portal_jumper", "one_handed"]:
		assert_true(fresh.has(id), "unlocked " + id)
	assert_false(fresh.has("first_nightmare"))
	assert_eq(AchievementSystem.evaluate(save, {}).size(), 0, "not unlocked twice")


func test_adaptive_bias_moves_both_ways() -> void:
	var st := AdaptiveDifficulty.defaults()
	for i in 8:
		AdaptiveDifficulty.update(st, {"min_moves": 20, "moves": 21, "time": 15.0, "hints": 0, "difficulty": 40.0})
	assert_true(AdaptiveDifficulty.current_bias(st) > 0, "fast solver gets harder levels")
	for i in 16:
		AdaptiveDifficulty.update(st, {"min_moves": 20, "moves": 90, "time": 400.0, "hints": 3, "difficulty": 40.0})
	assert_true(AdaptiveDifficulty.current_bias(st) < 0, "struggling player gets easier levels")
	assert_between(AdaptiveDifficulty.current_bias(st), AdaptiveDifficulty.MIN_BIAS, AdaptiveDifficulty.MAX_BIAS)


func test_level_cache_lru() -> void:
	var cache := LevelCache.new("user://test_save/cache.json")
	var first := SeedManager.level_request(1)
	cache.put(first, PuzzleGenerator.new().generate(first))
	for lv in range(2, 12):
		var r := SeedManager.level_request(lv)
		cache.put(r, PuzzleGenerator.new().generate(r))
	assert_eq(cache.size(), LevelCache.MAX_ENTRIES)
	assert_eq(cache.get_puzzle(first), null, "oldest evicted")
	var last := SeedManager.level_request(11)
	var p := cache.get_puzzle(last)
	assert_not_null(p)
	assert_eq(str(p.meta["fingerprint"]), str(PuzzleGenerator.new().generate(last).meta["fingerprint"]))
	cache.save_cache()
	var again := LevelCache.new("user://test_save/cache.json")
	again.load_cache()
	assert_eq(again.size(), LevelCache.MAX_ENTRIES)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_save/cache.json"))


func test_telemetry_ring_buffer() -> void:
	var save := SaveStore.defaults()
	for i in Telemetry.MAX_RECORDS + 20:
		Telemetry.record(save, {"event": "solve", "solve_time": 10.0, "moves": 5, "difficulty": 20.0, "generation_ms": 3.0})
	assert_eq((save["telemetry"] as Array).size(), Telemetry.MAX_RECORDS)
	var sm := Telemetry.summary(save)
	assert_eq(int(sm["solves"]), Telemetry.MAX_RECORDS)
	assert_between(float(sm["avg_generation_ms"]), 2.9, 3.1)
