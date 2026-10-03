class_name SaveStore
extends RefCounted
## Versioned, checksummed JSON save with automatic backup and migration.
##
## File envelope: {"version": V, "checksum": sha256(payload), "payload": "<json>"}
## Writes go to <path>.tmp, the previous good file is kept as <path>.bak, then
## the temp file replaces the main file. On load a corrupted main file falls
## back to the backup, and a corrupted backup falls back to defaults (the bad
## file is kept as <path>.corrupt for inspection).

const VERSION := 2

var path: String
var last_load_source: String = ""


func _init(file_path: String = "user://save.json") -> void:
	path = file_path


func backup_path() -> String:
	return path + ".bak"


static func defaults() -> Dictionary:
	return {
		"version": VERSION,
		"progress": {"current_level": 1, "highest_level": 1, "level_bias": 0},
		"session": {},
		"stats": Statistics.defaults(),
		"settings": SaveStore.default_settings(),
		"unlocked_themes": ["cyber", "void", "monochrome"],
		"achievements": {},
		"daily": {},
		"adaptive": AdaptiveDifficulty.defaults(),
		"telemetry": [],
		"recent_fingerprints": [],
		"favorites": [],
		"seen_mechanics": [],
	}


static func default_settings() -> Dictionary:
	return {
		"language": "auto",
		"sound": true,
		"music": true,
		"sfx_volume": 0.8,
		"music_volume": 0.45,
		"haptics": true,
		"haptic_strength": 1.0,
		"animation_speed": 1.0,
		"reduce_motion": false,
		"effects": "high",
		"high_contrast": false,
		"colorblind": false,
		"left_handed": false,
		"ui_scale": 1.0,
		"theme": "auto",
		"double_tap": "pin",
		"two_finger_tap": "undo",
		"show_timer": false,
	}


func load_data() -> Dictionary:
	var main := _read(path)
	if not main.is_empty():
		last_load_source = "main"
		return _complete(main)
	if FileAccess.file_exists(path):
		_quarantine(path)
	var backup := _read(backup_path())
	if not backup.is_empty():
		last_load_source = "backup"
		GameLog.warn("SAVE", "main save unreadable, restored backup")
		return _complete(backup)
	last_load_source = "defaults"
	return defaults()


func save_data(data: Dictionary) -> bool:
	var payload := JSON.stringify(data)
	var envelope := {"version": VERSION, "checksum": payload.sha256_text(), "payload": payload}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		GameLog.error("SAVE", "cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(envelope))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	# Keep the last good save as backup before replacing it.
	if FileAccess.file_exists(path) and not _read(path).is_empty():
		dir.copy(path, backup_path())
	if dir.rename(tmp, path) != OK:
		dir.copy(tmp, path)
		dir.remove(tmp)
	return true


func delete_all() -> void:
	for p in [path, backup_path(), path + ".tmp", path + ".corrupt"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## Returns {} when the file is missing, unparsable or fails its checksum.
func _read(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var env := JsonUtil.parse_dict(FileAccess.get_file_as_string(file_path))
	if env.is_empty():
		return {}
	var payload: Variant = env.get("payload", null)
	if not payload is String:
		return {}
	if str(env.get("checksum", "")) != (payload as String).sha256_text():
		GameLog.warn("SAVE", "checksum mismatch in %s" % file_path)
		return {}
	var data := JsonUtil.parse_dict(payload)
	if data.is_empty():
		return {}
	return migrate(data, int(env.get("version", 1)))


func _quarantine(file_path: String) -> void:
	var dir := DirAccess.open(file_path.get_base_dir())
	if dir:
		dir.copy(file_path, file_path + ".corrupt")


## Upgrades older payloads step by step.
static func migrate(data: Dictionary, from_version: int) -> Dictionary:
	var d := data.duplicate(true)
	var v := from_version
	if v < 2:
		# v1 stored the level directly at the top level.
		var progress: Dictionary = d.get("progress", {})
		if d.has("current_level"):
			progress["current_level"] = int(d["current_level"])
			d.erase("current_level")
		if d.has("highest_level"):
			progress["highest_level"] = int(d["highest_level"])
			d.erase("highest_level")
		d["progress"] = progress
		v = 2
	d["version"] = VERSION
	return d


## Fills keys missing from older or partial saves with defaults.
static func _complete(data: Dictionary) -> Dictionary:
	var base := defaults()
	for key in base.keys():
		if not data.has(key) or typeof(data[key]) != typeof(base[key]):
			data[key] = base[key]
		elif base[key] is Dictionary:
			var sub: Dictionary = data[key]
			for k in (base[key] as Dictionary).keys():
				if not sub.has(k):
					sub[k] = base[key][k]
	var progress: Dictionary = data["progress"]
	progress["current_level"] = maxi(1, int(progress.get("current_level", 1)))
	progress["highest_level"] = maxi(int(progress["current_level"]), int(progress.get("highest_level", 1)))
	return data
