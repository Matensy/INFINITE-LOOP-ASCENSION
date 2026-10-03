extends Node
## Autoload "Game": level flow and progression glue between generator,
## sessions and persistence. Screens call into this; it holds no UI.

signal puzzle_ready(key: String, puzzle: Puzzle)

## Challenge tiers (target difficulty). Puzzles are rebuilt from level+seed,
## so challenge codes are shareable like any other.
const CHALLENGES := [
	{"id": "hardcore", "target": 120.0},
	{"id": "insane", "target": 200.0},
	{"id": "nightmare", "target": 320.0},
	{"id": "ascension", "target": 520.0},
]
const RECENT_FINGERPRINTS := 40

var generator: GeneratorService
## Request the next screen should open (set by menus).
var pending_request: PuzzleRequest
var pending_options: Dictionary = {}


func _ready() -> void:
	DifficultyConfig.load_config()
	ThemeCatalog.load_catalog()
	AchievementSystem.data()
	generator = GeneratorService.new()
	generator.name = "GeneratorService"
	add_child(generator)
	var save := _save()
	if save:
		generator.level_cache = save.cache
	generator.puzzle_ready.connect(func(key: String, p: Puzzle): puzzle_ready.emit(key, p))


func _save() -> Node:
	return get_node_or_null("/root/Save")


# --- Requests -----------------------------------------------------------------

## The player's current endless level, with the difficulty bias that was
## locked when this level was first reached.
func continue_request() -> PuzzleRequest:
	var save := _save()
	var level: int = save.current_level() if save else 1
	var bias: int = int(save.progress().get("level_bias", 0)) if save else 0
	return SeedManager.level_request(level, bias)


func daily_request() -> PuzzleRequest:
	return SeedManager.daily_request(Time.get_date_dict_from_system())


## Relaxed endless puzzle near the player's level (never repeats recent ones).
func zen_request() -> PuzzleRequest:
	var save := _save()
	var level: int = maxi(1, save.highest_level() if save else 1)
	var entropy := int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec()
	var req := PuzzleRequest.make(PuzzleRequest.Kind.ZEN, level, SeedManager.random_seed(entropy))
	return req


func challenge_request(index: int) -> PuzzleRequest:
	var ch: Dictionary = CHALLENGES[clampi(index, 0, CHALLENGES.size() - 1)]
	var level := DifficultyCurve.level_for_target(float(ch["target"]))
	var entropy := int(Time.get_unix_time_from_system() * 1000.0) ^ (Time.get_ticks_usec() << 3)
	var req := PuzzleRequest.make(PuzzleRequest.Kind.CHALLENGE, level, SeedManager.random_seed(entropy))
	req.label = str(ch["id"])
	return req


func avoid_list(req: PuzzleRequest) -> Array:
	var save := _save()
	if save == null or req.kind != PuzzleRequest.Kind.ZEN:
		return []
	return save.data.get("recent_fingerprints", [])


func next_level_request() -> PuzzleRequest:
	return continue_request()


func prefetch_next() -> void:
	generator.prefetch(continue_request())


# --- Session persistence ------------------------------------------------------
# One in-progress slot per puzzle kind, so a zen detour never overwrites the
# endless level the player was halfway through.

func store_session(session: GameSession) -> void:
	var save := _save()
	if save == null or session == null or session.solved or session.request == null:
		return
	_slots()[session.request.kind_id()] = session.to_save()
	save.mark_dirty()


func saved_session_for(req: PuzzleRequest) -> Dictionary:
	if _save() == null:
		return {}
	var s: Dictionary = _slots().get(req.kind_id(), {})
	if s.is_empty():
		return {}
	var saved_req := PuzzleRequest.from_dict(s.get("request", {}))
	if saved_req.cache_key() != req.cache_key():
		return {}
	return s


func clear_session(req: PuzzleRequest = null) -> void:
	var save := _save()
	if save == null:
		return
	if req == null:
		save.data["session"] = {}
	else:
		_slots().erase(req.kind_id())
	save.mark_dirty()


func _slots() -> Dictionary:
	var save := _save()
	var slots: Variant = save.data.get("session", {})
	if not slots is Dictionary or (slots as Dictionary).has("request"):
		slots = {}
		save.data["session"] = slots
	return slots


# --- Completion ---------------------------------------------------------------

## Records a solved session: statistics, achievements, adaptive difficulty,
## progression, daily results, telemetry. Returns a summary for the results
## screen: {achievements, new_level, boss, perfect, daily}.
func complete(session: GameSession) -> Dictionary:
	var save := _save()
	var p := session.puzzle
	var req := session.request
	var day := Statistics.today()
	var info := {
		"difficulty": session.difficulty(),
		"moves": session.moves,
		"time": session.elapsed,
		"hints": session.hints_used,
		"perfect": session.is_perfect(),
		"mode": GameMode.id_of(p.mode),
		"tier": str(p.meta.get("tier", "tutorial")),
		"kind": req.kind_id() if req else "custom",
		"boss": bool(p.meta.get("boss", false)),
		"code": session.code(),
		"day": day,
		"min_moves": int(p.meta.get("min_moves", 0)),
		"mechanics": AchievementSystem.mechanics_of(p),
		"gestures": session.gestures,
	}
	var result := {"achievements": PackedStringArray(), "new_level": -1, "boss": info["boss"], "perfect": info["perfect"]}
	if save == null:
		return result
	var data: Dictionary = save.data
	Statistics.record_solve(data["stats"], info)
	if req and req.kind == PuzzleRequest.Kind.LEVEL:
		var progress: Dictionary = data["progress"]
		if req.level == int(progress.get("current_level", 1)):
			var bias := AdaptiveDifficulty.update(data["adaptive"], info)
			progress["current_level"] = req.level + 1
			progress["highest_level"] = maxi(int(progress.get("highest_level", 1)), req.level + 1)
			progress["level_bias"] = bias
			result["new_level"] = req.level + 1
			_unlock_themes(data, int(progress["highest_level"]))
	if req and req.kind == PuzzleRequest.Kind.DAILY:
		var daily: Dictionary = data["daily"]
		var prev: Dictionary = daily.get(req.label, {})
		if prev.is_empty() or float(prev.get("time", 1e9)) > session.elapsed:
			daily[req.label] = {"time": session.elapsed, "moves": session.moves, "hints": session.hints_used, "mistakes": session.mistakes}
		result["daily"] = daily[req.label]
	if req and req.kind == PuzzleRequest.Kind.ZEN:
		var recent: Array = data.get("recent_fingerprints", [])
		recent.append(str(p.meta.get("fingerprint", "")))
		while recent.size() > RECENT_FINGERPRINTS:
			recent.pop_front()
		data["recent_fingerprints"] = recent
	var seen: Array = data.get("seen_mechanics", [])
	for m in info["mechanics"]:
		if not seen.has(m):
			seen.append(m)
	data["seen_mechanics"] = seen
	result["achievements"] = AchievementSystem.evaluate(data, info)
	Telemetry.record(data, {
		"event": "solve", "kind": info["kind"], "level": req.level if req else 0,
		"difficulty": info["difficulty"], "solve_time": session.elapsed, "moves": session.moves,
		"hints": session.hints_used, "generation_ms": float(p.meta.get("gen_ms", 0.0)),
	})
	clear_session(req)
	save.mark_dirty()
	return result


## Records leaving a puzzle unsolved (telemetry + adaptive signal).
func abandon(session: GameSession) -> void:
	var save := _save()
	if save == null or session == null or session.solved or session.moves == 0:
		return
	var data: Dictionary = save.data
	var stats: Dictionary = data["stats"]
	stats["abandons"] = int(stats.get("abandons", 0)) + 1
	Telemetry.record(data, {"event": "abandon", "level": session.request.level if session.request else 0,
		"difficulty": session.difficulty(), "moves": session.moves, "solve_time": session.elapsed})
	save.mark_dirty()


func _unlock_themes(data: Dictionary, highest: int) -> void:
	var unlocked: Array = data.get("unlocked_themes", [])
	for t in ThemeCatalog.all():
		var id := str(t.get("id", ""))
		if int(t.get("unlock", 1)) <= highest and not unlocked.has(id):
			unlocked.append(id)
	data["unlocked_themes"] = unlocked


func is_daily_done(label: String) -> bool:
	var save := _save()
	return save != null and (save.data.get("daily", {}) as Dictionary).has(label)


func title_key() -> String:
	var save := _save()
	return Statistics.title_for(save.highest_level() if save else 1, AchievementSystem.titles())


## Prestige: one "ascension" star per 1000 levels reached.
func prestige_stars() -> int:
	var save := _save()
	var every := int(AchievementSystem.data().get("prestige_every", 1000))
	return (save.highest_level() if save else 1) / maxi(1, every)
