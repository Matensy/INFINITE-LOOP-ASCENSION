class_name GeneratorService
extends Node
## Runs puzzle generation on a background thread with an in-memory LRU and
## the persistent LevelCache. The next level is prefetched while the player
## solves the current one, so "Next" is usually instant.

signal puzzle_ready(key: String, puzzle: Puzzle)

const MEMORY_ENTRIES := 6

var level_cache: LevelCache
var last_generation_ms: float = 0.0

var _thread: Thread
var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _quit := false
var _jobs: Array = []          # [{key, request, avoid}]
var _done: Array = []          # [{key, puzzle, ms}]
var _in_flight: Dictionary = {}
var _memory: Dictionary = {}
var _memory_order: PackedStringArray = PackedStringArray()
var _threaded := true


func _ready() -> void:
	_threaded = OS.get_processor_count() > 1 and not OS.has_feature("web")
	if _threaded:
		_thread = Thread.new()
		_thread.start(_worker)


func _exit_tree() -> void:
	if _thread:
		_mutex.lock()
		_quit = true
		_mutex.unlock()
		_semaphore.post()
		_thread.wait_to_finish()


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
	if _memory.has(key) or _in_flight.has(key):
		return
	if level_cache and level_cache.get_puzzle(req) != null:
		return
	_enqueue(key, req, [], false)


## Synchronous generation (debug tools, tests, single-threaded platforms).
func generate_now(req: PuzzleRequest, avoid: Array = []) -> Puzzle:
	var key := req.cache_key()
	var cached := _cached(key, req)
	if cached:
		return cached
	var p := _generate(req, avoid)
	_remember(key, p)
	if level_cache:
		level_cache.put(req, p)
	return p


func is_pending(req: PuzzleRequest) -> bool:
	return _in_flight.has(req.cache_key())


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


func _enqueue(key: String, req: PuzzleRequest, avoid: Array, urgent: bool) -> void:
	if not _threaded:
		var p := _generate(req, avoid)
		_remember(key, p)
		puzzle_ready.emit.call_deferred(key, p)
		return
	_mutex.lock()
	if _in_flight.has(key):
		# Promote an already queued job.
		if urgent:
			for i in _jobs.size():
				if _jobs[i]["key"] == key:
					var job: Dictionary = _jobs[i]
					_jobs.remove_at(i)
					_jobs.push_front(job)
					break
		_mutex.unlock()
		return
	_in_flight[key] = true
	var job := {"key": key, "request": req.duplicate_request(), "avoid": avoid.duplicate()}
	if urgent:
		_jobs.push_front(job)
	else:
		_jobs.push_back(job)
	_mutex.unlock()
	_semaphore.post()


func _worker() -> void:
	while true:
		_semaphore.wait()
		_mutex.lock()
		if _quit:
			_mutex.unlock()
			return
		if _jobs.is_empty():
			_mutex.unlock()
			continue
		var job: Dictionary = _jobs.pop_front()
		_mutex.unlock()
		var t0 := Time.get_ticks_usec()
		var p := _generate(job["request"], job["avoid"])
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		_mutex.lock()
		_done.append({"key": job["key"], "request": job["request"], "puzzle": p, "ms": ms})
		_mutex.unlock()
		call_deferred("_deliver")


func _generate(req: PuzzleRequest, avoid: Array) -> Puzzle:
	var gen := PuzzleGenerator.new()
	for fp in avoid:
		gen.avoid_fingerprints[str(fp)] = true
	return gen.generate(req)


func _deliver() -> void:
	_mutex.lock()
	var done := _done.duplicate()
	_done.clear()
	for d in done:
		_in_flight.erase(d["key"])
	_mutex.unlock()
	for d in done:
		last_generation_ms = d["ms"]
		_remember(d["key"], d["puzzle"])
		if level_cache:
			level_cache.put(d["request"], d["puzzle"])
		puzzle_ready.emit(d["key"], d["puzzle"])


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
