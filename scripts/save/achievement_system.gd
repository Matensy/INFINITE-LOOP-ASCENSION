class_name AchievementSystem
extends RefCounted
## Evaluates data-driven achievements (data/achievements/achievements.json).

const PATH := "res://data/achievements/achievements.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"achievements": [], "titles": []}
	return _data


static func definitions() -> Array:
	return data().get("achievements", [])


static func titles() -> Array:
	return data().get("titles", [])


## Checks every locked achievement against the save and the last solve.
## `solve` keys: difficulty, tier, hints, perfect, time, mode, mechanics
## (Array of "portal"/"link"/"hex"), gestures (Dictionary).
## Returns ids unlocked by this call and records them in save["achievements"].
static func evaluate(save: Dictionary, solve: Dictionary) -> PackedStringArray:
	var unlocked: Dictionary = save.get("achievements", {})
	var stats: Dictionary = save.get("stats", {})
	var progress: Dictionary = save.get("progress", {})
	var fresh := PackedStringArray()
	var now := int(Time.get_unix_time_from_system())
	for def in definitions():
		var id := str(def.get("id", ""))
		if id == "" or unlocked.has(id):
			continue
		if _met(def, stats, progress, solve):
			unlocked[id] = now
			fresh.append(id)
	save["achievements"] = unlocked
	return fresh


static func _met(def: Dictionary, stats: Dictionary, progress: Dictionary, solve: Dictionary) -> bool:
	var value: Variant = def.get("value", 0)
	var min_diff := float(def.get("min_difficulty", 0.0))
	var diff := float(solve.get("difficulty", 0.0))
	match str(def.get("type", "")):
		"solved":
			return int(stats.get("total_solved", 0)) >= int(value)
		"level":
			return int(progress.get("highest_level", 1)) >= int(value)
		"tier":
			if solve.is_empty():
				return false
			return DifficultyCurve.tier_index(diff) >= _tier_index(str(value))
		"no_hint":
			return not solve.is_empty() and int(solve.get("hints", 1)) == 0 and diff >= min_diff
		"perfect":
			return bool(solve.get("perfect", false)) and diff >= min_diff
		"speed":
			if bool(def.get("no_hints", false)) and int(solve.get("hints", 0)) > 0:
				return false
			return not solve.is_empty() and float(solve.get("time", 1e9)) <= float(value) and diff >= min_diff
		"one_handed":
			var g: Dictionary = solve.get("gestures", {})
			return not solve.is_empty() and diff >= min_diff and not g.has("pinch") and not g.has("two_finger")
		"daily":
			return int(stats.get("daily_solved", 0)) >= int(value)
		"streak":
			return int(stats.get("longest_streak", 0)) >= int(value)
		"mode":
			return int((stats.get("modes", {}) as Dictionary).get(str(value), 0)) > 0
		"boss":
			return int(stats.get("boss_solved", 0)) >= int(value)
		"mechanic":
			return (solve.get("mechanics", []) as Array).has(str(value))
	return false


static func _tier_index(id: String) -> int:
	var list := DifficultyCurve.tiers()
	for i in list.size():
		if str(list[i].get("id", "")) == id:
			return i
	return 99


## Mechanics present in a puzzle, as achievement keys.
static func mechanics_of(puzzle: Puzzle) -> Array:
	var out: Array = []
	if puzzle.portal_count() > 0:
		out.append("portal")
	if not puzzle.link_groups.is_empty():
		out.append("link")
	if puzzle.topology.kind == Topology.Kind.HEX:
		out.append("hex")
	return out
