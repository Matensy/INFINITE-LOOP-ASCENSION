extends Control
## DEBUG GENERATOR (spec §82-84): inspect any seed/level, override the
## difficulty vector, solve / scramble / verify / step through the solution,
## export JSON and run batch generation reports. Batch runs use a worker
## thread so the UI stays responsive.

var main: Node
var _seed: LineEdit
var _level: SpinBox
var _target: SpinBox
var _mode: OptionButton
var _topology: OptionButton
var _shape: OptionButton
var _board: BoardView
var _log: TextEdit
var _info: Label
var _puzzle: Puzzle
var _state: BoardState
var _request: PuzzleRequest
var _batch_task := -1
var _batch_mutex := Mutex.new()
var _batch_progress := 0
var _batch_total := 0
var _batch_report: Dictionary = {}
var _batch_cancel := false
var _progress: ProgressBar
var _stepping := false


func _ready() -> void:
	UiKit.full_rect(self)
	var p := Themes.palette
	var safe := UiKit.safe_margins(get_viewport())
	var root := UiKit.margin(null, 16 + int(safe.position.x), 16 + int(safe.position.y), 16 + int(safe.size.x), 12 + int(safe.size.y))
	UiKit.full_rect(root)
	add_child(root)
	var col := UiKit.vbox(8)
	root.add_child(col)
	var header := UiKit.hbox(8)
	header.add_child(UiKit.icon_button("←", func(): main.back(), 70))
	var t := UiKit.title("DEBUG GENERATOR", 30, p.ui_accent)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(t)
	col.add_child(header)

	var form := GridContainer.new()
	form.columns = 4
	form.add_theme_constant_override("h_separation", 8)
	form.add_theme_constant_override("v_separation", 6)
	col.add_child(form)
	_seed = _edit(form, "Seed", str(SeedManager.level_seed(1)))
	_level = _spin(form, "Level", 1, 1000000000000, 1)
	_target = _spin(form, "Target", 0, 5000, 0)
	_mode = _options(form, "Mode", ["auto"] + Array(GameMode.IDS))
	_topology = _options(form, "Topology", ["auto", "square", "hex"])
	_shape = _options(form, "Shape", ["auto"] + Array(BoardShapes.NAMES))
	_level.value_changed.connect(func(v: float): _seed.text = str(SeedManager.level_seed(int(v))))

	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	col.add_child(buttons)
	for spec in [
		["Generate", _on_generate], ["Solve", _on_solve], ["Step", _on_step], ["Scramble", _on_scramble],
		["Verify", _on_verify], ["Export", _on_export], ["Play", _on_play],
		["Gen 1,000", _on_batch.bind(1000)], ["Gen 10,000", _on_batch.bind(10000)], ["Telemetry", _on_telemetry],
	]:
		var b := UiKit.button(spec[0], spec[1], 60)
		b.add_theme_font_size_override("font_size", 20)
		b.clip_text = false
		b.custom_minimum_size = Vector2(128, 60)
		buttons.add_child(b)

	_info = UiKit.label("", 20, p.ui_dim, null, HORIZONTAL_ALIGNMENT_LEFT)
	col.add_child(_info)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 18)
	_progress.visible = false
	col.add_child(_progress)
	_board = BoardView.new()
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(0, 360)
	_board.cell_tapped.connect(_on_tap)
	col.add_child(_board)
	_log = TextEdit.new()
	_log.editable = false
	_log.custom_minimum_size = Vector2(0, 220)
	_log.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	col.add_child(_log)
	GameLog.sink = _append_log
	_on_generate()


func _exit_tree() -> void:
	GameLog.sink = Callable()
	if _batch_task >= 0:
		_batch_cancel = true
		WorkerThreadPool.wait_for_task_completion(_batch_task)


func _form_label(parent: Control, text: String) -> void:
	var l := UiKit.label(text, 18, Themes.palette.ui_dim, null, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size = Vector2(96, 0)
	parent.add_child(l)


func _edit(parent: Control, label: String, value: String) -> LineEdit:
	_form_label(parent, label)
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size = Vector2(0, 52)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 20)
	parent.add_child(e)
	return e


func _spin(parent: Control, label: String, lo: float, hi: float, value: float) -> SpinBox:
	_form_label(parent, label)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.step = 1
	s.custom_minimum_size = Vector2(0, 52)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.get_line_edit().add_theme_font_size_override("font_size", 20)
	parent.add_child(s)
	return s


func _options(parent: Control, label: String, items: Array) -> OptionButton:
	_form_label(parent, label)
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(str(items[i]), i)
	o.custom_minimum_size = Vector2(0, 52)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.add_theme_font_size_override("font_size", 20)
	o.clip_text = true
	parent.add_child(o)
	return o


func _append_log(line: String) -> void:
	if not is_inside_tree():
		return
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return
	_log.text += line + "\n"
	_log.scroll_vertical = _log.get_line_count()


func _build_request() -> PuzzleRequest:
	var req := PuzzleRequest.make(PuzzleRequest.Kind.DEBUG, int(_level.value), _seed.text.to_int())
	req.progression = true
	req.force_mode = _mode.selected - 1
	req.force_topology = _topology.selected - 1
	req.force_shape = _shape.selected - 1
	req.force_target = _target.value if _target.value > 0 else -1.0
	return req


func _on_generate() -> void:
	_request = _build_request()
	_log.text = ""
	var plan := LevelPlanner.plan(_request)
	_append_log("[PLAN] " + JSON.stringify(plan.to_dict()))
	_puzzle = PuzzleGenerator.new().generate(_request)
	_state = BoardState.new(_puzzle)
	Themes.apply(str(_puzzle.meta.get("theme", "cyber")))
	_board.set_palette(Themes.palette)
	_board.show_puzzle(_puzzle, _state)
	_update_info()


func _update_info() -> void:
	if _puzzle == null:
		return
	var a: Dictionary = _puzzle.meta.get("analysis", {})
	_info.text = "%s %s %dx%d %s | score %.1f (%s) target %.1f | rot %d nonlocal %d nodes %d | unique %s | min moves %d | %.1f ms | fp %s" % [
		GameMode.id_of(_puzzle.mode), _puzzle.topology.kind_name(), _puzzle.topology.width, _puzzle.topology.height,
		str(_puzzle.meta.get("shape", "")), float(_puzzle.meta.get("difficulty", 0)), str(_puzzle.meta.get("tier", "")),
		float(_puzzle.meta.get("target", 0)), int(a.get("decisions", 0)), int(a.get("nonlocal", 0)), int(a.get("nodes", 0)),
		str(_puzzle.unique), int(a.get("min_moves", 0)), float(_puzzle.meta.get("gen_ms", 0)), str(_puzzle.meta.get("fingerprint", ""))]


func _on_tap(cell: int, steps: int) -> void:
	if _state == null:
		return
	var changed := _state.rotate(cell, steps)
	if not changed.is_empty():
		_board.animate_rotation(changed, steps)
		if _state.is_solved():
			_board.play_victory(_puzzle.cores)


func _on_solve() -> void:
	if _puzzle == null:
		return
	var res := PuzzleSolver.new(_puzzle).solve(2, 50000, _state.rot)
	_append_log("[SOLVER] count=%d complete=%s nodes=%d backtracks=%d depth=%d local_undecided=%d %.1fms" % [
		int(res["count"]), str(res["complete"]), int(res["nodes"]), int(res["backtracks"]), int(res["max_depth"]),
		int(res["root_local_undecided"]), float(res["time_ms"])])
	var sols: Array = res["solutions"]
	var target: PackedInt32Array = sols[0] if not sols.is_empty() else _puzzle.solution_rotations()
	var changed := PackedInt32Array()
	for c in _puzzle.cell_count():
		if _puzzle.active[c] == 1 and not _state.matches(c, target[c]):
			_state.set_rotation(c, target[c])
			changed.append(c)
	_board.animate_rotation(changed, 1)
	if _state.is_solved():
		_board.play_victory(_puzzle.cores)


## Shows the solution one tile at a time (solution visualiser).
func _on_step() -> void:
	if _puzzle == null or _stepping:
		return
	_stepping = true
	var target := HintSystem.closest_solution(_puzzle, _state)
	for c in _puzzle.cell_count():
		if not is_inside_tree():
			return
		if _puzzle.active[c] == 1 and not _state.matches(c, target[c]):
			var steps := posmod(target[c] - _state.rot[c], _puzzle.dir_count())
			var changed := _state.rotate(c, steps)
			if changed.is_empty():
				_state.set_rotation(c, target[c])
				changed = PackedInt32Array([c])
			_board.animate_rotation(changed, steps)
			_board.set_highlight(changed)
			await get_tree().create_timer(0.12).timeout
	_stepping = false
	if is_inside_tree() and _state.is_solved():
		_board.play_victory(_puzzle.cores)


func _on_scramble() -> void:
	if _puzzle == null:
		return
	_state.reset()
	_board.show_puzzle(_puzzle, _state)


func _on_verify() -> void:
	if _puzzle == null:
		return
	var structure := Validator.structural_errors(_puzzle)
	var stored := Validator.verify_stored_solution(_puzzle)
	var res := PuzzleSolver.new(_puzzle).solve(2, 100000)
	var fp := Fingerprint.compute(_puzzle)
	_append_log("[VALIDATOR] structure=%s stored_solution=%s solutions=%d%s fingerprint_match=%s current_solved=%s" % [
		"OK" if structure == "" else structure, "PASS" if stored else "FAIL", int(res["count"]),
		"" if bool(res["complete"]) else "+", str(fp == str(_puzzle.meta.get("fingerprint", ""))), str(_state.is_solved())])


func _on_export() -> void:
	if _puzzle == null:
		return
	var text := JSON.stringify(_puzzle.to_dict(), "  ")
	DisplayServer.clipboard_set(text)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://exports"))
	var path := "user://exports/%s.json" % str(_puzzle.meta.get("fingerprint", "puzzle"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
	_append_log("[EXPORT] copied to clipboard and saved to %s (%s)" % [path, ProjectSettings.globalize_path(path)])


func _on_play() -> void:
	if _request:
		Game.pending_request = _request
		main.goto("game")


func _on_telemetry() -> void:
	_append_log("[TELEMETRY] " + JSON.stringify(Telemetry.summary(Save.data)))


func _on_batch(count: int) -> void:
	if _batch_task >= 0:
		_batch_cancel = true
		return
	_batch_cancel = false
	_batch_progress = 0
	_batch_total = count
	_progress.visible = true
	_progress.max_value = count
	var start := int(_level.value)
	_append_log("[BATCH] generating %d puzzles from level %d (tap again to cancel)" % [count, start])
	_batch_task = WorkerThreadPool.add_task(_batch_worker.bind(start, count), true, "debug batch")
	set_process(true)


func _batch_worker(start: int, count: int) -> void:
	var gen := PuzzleGenerator.new()
	var seen := {}
	var valid := 0
	var invalid := 0
	var duplicates := 0
	var total_ms := 0.0
	var total_diff := 0.0
	var done := 0
	for i in count:
		if _batch_cancel:
			break
		var req := SeedManager.level_request(start + i)
		var t0 := Time.get_ticks_usec()
		var p := gen.generate(req)
		total_ms += (Time.get_ticks_usec() - t0) / 1000.0
		if Validator.structural_errors(p) == "" and Validator.verify_stored_solution(p):
			valid += 1
		else:
			invalid += 1
		var fp := str(p.meta.get("fingerprint", ""))
		if seen.has(fp):
			duplicates += 1
		seen[fp] = true
		total_diff += float(p.meta.get("difficulty", 0.0))
		done += 1
		_batch_mutex.lock()
		_batch_progress = done
		_batch_mutex.unlock()
	_batch_mutex.lock()
	_batch_report = {
		"generated": done, "valid": valid, "invalid": invalid, "duplicate": duplicates,
		"avg_difficulty": total_diff / maxf(1.0, done), "avg_ms": total_ms / maxf(1.0, done),
	}
	_batch_mutex.unlock()


func _process(_delta: float) -> void:
	if _batch_task < 0:
		return
	_batch_mutex.lock()
	var prog := _batch_progress
	_batch_mutex.unlock()
	_progress.value = prog
	if WorkerThreadPool.is_task_completed(_batch_task):
		WorkerThreadPool.wait_for_task_completion(_batch_task)
		_batch_task = -1
		_progress.visible = false
		var r := _batch_report
		_append_log("Generated: %d\nValid: %d\nInvalid: %d\nDuplicate: %d\nAverage Difficulty: %.1f\nAverage Generation Time: %.1fms" % [
			int(r.get("generated", 0)), int(r.get("valid", 0)), int(r.get("invalid", 0)), int(r.get("duplicate", 0)),
			float(r.get("avg_difficulty", 0.0)), float(r.get("avg_ms", 0.0))])


func on_back() -> bool:
	return false
