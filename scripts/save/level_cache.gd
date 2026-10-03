class_name LevelCache
extends RefCounted
## Small LRU cache of generated puzzles (current / recent / daily / shared).
## Levels are never pre-stored: anything evicted is simply regenerated from
## its request, which is deterministic.

const MAX_ENTRIES := 8

var path: String
var _entries: Dictionary = {}
var _order: PackedStringArray = PackedStringArray()


func _init(file_path: String = "user://cache.json") -> void:
	path = file_path


func load_cache() -> void:
	_entries.clear()
	_order.clear()
	if not FileAccess.file_exists(path):
		return
	var parsed := JsonUtil.parse_dict(FileAccess.get_file_as_string(path))
	if parsed.is_empty():
		return
	var entries: Variant = parsed.get("entries", {})
	var order: Variant = parsed.get("order", [])
	if entries is Dictionary and order is Array:
		_entries = entries
		for k in order:
			if _entries.has(str(k)):
				_order.append(str(k))


func save_cache() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"entries": _entries, "order": Array(_order)}))


func get_puzzle(request: PuzzleRequest) -> Puzzle:
	var key := request.cache_key()
	if not _entries.has(key):
		return null
	var p := Puzzle.from_dict(_entries[key])
	if p == null:
		_entries.erase(key)
		return null
	_touch(key)
	return p


func put(request: PuzzleRequest, puzzle: Puzzle) -> void:
	var key := request.cache_key()
	_entries[key] = puzzle.to_dict()
	_touch(key)
	while _order.size() > MAX_ENTRIES:
		var old := _order[0]
		_order.remove_at(0)
		_entries.erase(old)


func size() -> int:
	return _entries.size()


func clear() -> void:
	_entries.clear()
	_order.clear()


func _touch(key: String) -> void:
	var idx := _order.find(key)
	if idx >= 0:
		_order.remove_at(idx)
	_order.append(key)
