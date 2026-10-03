class_name ThemeCatalog
extends RefCounted
## Pure data access to data/themes/themes.json plus the deterministic theme
## choice for a puzzle (generator layer 8: presentation).

const PATH := "res://data/themes/themes.json"
const DEFAULT_ID := "cyber"
const SALT := 0x54484D45

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}


static func load_catalog() -> void:
	if not _data.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		GameLog.error("THEME", "failed to parse %s" % PATH)
		parsed = {"themes": [], "event_themes": {}, "rotation_block": 10}
	_data = parsed
	_by_id.clear()
	for t in _data.get("themes", []):
		_by_id[str(t.get("id", ""))] = t


static func all() -> Array:
	load_catalog()
	return _data.get("themes", [])


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for t in all():
		out.append(str(t.get("id", "")))
	return out


static func get_theme(id: String) -> Dictionary:
	load_catalog()
	if _by_id.has(id):
		return _by_id[id]
	return _by_id.get(DEFAULT_ID, {})


static func unlock_level(id: String) -> int:
	return int(get_theme(id).get("unlock", 1))


static func is_unlocked(id: String, highest_level: int) -> bool:
	return unlock_level(id) <= highest_level


## Deterministic theme for a request. Events have fixed themes; otherwise
## themes rotate every `rotation_block` levels among auto-rotation themes
## already unlocked at that level.
static func theme_for(request: PuzzleRequest, event: String) -> String:
	load_catalog()
	var event_themes: Dictionary = _data.get("event_themes", {})
	if event != "" and event_themes.has(event):
		return str(event_themes[event])
	var pool: Array = []
	for t in all():
		if bool(t.get("auto", false)) and int(t.get("unlock", 1)) <= request.level:
			pool.append(str(t.get("id", "")))
	if pool.is_empty():
		return DEFAULT_ID
	var block_size := maxi(1, int(_data.get("rotation_block", 10)))
	var index := (request.level - 1) / block_size
	if not request.uses_progression():
		index = int(SeededRng.mix32(request.seed & 0xFFFFFFFF))
	var rng := SeededRng.new(SeededRng.hash_ints([SALT, index / maxi(1, pool.size())]))
	rng.shuffle(pool)
	return pool[index % pool.size()]


static func color(theme: Dictionary, key: String, fallback: Color = Color.WHITE) -> Color:
	var v: Variant = theme.get(key, null)
	if v is String:
		return Color.from_string(v, fallback)
	return fallback


static func core_colors(theme: Dictionary) -> Array[Color]:
	var out: Array[Color] = []
	for v in theme.get("cores", []):
		out.append(Color.from_string(str(v), Color.WHITE))
	if out.is_empty():
		out.append(Color(1.0, 0.85, 0.3))
	return out
