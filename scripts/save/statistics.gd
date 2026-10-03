class_name Statistics
extends RefCounted
## Player statistics (pure functions over the stats dictionary).


static func defaults() -> Dictionary:
	return {
		"total_solved": 0,
		"total_moves": 0,
		"total_time": 0.0,
		"perfect_solves": 0,
		"no_hint_solves": 0,
		"hints_used": 0,
		"hardest_solve": 0.0,
		"hardest_code": "",
		"fastest_solve": -1.0,
		"fewest_moves": -1,
		"current_streak": 0,
		"longest_streak": 0,
		"last_play_day": "",
		"daily_solved": 0,
		"daily_streak": 0,
		"last_daily": "",
		"boss_solved": 0,
		"modes": {},
		"tiers": {},
		"abandons": 0,
	}


## Records a solve. `info` keys: difficulty, moves, time, hints, perfect,
## mode, tier, kind, boss, code, day ("YYYY-MM-DD"), min_moves.
static func record_solve(stats: Dictionary, info: Dictionary) -> void:
	var difficulty := float(info.get("difficulty", 0.0))
	var moves := int(info.get("moves", 0))
	var time := float(info.get("time", 0.0))
	var hints := int(info.get("hints", 0))
	stats["total_solved"] = int(stats.get("total_solved", 0)) + 1
	stats["total_moves"] = int(stats.get("total_moves", 0)) + moves
	stats["total_time"] = float(stats.get("total_time", 0.0)) + time
	stats["hints_used"] = int(stats.get("hints_used", 0)) + hints
	if hints == 0:
		stats["no_hint_solves"] = int(stats.get("no_hint_solves", 0)) + 1
	if bool(info.get("perfect", false)):
		stats["perfect_solves"] = int(stats.get("perfect_solves", 0)) + 1
	if difficulty > float(stats.get("hardest_solve", 0.0)):
		stats["hardest_solve"] = difficulty
		stats["hardest_code"] = str(info.get("code", ""))
	# Fastest / fewest only count real puzzles (not tutorials).
	if difficulty >= 10.0 and hints == 0:
		var fastest := float(stats.get("fastest_solve", -1.0))
		if fastest < 0.0 or time < fastest:
			stats["fastest_solve"] = time
		var fewest := int(stats.get("fewest_moves", -1))
		if fewest < 0 or moves < fewest:
			stats["fewest_moves"] = moves
	if bool(info.get("boss", false)):
		stats["boss_solved"] = int(stats.get("boss_solved", 0)) + 1
	_bump(stats, "modes", str(info.get("mode", "loop")))
	_bump(stats, "tiers", str(info.get("tier", "tutorial")))
	var day := str(info.get("day", ""))
	if day != "":
		_update_streak(stats, day)
	if str(info.get("kind", "")) == "daily":
		stats["daily_solved"] = int(stats.get("daily_solved", 0)) + 1
		var last := str(stats.get("last_daily", ""))
		if last != day:
			stats["daily_streak"] = int(stats.get("daily_streak", 0)) + 1 if _is_next_day(last, day) else 1
			stats["last_daily"] = day


static func average_moves(stats: Dictionary) -> float:
	var solved := int(stats.get("total_solved", 0))
	return float(stats.get("total_moves", 0)) / solved if solved > 0 else 0.0


static func _bump(stats: Dictionary, key: String, sub: String) -> void:
	var d: Dictionary = stats.get(key, {})
	d[sub] = int(d.get(sub, 0)) + 1
	stats[key] = d


## Streak = consecutive calendar days with at least one solve.
static func _update_streak(stats: Dictionary, day: String) -> void:
	var last := str(stats.get("last_play_day", ""))
	if last == day:
		return
	if _is_next_day(last, day):
		stats["current_streak"] = int(stats.get("current_streak", 0)) + 1
	else:
		stats["current_streak"] = 1
	stats["longest_streak"] = maxi(int(stats.get("longest_streak", 0)), int(stats["current_streak"]))
	stats["last_play_day"] = day


static func _is_next_day(prev: String, day: String) -> bool:
	if prev == "" or day == "":
		return false
	var a := Time.get_unix_time_from_datetime_string(prev + "T12:00:00")
	var b := Time.get_unix_time_from_datetime_string(day + "T12:00:00")
	return absi(int(b - a) - 86400) < 3600


static func today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## Title earned at a given highest level (data driven, see achievements.json).
static func title_for(highest_level: int, titles: Array) -> String:
	var key := "TITLE_NOVICE"
	for t in titles:
		if highest_level >= int(t.get("level", 1)):
			key = str(t.get("key", key))
	return key
