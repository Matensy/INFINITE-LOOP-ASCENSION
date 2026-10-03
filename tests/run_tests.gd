extends SceneTree
## Headless test runner.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- --filter=solver
##
## Discovers tests/<suite>/test_*.gd, runs every `test_*` method and exits
## with code 1 on any failure. Engine/script errors raised while a test runs
## are captured through a Logger and count as failures.

const SUITES: Array[String] = ["core", "generator", "solver", "gameplay", "performance"]


class ErrorCounter:
	extends Logger
	var errors: PackedStringArray = PackedStringArray()
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var out := errors.duplicate()
		errors.clear()
		_mutex.unlock()
		return out


func _init() -> void:
	GameLog.enabled = false
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
	DifficultyConfig.load_config()
	ThemeCatalog.load_catalog()
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var total := 0
	var failed := 0
	var assertions := 0
	var t0 := Time.get_ticks_msec()
	for suite in SUITES:
		for path in _find_tests("res://tests/" + suite):
			if filter != "" and path.find(filter) < 0:
				continue
			var script: GDScript = load(path)
			if script == null:
				print("LOAD FAIL  %s" % path)
				failed += 1
				continue
			for method in script.get_script_method_list():
				var name: String = method["name"]
				if not name.begins_with("test_"):
					continue
				var test: TestCase = script.new()
				counter.take()
				var started := Time.get_ticks_msec()
				test.before_each()
				test.call(name)
				test.after_each()
				var errs := counter.take()
				for e in errs:
					test.failures.append("engine error: " + e)
				total += 1
				assertions += test.assertions
				var ms := Time.get_ticks_msec() - started
				if test.failures.is_empty():
					print("PASS  %s::%s (%d ms)" % [path.get_file(), name, ms])
				else:
					failed += 1
					print("FAIL  %s::%s" % [path.get_file(), name])
					for f in test.failures:
						print("        - " + f)
	OS.remove_logger(counter)
	print("")
	print("%d tests, %d failed, %d assertions, %.1fs" % [total, failed, assertions, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failed > 0 or total == 0 else 0)


func _find_tests(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
	out.sort()
	return out
