class_name GeneratorService
extends Node
## Schedules puzzle generation on the main thread, one candidate attempt at
## a time within a per-frame time budget, so the UI keeps animating while a
## puzzle is built.
##
## No GDScript ever runs on a second thread: Godot 4.7 can crash (SIGSEGV)
## when two threads execute the same not-yet-run GDScript code at once, and
## the generator shares a lot of code with gameplay (validation, RNG, ...).

signal puzzle_ready(key: String, puzzle: Puzzle)

const MEMORY_ENTRIES := 6
## Milliseconds of generation work per frame for puzzles the player waits on.
const URGENT_BUDGET_MS := 12.0
## Background prefetch budget, used only while `allow_background` is true.
const BACKGROUND_BUDGET_MS := 4.0

var level_cache: LevelCache
var last_generation_ms: float = 0.0
## Screens enable this when a small hitch is harmless (results overlay).
var allow_background: bool = false

var _jobs: Array = []          # [{key, request, avoid, urgent, gen}]
var _memory: Dictionary = {}
var _memory_order: PackedStringArray = PackedStringArray()


## Returns the puzzle immediately when cached, otherwise schedules it (first
## in line) and returns null; puzzle_ready fires when it is done.
func request(req: PuzzleRequest, avoid: Array = []) -> Puzzle:
	var key := req.cache_key()
	var cached := _cached(key, req)
	if cached:
		return cached
	_enqueue(key, req, avoid, true)
	return null


## Warms the cache in the background (lowest priority).
func prefetch(req: PuzzleRequest) -> void:
	var key := req.cache_key()
	if _memory.has(key) or _job_index(key) >= 0:
		return
	if level_cache and level_cache.get_puzzle(req) != null:
		return
	_enqueue(key, req, [], false)


## Synchronous generation (menu decoration, debug tools, tests).
func generate_now(req: PuzzleRequest, avoid: Array = []) -> Puzzle:
	var key := req.cache_key()
	var cached := _cached(key, req)
	if cached:
		return cached
	var gen := _make_generator(avoid)
	var p := gen.generate(req)
	_store(key, req, p)
	return p


func is_pending(req: PuzzleRequest) -> bool:
	return _job_index(req.cache_key()) >= 0


func cancel_background() -> void:
	for i in range(_jobs.size() - 1, -1, -1):
		if not bool(_jobs[i]["urgent"]):
			_jobs.remove_at(i)


func _process(_delta: float) -> void:
	if _jobs.is_empty():
		return
	var start := Time.get_ticks_usec()
	var urgent := _next_job(true) >= 0
	var budget := URGENT_BUDGET_MS if urgent else BACKGROUND_BUDGET_MS
	if not urgent and not allow_background:
		return
	# Always run at least one attempt per frame so progress is guaranteed.
	while true:
		var idx := _next_job(urgent)
		if idx < 0:
			break
		var job: Dictionary = _jobs[idx]
		var gen: PuzzleGenerator = job["gen"]
		if gen == null:
			gen = _make_generator(job["avoid"])
			gen.begin(job["request"])
			job["gen"] = gen
		if gen.step():
			_jobs.remove_at(idx)
			var p := gen.result()
			last_generation_ms = float(p.meta.get("gen_ms", 0.0))
			_store(job["key"], job["request"], p)
			puzzle_ready.emit(job["key"], p)
		if (Time.get_ticks_usec() - start) / 1000.0 >= budget:
			break


func _next_job(urgent_only: bool) -> int:
	for i in _jobs.size():
		if bool(_jobs[i]["urgent"]):
			return i
	if urgent_only:
		return -1
	return 0 if not _jobs.is_empty() else -1


func _job_index(key: String) -> int:
	for i in _jobs.size():
		if _jobs[i]["key"] == key:
			return i
	return -1


func _enqueue(key: String, req: PuzzleRequest, avoid: Array, urgent: bool) -> void:
	var idx := _job_index(key)
	if idx >= 0:
		if urgent:
			_jobs[idx]["urgent"] = true
		return
	_jobs.append({"key": key, "request": req.duplicate_request(), "avoid": avoid.duplicate(), "urgent": urgent, "gen": null})


func _make_generator(avoid: Array) -> PuzzleGenerator:
	var gen := PuzzleGenerator.new()
	for fp in avoid:
		gen.avoid_fingerprints[str(fp)] = true
	return gen


func _cached(key: String, req: PuzzleRequest) -> Puzzle:
	if _memory.has(key):
		_touch(key)
		return _memory[key]
	if level_cache:
		var p := level_cache.get_puzzle(req)
		if p:
			_remember(key, p)
			return p
	return null


func _store(key: String, req: PuzzleRequest, p: Puzzle) -> void:
	_remember(key, p)
	if level_cache:
		level_cache.put(req, p)


func _remember(key: String, p: Puzzle) -> void:
	_memory[key] = p
	_touch(key)
	while _memory_order.size() > MEMORY_ENTRIES:
		_memory.erase(_memory_order[0])
		_memory_order.remove_at(0)


func _touch(key: String) -> void:
	var idx := _memory_order.find(key)
	if idx >= 0:
		_memory_order.remove_at(idx)
	_memory_order.append(key)
