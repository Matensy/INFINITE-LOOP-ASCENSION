class_name DifficultyConfig
extends RefCounted
## Loads data/difficulties/difficulty.json once. Call load_config()
## on the main thread at start-up; afterwards reads are thread safe.

const PATH := "res://data/difficulties/difficulty.json"

static var _data: Dictionary = {}


static func load_config() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_data = parsed
		else:
			GameLog.error("CONFIG", "failed to parse %s" % PATH)
			_data = {"curve": {}, "tiers": [], "score": {}, "unlocks": {}, "planner": {}, "events": []}
	return _data


static func section(name: String) -> Dictionary:
	var d: Variant = load_config().get(name, {})
	return d if d is Dictionary else {}


static func value(section_name: String, key: String, default: Variant) -> Variant:
	return section(section_name).get(key, default)


static func num(section_name: String, key: String, default: float) -> float:
	return float(section(section_name).get(key, default))


static func range_of(section_name: String, key: String, default: Vector2) -> Vector2:
	var v: Variant = section(section_name).get(key, null)
	if v is Array and (v as Array).size() == 2:
		return Vector2(float(v[0]), float(v[1]))
	return default


static func list(name: String) -> Array:
	var v: Variant = load_config().get(name, [])
	return v if v is Array else []
