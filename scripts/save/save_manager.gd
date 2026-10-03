extends Node
## Autoload "Save": owns the persistent player data and settings.
## Writes are debounced and flushed when the app is paused or closed.

signal settings_changed(key: String, value: Variant)

const SAVE_DELAY := 0.75

var data: Dictionary = {}
var store: SaveStore
var cache: LevelCache
## Disabled by `--ephemeral-save` (automated UI tests) so nothing is written.
var persistent: bool = true

var _dirty := false
var _timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	persistent = not OS.get_cmdline_user_args().has("--ephemeral-save")
	store = SaveStore.new("user://save.json")
	cache = LevelCache.new("user://cache.json")
	if persistent:
		data = store.load_data()
		cache.load_cache()
	else:
		data = SaveStore.defaults()
	GameLog.info("SAVE", "loaded (%s)" % (store.last_load_source if persistent else "ephemeral"))


func _process(delta: float) -> void:
	if _dirty:
		_timer -= delta
		if _timer <= 0.0:
			flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		flush()


func mark_dirty() -> void:
	_dirty = true
	_timer = SAVE_DELAY


func flush() -> void:
	_dirty = false
	if not persistent:
		return
	store.save_data(data)
	cache.save_cache()


func settings() -> Dictionary:
	return data["settings"]


func setting(key: String, default: Variant = null) -> Variant:
	return (data["settings"] as Dictionary).get(key, default)


func set_setting(key: String, value: Variant) -> void:
	(data["settings"] as Dictionary)[key] = value
	mark_dirty()
	settings_changed.emit(key, value)


func progress() -> Dictionary:
	return data["progress"]


func stats() -> Dictionary:
	return data["stats"]


func current_level() -> int:
	return int(progress().get("current_level", 1))


func highest_level() -> int:
	return int(progress().get("highest_level", 1))


func reset_progress() -> void:
	var keep: Dictionary = (data["settings"] as Dictionary).duplicate()
	data = SaveStore.defaults()
	data["settings"] = keep
	cache.clear()
	mark_dirty()
	flush()
