extends TestCase


func test_rng_is_deterministic() -> void:
	var a := SeededRng.new(839204918230)
	var b := SeededRng.new(839204918230)
	for i in 200:
		assert_eq(a.next_u32(), b.next_u32())


func test_rng_golden_values() -> void:
	# Regression guard: these values were cross-checked against an independent
	# Python implementation of xoshiro128**. Changing the PRNG would silently
	# change every level ever generated.
	var r := SeededRng.new(1)
	assert_eq(r.next_u32(), 1340571627)
	assert_eq(r.next_u32(), 399410527)
	assert_eq(r.next_u32(), 3718193537)
	assert_eq(r.next_u32(), 1918321543)
	assert_eq(SeedManager.level_seed(1), 756681667799)
	assert_eq(SeedManager.level_seed(1000), 427134717714)
	assert_eq(SeededRng.mul32(0xFFFFFFFF, 0xFFFFFFFF), 1, "mul32 wraps mod 2^32")
	assert_eq(SeededRng.mul32(65536, 65536), 0)
	assert_eq(SeededRng.rotl(0x80000000, 1), 1)
	assert_eq(SeededRng.hash_string("abc"), SeededRng.hash_string("abc"))
	assert_ne(SeededRng.hash_string("abc"), SeededRng.hash_string("abd"))


func test_rng_ranges_and_distribution() -> void:
	var r := SeededRng.new(7)
	var buckets := [0, 0, 0, 0]
	for i in 4000:
		var v := r.range_int(0, 3)
		assert_between(v, 0, 3)
		buckets[v] += 1
		var f := r.next_float()
		assert_true(f >= 0.0 and f < 1.0, "float range")
	for b in buckets:
		assert_between(b, 850, 1150, "uniform buckets")


func test_rng_values_are_32_bit() -> void:
	var r := SeededRng.new(-12345)
	for i in 500:
		var v := r.next_u32()
		assert_true(v >= 0 and v <= 0xFFFFFFFF, "32-bit output")


func test_fork_is_independent_and_stable() -> void:
	var base := SeededRng.new(99)
	var f1 := base.fork(1)
	var f2 := base.fork(2)
	var f1b := SeededRng.new(99).fork(1)
	assert_ne(f1.next_u32(), f2.next_u32())
	f1 = SeededRng.new(99).fork(1)
	assert_eq(f1.next_u32(), f1b.next_u32())


func test_level_seeds() -> void:
	for lv in [1, 2, 10, 1000, 100000000, 999999999999]:
		var s := SeedManager.level_seed(lv)
		assert_eq(s, SeedManager.level_seed(lv), "deterministic")
		assert_eq(str(s).length(), 12, "12 digit seed")
	assert_ne(SeedManager.level_seed(1), SeedManager.level_seed(2))


func test_share_code_roundtrip() -> void:
	var req := SeedManager.level_request(18492, 12)
	var code := SeedManager.make_code(req)
	assert_true(code.begins_with("ASCENSION-18492-"), code)
	var back := SeedManager.parse_code(code)
	assert_not_null(back)
	assert_eq(back.level, 18492)
	assert_eq(back.seed, req.seed)
	assert_eq(back.bias, 12)
	var neg := PuzzleRequest.make(PuzzleRequest.Kind.LEVEL, 50, 123456789012, -20)
	var back2 := SeedManager.parse_code(SeedManager.make_code(neg))
	assert_eq(back2.bias, -20)


func test_pure_seed_code() -> void:
	var r := SeedManager.parse_code("ASCENSION-839204918230")
	assert_not_null(r)
	assert_eq(r.seed, 839204918230)
	assert_between(r.level, 1, SeedManager.CUSTOM_LEVEL_SPAN)
	var again := SeedManager.parse_code("ascension-839204918230")
	assert_eq(again.level, r.level, "case insensitive and deterministic")


func test_daily_code() -> void:
	var r := SeedManager.parse_code("DAILY-2026-10-03")
	assert_not_null(r)
	assert_eq(r.kind, PuzzleRequest.Kind.DAILY)
	assert_eq(r.label, "2026-10-03")
	assert_eq(SeedManager.make_code(r), "DAILY-2026-10-03")
	var other := SeedManager.parse_code("DAILY-2026-10-04")
	assert_ne(other.seed, r.seed)
	assert_eq(SeedManager.parse_code("DAILY-2026-02-30"), null, "invalid date")


func test_codes_are_data_only() -> void:
	for bad in ["", "ASCENSION", "ASCENSION-abc-1", "ASCENSION-1-2-3-4", "ASCENSION-0-5",
			"ASCENSION-5-5-X3", "print('hi')", "ASCENSION-1-1;OS.execute", "DAILY-20-1-1",
			"ASCENSION-99999999999999-1", "A".repeat(200), "ASCENSION-5-5-P999"]:
		assert_eq(SeedManager.parse_code(bad), null, "rejects %s" % bad)


func test_daily_difficulty_rises_through_week() -> void:
	var mon := SeedManager.daily_request({"year": 2026, "month": 9, "day": 28, "weekday": 1})
	var sun := SeedManager.daily_request({"year": 2026, "month": 10, "day": 4, "weekday": 0})
	assert_true(sun.level > mon.level)
