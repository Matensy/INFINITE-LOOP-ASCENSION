extends Node
## Autoload "Save": owns the persistent player data and settings.
## Writes are debounced and flushed when the app is paused or closed.

signal settings_changed(key: String, value: Variant)

const SAVE_DELAY := 2.0
const LOCK_PATH := "user://running.lock"
## After this many unexpected exits in a row, heavy effects are turned off.
const SAFE_MODE_AFTER := 2

var data: Dictionary = {}
var store: SaveStore
var cache: LevelCache
## Disabled by `--ephemeral-save` (automated UI tests) so nothing is written.
var persistent: bool = true
## True when the previous run ended while the app was in the foreground
## (crash, freeze kill, ...). Detected with a lock file that is removed
## whenever the app goes to the background or quits normally.
var crashed_last_time: bool = false
var safe_mode_applied: bool = false

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
		_check_previous_run()
	else:
		data = SaveStore.defaults()
	GameLog.info("SAVE", "loaded (%s)" % (store.last_load_source if persistent else "ephemeral"))


func _check_previous_run() -> void:
	crashed_last_time = FileAccess.file_exists(LOCK_PATH)
	var count := int(data.get("crash_count", 0))
	count = count + 1 if crashed_last_time else 0
	data["crash_count"] = count
	if crashed_last_time:
		GameLog.warn("SAVE", "previous run ended unexpectedly (%d in a row)" % count)
		# Lost progress protection: a crash may have skipped the last flush.
		var settings: Dictionary = data["settings"]
		if count >= SAFE_MODE_AFTER and str(settings.get("effects", "high")) == "high":
			settings["effects"] = "low"
			safe_mode_applied = true
		flush()
	_write_lock()


func _write_lock() -> void:
	if not persistent:
		return
	var f := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
	if f:
		f.store_string(str(Time.get_unix_time_from_system()))


func _remove_lock() -> void:
	if persistent and FileAccess.file_exists(LOCK_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK_PATH))


func _process(delta: float) -> void:
	if _dirty:
		_timer -= delta
		if _timer <= 0.0:
			flush()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			flush()
			_remove_lock()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			flush()
		NOTIFICATION_APPLICATION_RESUMED:
			_write_lock()
		NOTIFICATION_PREDELETE:
			_remove_lock()


## Clean shutdown path used by the app before quitting.
func shutdown() -> void:
	flush()
	_remove_lock()


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
