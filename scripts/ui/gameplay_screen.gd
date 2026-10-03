extends Control
## Gameplay screen: HUD + board + overlays (intro cards, hints, pause,
## results, replay, share). Orchestrates feedback (sound, haptics, particles)
## for every model event coming from GameSession.

const HINT_LEVELS := 5
const REPLAY_MAX_SECONDS := 8.0

var main: Node
var request: PuzzleRequest
var session: GameSession
var board: BoardView

var _title: Label
var _chips: HBoxContainer
var _timer_label: Label
var _moves_label: Label
var _moves_caption: Label
var _hint_btn: Button
var _undo_btn: Button
var _loading: Label
var _overlay: Control
var _bottom: HBoxContainer
var _waiting_key := ""
var _show_timer := false
var _last_tap_cell := -1
var _replaying := false
var _completion: Dictionary = {}
var _load_t := 0.0
var _replay_state: BoardState
var _replay_index := 0
var _replay_wait := 0.0
var _replay_last_t := 0.0
var _replay_scale := 1.0


func _ready() -> void:
	UiKit.full_rect(self)
	_build_ui()
	Game.puzzle_ready.connect(_on_puzzle_ready)
	Save.settings_changed.connect(_on_setting)
	Themes.theme_changed.connect(_on_theme_changed)
	var req: PuzzleRequest = Game.pending_request if Game.pending_request else Game.continue_request()
	Game.pending_request = null
	load_request(req)


# --- UI construction ----------------------------------------------------------

func _build_ui() -> void:
	var p := Themes.palette
	var safe := UiKit.safe_margins(get_viewport())
	var root := UiKit.margin(null, 22 + int(safe.position.x), 20 + int(safe.position.y), 22 + int(safe.size.x), 22 + int(safe.size.y))
	UiKit.full_rect(root)
	add_child(root)
	var col := UiKit.vbox(10)
	root.add_child(col)

	var top := UiKit.hbox(12)
	top.custom_minimum_size = Vector2(0, 108)
	var pause_btn := UiKit.icon_button("pause", _open_pause, 80)
	pause_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(pause_btn)
	var titles := UiKit.vbox(6)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	_title = UiKit.title("", 40, p.ui_text)
	titles.add_child(_title)
	_chips = UiKit.hbox(8)
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_child(_chips)
	top.add_child(titles)
	_timer_label = UiKit.label("", 24, p.ui_text, UiTheme.semi_font())
	_timer_label.custom_minimum_size = Vector2(80, 0)
	_timer_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(_timer_label)
	col.add_child(top)

	var board_holder := Control.new()
	board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(board_holder)
	board = BoardView.new()
	UiKit.full_rect(board)
	board_holder.add_child(board)
	board.cell_tapped.connect(_on_cell_tapped)
	board.cell_double_tapped.connect(_on_cell_double_tapped)
	board.empty_double_tapped.connect(func(): board.reset_view())
	board.two_finger_tapped.connect(_on_two_finger)
	board.gesture_used.connect(_on_gesture)
	board.victory_finished.connect(_on_victory_finished)
	_loading = UiKit.label(tr("GENERATING"), 26, Color(p.ui_text, 0.55), UiTheme.semi_font())
	UiKit.full_rect(_loading)
	_loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_holder.add_child(_loading)

	_bottom = UiKit.hbox(16)
	_bottom.custom_minimum_size = Vector2(0, 112)
	_bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint_btn = UiKit.icon_button("hint", _open_hints, 96, p.lit)
	_undo_btn = UiKit.icon_button("undo", _on_undo, 96)
	var moves := UiKit.vbox(0)
	moves.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moves.alignment = BoxContainer.ALIGNMENT_CENTER
	_moves_label = UiKit.title("0", 44, p.ui_text)
	_moves_caption = UiKit.caption(tr("MOVES"), Color(p.ui_text, 0.45), 17, HORIZONTAL_ALIGNMENT_CENTER)
	moves.add_child(_moves_label)
	moves.add_child(_moves_caption)
	_bottom.add_child(_hint_btn)
	_bottom.add_child(moves)
	_bottom.add_child(_undo_btn)
	col.add_child(_bottom)
	_apply_handedness()


func _apply_handedness() -> void:
	# Right-handed: hint far left, menu far right; left-handed mirrors so the
	# most used controls sit under the thumb.
	var order: Array = _bottom.get_meta("order", [])
	if order.is_empty():
		order = _bottom.get_children()
		_bottom.set_meta("order", order)
	var left: bool = Save.setting("left_handed", false)
	for i in order.size():
		var node: Node = order[order.size() - 1 - i] if left else order[i]
		_bottom.move_child(node, i)


# --- Loading --------------------------------------------------------------------

func load_request(req: PuzzleRequest) -> void:
	Game.generator.allow_background = false
	request = req
	_close_overlay()
	_loading.visible = true
	_load_t = 0.0
	board.interactive = false
	var p := Game.generator.request(req, Game.avoid_list(req))
	if p:
		_start(p)
	else:
		_waiting_key = req.cache_key()


func _on_puzzle_ready(key: String, p: Puzzle) -> void:
	if key == _waiting_key:
		_waiting_key = ""
		_start(p)


func _start(p: Puzzle) -> void:
	_loading.visible = false
	session = GameSession.new(p, request)
	var saved := Game.saved_session_for(request)
	if not saved.is_empty() and session.restore(saved):
		main.toast(tr("PROGRESS_RESTORED"), 1.6)
	Themes.apply(Themes.resolve_for_puzzle(str(p.meta.get("theme", ""))))
	board.set_palette(Themes.palette)
	board.apply_user_settings(Save.settings())
	board.show_puzzle(p, session.state, session)
	board.interactive = not session.solved
	_show_timer = bool(Save.setting("show_timer", false)) or request.kind in [PuzzleRequest.Kind.DAILY, PuzzleRequest.Kind.CHALLENGE]
	_hint_btn.disabled = request.kind == PuzzleRequest.Kind.CHALLENGE
	_update_hud()
	_update_music()
	_show_intros(p)


func _process(delta: float) -> void:
	if _replaying:
		_tick_replay(delta)
	if session and not _replaying:
		session.tick(delta)
		if _show_timer:
			_timer_label.text = I18n.format_time(session.elapsed)
	if _loading.visible:
		_load_t += delta
		_loading.text = tr("GENERATING") + ".".repeat(int(_load_t * 3.0) % 4)


# --- HUD ------------------------------------------------------------------------

func _update_hud() -> void:
	if session == null:
		return
	var p := session.puzzle
	match request.kind:
		PuzzleRequest.Kind.DAILY:
			_title.text = "%s #%s" % [tr("DAILY"), request.label]
		PuzzleRequest.Kind.ZEN:
			_title.text = tr("ZEN")
		PuzzleRequest.Kind.CHALLENGE:
			_title.text = tr("TIER_" + request.label.to_upper())
		PuzzleRequest.Kind.CUSTOM:
			_title.text = "%s %s" % [tr("SEED"), I18n.format_int(request.level)]
		_:
			_title.text = "%s %s" % [tr("LEVEL"), I18n.format_int(request.level)]
	for ch in _chips.get_children():
		ch.queue_free()
	var pal := Themes.palette
	_chips.add_child(UiKit.chip(tr(GameMode.title_key(p.mode)), pal.lit))
	var event := str(p.meta.get("event", ""))
	if event != "":
		_chips.add_child(UiKit.chip(tr("EVENT_" + event.to_upper()), pal.lit2, true))
	elif p.unique:
		_chips.add_child(UiKit.chip(tr("MODIFIER_PERFECT"), pal.lit2))
	elif not p.link_groups.is_empty():
		_chips.add_child(UiKit.chip(tr("MODIFIER_CHAOS"), pal.lit2))
	var tier := tr(DifficultyCurve.tier_key(session.difficulty()))
	_chips.add_child(UiKit.chip("%d · %s" % [int(round(session.difficulty())), tier], Color(pal.ui_text, 0.8)))
	_moves_label.text = str(session.moves)
	_timer_label.text = I18n.format_time(session.elapsed) if _show_timer else ""
	_undo_btn.disabled = not session.can_undo()


func _update_music() -> void:
	if session == null:
		return
	var complexity := clampf(log(1.0 + session.difficulty()) / log(600.0), 0.0, 1.0)
	var total := 0
	var good := 0
	var matched := Connectivity.matched_mask(session.puzzle, session.state.masks())
	for c in session.puzzle.cell_count():
		var m := session.state.mask(c)
		if m != 0:
			total += Topology.popcount(m)
			good += Topology.popcount(matched[c])
	var progress := float(good) / float(total) if total > 0 else 0.0
	if session.puzzle.mode == GameMode.DARK:
		progress = 1.0 - progress
	Audio.set_intensity(complexity, progress)


# --- Input ----------------------------------------------------------------------

func _on_cell_tapped(cell: int, steps: int) -> void:
	if session == null or session.solved or _replaying:
		return
	var res := session.rotate(cell, steps)
	if bool(res["refused"]):
		board.shake(cell)
		Audio.play("denied")
		Haptics.pulse(Haptics.Kind.DENIED)
		return
	_last_tap_cell = cell
	var changed: PackedInt32Array = res["changed"]
	board.animate_rotation(changed, steps)
	Audio.play("rotate", 0.94 + 0.12 * randf() + (0.0 if steps > 0 else -0.12))
	Haptics.pulse(Haptics.Kind.TAP)
	if int(res["matched_delta"]) > 0:
		board.spark_connections(changed)
		Audio.play("connect", 1.0 + 0.04 * int(res["matched_delta"]))
		Haptics.pulse(Haptics.Kind.CONNECT)
	board.clear_highlight()
	_update_hud()
	_update_music()
	if bool(res["solved"]):
		_on_solved()
	else:
		Game.store_session(session)


func _on_gesture(kind: String) -> void:
	if session:
		session.gestures[kind] = true


func _on_cell_double_tapped(cell: int) -> void:
	if session == null or session.solved:
		return
	if str(Save.setting("double_tap", "pin")) != "pin":
		_on_cell_tapped(cell, 1)
		return
	# The first tap of the double tap rotated the tile: revert it, then pin.
	if session.can_undo() and _last_tap_cell == cell:
		var changed := session.undo()
		session.undos -= 1
		session.moves = maxi(0, session.moves - 1)
		board.animate_rotation(changed, -1)
	var pinned := session.toggle_pin(cell)
	Audio.play("ui", 1.3 if pinned else 0.9)
	Haptics.pulse(Haptics.Kind.IMPORTANT)
	board.refresh()
	_update_hud()


func _on_two_finger() -> void:
	match str(Save.setting("two_finger_tap", "undo")):
		"undo":
			_on_undo()
		"reset":
			_on_reset()


func _on_undo() -> void:
	if session == null:
		return
	var changed := session.undo()
	if changed.is_empty():
		return
	board.animate_rotation(changed, -1)
	Audio.play("rotate", 0.8)
	_update_hud()
	_update_music()
	Game.store_session(session)


func _on_reset() -> void:
	if session == null or session.solved:
		return
	session.reset()
	board.show_puzzle(session.puzzle, session.state, session)
	board.interactive = true
	_update_hud()
	_update_music()


# --- Victory --------------------------------------------------------------------

func _on_solved() -> void:
	board.interactive = false
	var p := session.puzzle
	board.play_victory(_victory_origins())
	var boss := bool(p.meta.get("boss", false))
	Audio.duck(2.2)
	Audio.play("boss" if boss else "solve")
	Haptics.pulse(Haptics.Kind.BOSS if boss else Haptics.Kind.SOLVE)
	main.flare(1.4 if boss else 0.9)
	if not _replaying:
		_completion = Game.complete(session)
		if request.kind == PuzzleRequest.Kind.LEVEL:
			Game.prefetch_next()


## Energy starts at the cores, or at the last tile the player touched.
func _victory_origins() -> PackedInt32Array:
	var p := session.puzzle
	if not p.cores.is_empty():
		return p.cores
	if _last_tap_cell >= 0:
		return PackedInt32Array([_last_tap_cell])
	return PackedInt32Array()


func _on_victory_finished() -> void:
	_replaying = false
	_show_results()


func _show_results() -> void:
	# Prefetch the next level only now: a short hitch is harmless here.
	Game.generator.allow_background = true
	var p := Themes.palette
	var box := UiKit.vbox(18)
	var boss := bool(session.puzzle.meta.get("boss", false))
	box.add_child(UiKit.gradient_title(tr("BOSS_DEFEATED") if boss else tr("SOLVED"), 60, p.lit, p.lit2))
	var sub := UiKit.hbox(8)
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	sub.add_child(UiKit.chip(_title.text, Color(p.ui_text, 0.85)))
	sub.add_child(UiKit.chip(tr(DifficultyCurve.tier_key(session.difficulty())), p.lit))
	if session.is_perfect():
		sub.add_child(UiKit.chip("✦ " + tr("PERFECT"), p.lit2, true))
	box.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var min_moves := int(session.puzzle.meta.get("min_moves", 0))
	grid.add_child(UiKit.stat_tile(str(session.moves), "%s · %s %d" % [tr("MOVES"), tr("MIN"), min_moves], p, p.lit))
	grid.add_child(UiKit.stat_tile(I18n.format_time(session.elapsed), tr("TIME"), p))
	grid.add_child(UiKit.stat_tile(str(int(round(session.difficulty()))), tr("DIFFICULTY"), p, p.lit2))
	grid.add_child(UiKit.stat_tile(str(session.hints_used), tr("HINTS"), p))
	box.add_child(grid)
	var ach: PackedStringArray = _completion.get("achievements", PackedStringArray())
	if not ach.is_empty():
		Audio.play("achievement")
		var flow := HFlowContainer.new()
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		for id in ach:
			flow.add_child(UiKit.chip("🏆 " + tr("ACH_" + id.to_upper()), p.lit2))
		box.add_child(flow)
	box.add_child(UiKit.caption(session.code(), Color(p.ui_text, 0.35), 17, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.primary_button(_next_label(), _on_next, p.lit, p.lit2, 108))
	var row := UiKit.hbox(6)
	row.add_child(UiKit.labeled_icon("replay", tr("REPLAY"), _on_replay))
	row.add_child(UiKit.labeled_icon("share", tr("SHARE"), _on_share))
	var fav := UiKit.labeled_icon(_fav_icon(), tr("FAVORITE"), Callable())
	var fav_btn: Button = fav.get_child(0)
	fav_btn.pressed.connect(_on_favorite.bind(fav_btn))
	row.add_child(fav)
	row.add_child(UiKit.labeled_icon("grid", tr("MENU"), _to_menu))
	box.add_child(row)
	_show_overlay(box, false)


func _next_label() -> String:
	match request.kind:
		PuzzleRequest.Kind.LEVEL:
			return "%s  →  %s %s" % [tr("NEXT"), tr("LEVEL"), I18n.format_int(request.level + 1)]
		PuzzleRequest.Kind.ZEN, PuzzleRequest.Kind.CHALLENGE:
			return tr("NEXT")
	return tr("MENU")


func _on_next() -> void:
	match request.kind:
		PuzzleRequest.Kind.LEVEL:
			load_request(Game.continue_request())
		PuzzleRequest.Kind.ZEN:
			load_request(Game.zen_request())
		PuzzleRequest.Kind.CHALLENGE:
			var idx := 0
			for i in Game.CHALLENGES.size():
				if Game.CHALLENGES[i]["id"] == request.label:
					idx = i
			load_request(Game.challenge_request(idx))
		_:
			_to_menu()


## Replays every recorded move from the scrambled start, compressed into a
## few seconds, then shows the victory sequence again. Driven from _process
## (no coroutines that could outlive the screen).
func _on_replay() -> void:
	_close_overlay()
	_replaying = true
	_replay_state = BoardState.new(session.puzzle)
	board.show_puzzle(session.puzzle, _replay_state, null)
	board.interactive = false
	var total := session.elapsed if session.elapsed > 0.0 else 1.0
	_replay_scale = minf(1.0, REPLAY_MAX_SECONDS / total)
	_replay_index = 0
	_replay_wait = 0.35
	_replay_last_t = 0.0


func _tick_replay(delta: float) -> void:
	if _replay_state == null:
		return
	_replay_wait -= delta
	if _replay_wait > 0.0:
		return
	var count := session.replay_cells.size()
	if _replay_index >= count:
		_replay_state = null
		board.play_victory(_victory_origins())
		Audio.play("solve")
		return
	var i := _replay_index
	_replay_index += 1
	var cell := session.replay_cells[i]
	if cell < 0:
		_replay_state.reset()
		board.refresh()
	else:
		var changed := _replay_state.rotate(cell, session.replay_steps[i])
		board.animate_rotation(changed, session.replay_steps[i])
		Audio.play("rotate", 1.1)
	if _replay_index < count:
		var t := session.replay_times[_replay_index] * _replay_scale
		_replay_wait = clampf(t - _replay_last_t, 0.03, 0.6)
		_replay_last_t = t
	else:
		_replay_wait = 0.4


func _on_share() -> void:
	var text := "INFINITE LOOP: ASCENSION\n%s\n%s %d (%s)\n%s %d\n%s %s\n%s" % [
		_title.text, tr("DIFFICULTY"), int(round(session.difficulty())), tr(DifficultyCurve.tier_key(session.difficulty())),
		tr("MOVES"), session.moves, tr("TIME"), I18n.format_time(session.elapsed), session.code()]
	DisplayServer.clipboard_set(text)
	var path := _save_share_image()
	main.toast(tr("SHARE_COPIED") + ("\n" + path if path != "" else ""), 2.5)


func _fav_icon() -> String:
	return "star_fill" if Game.is_favorite(session.code()) else "star"


func _on_favorite(button: Button = null) -> void:
	var now := Game.toggle_favorite(session.code())
	main.toast(tr("FAVORITE_ADDED") if now else tr("FAVORITE_REMOVED"), 1.4)
	if button and button.has_meta("icon"):
		(button.get_meta("icon") as VectorIcon).set_icon(_fav_icon())


func _save_share_image() -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://shares"))
	var path := "user://shares/%s.png" % session.code().replace(":", "-")
	return path if img.save_png(path) == OK else ""


func _to_menu() -> void:
	if session and not session.solved and request.kind != PuzzleRequest.Kind.LEVEL:
		Game.abandon(session)
	main.goto("menu", false)


func _to_settings() -> void:
	# Come back to this exact puzzle (and its progress) afterwards.
	Game.pending_request = request
	main.goto("settings")


# --- Hints ----------------------------------------------------------------------

func _open_hints() -> void:
	if session == null or session.solved:
		return
	var p := Themes.palette
	var box := UiKit.vbox(12)
	var head := UiKit.hbox(12)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var bulb := VectorIcon.new("hint", p.lit)
	bulb.custom_minimum_size = Vector2(44, 44)
	head.add_child(bulb)
	head.add_child(UiKit.title(tr("HINT"), 40, p.ui_text))
	box.add_child(head)
	box.add_child(UiKit.label(tr("HINT_HELP"), 21, Color(p.ui_text, 0.55)))
	for lvl in range(1, HINT_LEVELS + 1):
		var b := UiKit.button("%d   %s" % [lvl, tr("HINT_%d" % lvl)], _use_hint.bind(lvl), 82)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(b)
	box.add_child(UiKit.button(tr("CANCEL"), _close_overlay, 72))
	_show_overlay(box, true)


func _use_hint(level: int) -> void:
	_close_overlay()
	var hint := HintSystem.make_hint(level, session)
	if hint.is_empty():
		return
	Audio.play("hint")
	if level == 1:
		session.hints_used += 1
		session.max_hint_level = maxi(session.max_hint_level, 1)
		board.set_highlight(hint["highlight"])
	else:
		var changed := session.apply_hint(hint)
		board.animate_rotation(changed, 1)
		board.set_highlight(hint["highlight"])
		board.spark_connections(changed)
	_update_hud()
	_update_music()
	if session.solved:
		_on_solved()
	else:
		Game.store_session(session)


# --- Pause ----------------------------------------------------------------------

func _open_pause() -> void:
	if session == null or session.solved or _replaying:
		return
	session.paused = true
	var p := Themes.palette
	var box := UiKit.vbox(12)
	box.add_child(UiKit.title(tr("PAUSED"), 44, p.ui_text))
	box.add_child(UiKit.caption(session.code(), Color(p.ui_text, 0.4), 17, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.spacer(4))
	box.add_child(UiKit.primary_button(tr("RESUME"), _close_overlay, p.lit, p.lit2))
	box.add_child(UiKit.button(tr("RESET"), func():
		_close_overlay()
		_on_reset()
	))
	box.add_child(UiKit.button(tr("COPY_CODE"), func():
		DisplayServer.clipboard_set(session.code())
		main.toast(tr("CODE_COPIED"))
	))
	box.add_child(UiKit.button(tr("FAVORITE") + ("  ★" if Game.is_favorite(session.code()) else ""), func():
		_on_favorite()
		_close_overlay()
	))
	box.add_child(UiKit.button(tr("OBJECTIVE"), func():
		_close_overlay()
		_show_mode_card(session.puzzle.mode, true)
	))
	box.add_child(UiKit.button(tr("SETTINGS"), _to_settings))
	box.add_child(UiKit.button(tr("MAIN_MENU"), _to_menu))
	_show_overlay(box, true)


func _show_overlay(content: Control, dismissable: bool) -> void:
	_remove_overlay()
	_overlay = UiKit.modal(self, content)
	_overlay.set_meta("dismissable", dismissable)


func _close_overlay() -> void:
	_remove_overlay()
	if session:
		session.paused = false


func _remove_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


# --- Intro cards ------------------------------------------------------------------

func _show_intros(p: Puzzle) -> void:
	var seen: Array = Save.data.get("seen_mechanics", [])
	var mode_key := "mode_" + GameMode.id_of(p.mode)
	if bool(p.meta.get("boss", false)):
		_show_boss_card(p)
		return
	if not seen.has(mode_key):
		seen.append(mode_key)
		Save.data["seen_mechanics"] = seen
		Save.mark_dirty()
		_show_mode_card(p.mode, false)
		return
	for mech in _mechanics(p):
		var key: String = "intro_" + str(mech)
		if not seen.has(key):
			seen.append(key)
			Save.data["seen_mechanics"] = seen
			Save.mark_dirty()
			_show_card(tr("INTRO_%s_TITLE" % str(mech).to_upper()), tr("INTRO_%s_TEXT" % str(mech).to_upper()))
			return
	main.toast(tr(GameMode.objective_key(p.mode)), 1.8)


func _mechanics(p: Puzzle) -> Array:
	var out: Array = []
	if p.locked.find(1) >= 0:
		out.append("locked")
	if p.portal_count() > 0:
		out.append("portal")
	if not p.link_groups.is_empty():
		out.append("link")
	if p.topology.kind == Topology.Kind.HEX:
		out.append("hex")
	if p.unique:
		out.append("perfect")
	if str(p.meta.get("shape", "rect")) != "rect":
		out.append("shape")
	return out


func _show_mode_card(mode: int, _from_menu: bool) -> void:
	_show_card(tr(GameMode.title_key(mode)), tr(GameMode.objective_key(mode)) + "\n\n" + tr("CONTROLS_HELP"))


func _show_boss_card(p: Puzzle) -> void:
	var lines: Array[String] = []
	lines.append("%dx%d %s" % [p.topology.width, p.topology.height, tr("GRID")])
	lines.append(tr(GameMode.title_key(p.mode)))
	if p.cores.size() > 0:
		lines.append("%d %s" % [p.cores.size(), tr("CORES")])
	if p.portal_count() > 0:
		lines.append("%d %s" % [p.portal_count(), tr("PORTALS")])
	var locks := 0
	for c in p.cell_count():
		locks += p.locked[c]
	if locks > 0:
		lines.append("%d %s" % [locks, tr("LOCKS")])
	if not p.link_groups.is_empty():
		lines.append("%d %s" % [p.link_groups.size(), tr("LINKS")])
	var event := str(p.meta.get("event", ""))
	_show_card(tr("EVENT_" + event.to_upper()), "\n".join(lines))


func _show_card(title_text: String, body: String) -> void:
	var p := Themes.palette
	var box := UiKit.vbox(18)
	box.add_child(UiKit.gradient_title(title_text, 48, p.lit, p.lit2))
	var lbl := UiKit.label(body, 25, Color(p.ui_text, 0.85))
	box.add_child(lbl)
	box.add_child(UiKit.primary_button(tr("GOT_IT"), _close_overlay, p.lit, p.lit2))
	_show_overlay(box, true)


# --- Misc ----------------------------------------------------------------------

## HUD labels carry explicit colours; refresh them when the theme changes
## between puzzles (Controls themselves follow the root Theme automatically).
func _on_theme_changed(p: Palette) -> void:
	_title.add_theme_color_override("font_color", p.ui_text)
	_timer_label.add_theme_color_override("font_color", p.ui_text)
	_moves_label.add_theme_color_override("font_color", p.ui_text)
	_moves_caption.add_theme_color_override("font_color", Color(p.ui_text, 0.45))
	_loading.add_theme_color_override("font_color", Color(p.ui_text, 0.55))
	if _hint_btn.has_meta("icon"):
		(_hint_btn.get_meta("icon") as VectorIcon).color = p.lit
		(_hint_btn.get_meta("icon") as VectorIcon).queue_redraw()
	board.set_palette(p)
	_update_hud()


func _on_setting(key: String, _value: Variant) -> void:
	match key:
		"left_handed":
			_apply_handedness()
		"animation_speed", "reduce_motion", "effects":
			board.apply_user_settings(Save.settings())
		"high_contrast", "colorblind", "theme":
			if session:
				Themes.apply(Themes.resolve_for_puzzle(str(session.puzzle.meta.get("theme", ""))), true)
				board.set_palette(Themes.palette)
				board.refresh()


func on_back() -> bool:
	if _overlay:
		if bool(_overlay.get_meta("dismissable", true)):
			_close_overlay()
			return true
		return false
	_open_pause()
	return true


func on_leave() -> void:
	Game.generator.allow_background = false
	if session and not session.solved:
		Game.store_session(session)
	Save.flush()
