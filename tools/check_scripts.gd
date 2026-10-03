extends SceneTree
## Loads (compiles) every GDScript in the project and reports failures.
##   godot --headless --path . --script res://tools/check_scripts.gd

func _initialize() -> void:
	# Deferred so autoload singletons are registered before compiling.
	_check.call_deferred()


func _check() -> void:
	var failed := 0
	var total := 0
	for path in _scan("res://"):
		total += 1
		var s: Variant = load(path)
		if s == null or (s is GDScript and not (s as GDScript).can_instantiate()):
			failed += 1
			print("FAILED: ", path)
	print("%d scripts checked, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)


func _scan(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for d in dir.get_directories():
		if d.begins_with(".") or d == "addons":
			continue
		out.append_array(_scan(dir_path.path_join(d)))
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	return out
