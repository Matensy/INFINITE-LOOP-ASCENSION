class_name Diagnostics
extends RefCounted
## Device information and engine logs for bug reports. File logging is on
## for every platform (project.godot), so after an unexpected exit the log
## of the previous run is still on disk and can be copied from the app.

const LOG_DIR := "user://logs"
const CURRENT_LOG := "godot.log"


static func device_report() -> String:
	var lines: PackedStringArray = []
	lines.append("Infinite Loop: Ascension %s" % str(ProjectSettings.get_setting("application/config/version", "?")))
	var info := Engine.get_version_info()
	lines.append("Godot %s" % str(info.get("string", "?")))
	lines.append("OS: %s %s" % [OS.get_name(), OS.get_version()])
	lines.append("Model: %s" % OS.get_model_name())
	lines.append("Locale: %s" % OS.get_locale())
	lines.append("CPU cores: %d" % OS.get_processor_count())
	lines.append("Renderer: %s / %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	lines.append("Vendor: %s" % RenderingServer.get_video_adapter_vendor())
	lines.append("Screen: %s  scale %.2f" % [str(DisplayServer.screen_get_size()), DisplayServer.screen_get_scale()])
	lines.append("Window: %s" % str(DisplayServer.window_get_size()))
	lines.append("Static memory: %.1f MB" % (OS.get_static_memory_usage() / 1048576.0))
	lines.append("Debug build: %s" % str(OS.is_debug_build()))
	return "\n".join(lines)


## Log of the previous run (the newest rotated log file), or "".
static func previous_log(max_lines: int = 200) -> String:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return ""
	var newest := ""
	var newest_time := -1
	for f in dir.get_files():
		if not f.ends_with(".log") or f == CURRENT_LOG:
			continue
		var t := FileAccess.get_modified_time(LOG_DIR.path_join(f))
		if t > newest_time:
			newest_time = t
			newest = f
	if newest == "":
		return ""
	return _tail(LOG_DIR.path_join(newest), max_lines)


static func current_log(max_lines: int = 200) -> String:
	return _tail(LOG_DIR.path_join(CURRENT_LOG), max_lines)


static func _tail(path: String, max_lines: int) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var start := maxi(0, lines.size() - max_lines)
	return "\n".join(lines.slice(start))


## Full text to paste into a bug report.
static func report(include_previous: bool) -> String:
	var parts: PackedStringArray = ["== DEVICE ==", device_report()]
	if include_previous:
		var prev := previous_log()
		parts.append("== PREVIOUS RUN LOG ==")
		parts.append(prev if prev != "" else "(no previous log)")
	parts.append("== CURRENT LOG ==")
	parts.append(current_log(120))
	return "\n".join(parts)
