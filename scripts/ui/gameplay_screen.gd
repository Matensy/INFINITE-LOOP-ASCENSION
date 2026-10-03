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
var _subtitle: Label
var _timer_label: Label
var _moves_label: Label
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
	var root := UiKit.margin(null, 18 + int(safe.position.x), 14 + int(safe.position.y), 18 + int(safe.size.x), 14 + int(safe.size.y))
	UiKit.full_rect(root)
	add_child(root)
	var col := UiKit.vbox(8)
	root.add_child(col)

	var top := UiKit.hbox(10)
	top.custom_minimum_size = Vector2(0, 112)
	var menu_btn := UiKit.icon_button("≡", _open_pause, 88)
	top.add_child(menu_btn)
	var titles := UiKit.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = UiKit.title("", 38, p.ui_text)
	_subtitle = UiKit.label("", 20, p.ui_dim)
	_subtitle.max_lines_visible = 2
	titles.add_child(_title)
	titles.add_child(_subtitle)
	top.add_child(titles)
	_timer_label = UiKit.label("", 26, p.ui_text, UiTheme.bold_font())
	_timer_label.custom_minimum_size = Vector2(88, 0)
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
	_loading = UiKit.title(tr("GENERATING"), 30, p.ui_dim)
	UiKit.full_rect(_loading)
	_loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_holder.add_child(_loading)

	_bottom = UiKit.hbox(12)
	_bottom.custom_minimum_size = Vector2(0, 110)
	_hint_btn = UiKit.button(tr("HINT"), _open_hints)
	_hint_btn.custom_minimum_size = Vector2(150, 96)
	_undo_btn = UiKit.icon_button("↶", _on_undo, 96)
	_moves_label = UiKit.label("", 26, p.ui_text, UiTheme.bold_font())
	_moves_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_moves_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var pause_btn := UiKit.button(tr("MENU"), _open_pause)
	pause_btn.custom_minimum_size = Vector2(150, 96)
	_bottom.add_child(_hint_btn)
	_bottom.add_child(_undo_btn)
	_bottom.add_child(_moves_label)
	_bottom.add_child(pause_btn)
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
	if request.kind == PuzzleRequest.Kind.LEVEL:
		Game.prefetch_next()
	_show_intros(p)


func _process(delta: float) -> void:
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
	var parts: Array[String] = [tr(GameMode.title_key(p.mode))]
	if p.unique:
		parts.append(tr("MODIFIER_PERFECT"))
	var event := str(p.meta.get("event", ""))
	if not p.link_groups.is_empty() and event != "chaos":
		parts.append(tr("MODIFIER_CHAOS"))
	if event != "":
		parts.append(tr("EVENT_" + event.to_upper()))
	parts.append("%s %d" % [tr("DIFFICULTY"), int(round(session.difficulty()))])
	parts.append(tr(DifficultyCurve.tier_key(session.difficulty())))
	_subtitle.text = " · ".join(parts)
	_moves_label.text = "%s: %d" % [tr("MOVES"), session.moves]
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
	var origins := p.cores if not p.cores.is_empty() else PackedInt32Array([_last_tap_cell])
	board.play_victory(origins)
	var boss := bool(p.meta.get("boss", false))
	Audio.duck(2.2)
	Audio.play("boss" if boss else "solve")
	Haptics.pulse(Haptics.Kind.BOSS if boss else Haptics.Kind.SOLVE)
	main.flare(1.4 if boss else 0.9)
	if not _replaying:
		_completion = Game.complete(session)


func _on_victory_finished() -> void:
	_replaying = false
	_show_results()


func _show_results() -> void:
	var p := Themes.palette
	var box := UiKit.vbox(12)
	var boss := bool(session.puzzle.meta.get("boss", false))
	box.add_child(UiKit.title(tr("BOSS_DEFEATED") if boss else tr("SOLVED"), 46, p.lit))
	if session.is_perfect():
		box.add_child(UiKit.label("✦ " + tr("PERFECT") + " ✦", 26, p.ui_accent))
	var grid := UiKit.vbox(6)
	grid.add_child(UiKit.stat_row(_title.text, "", p.ui_dim, p.ui_text))
	var diff_text := "%d · %s" % [int(round(session.difficulty())), tr(DifficultyCurve.tier_key(session.difficulty()))]
	var moves_text := "%d  (%s %d)" % [session.moves, tr("MIN"), int(session.puzzle.meta.get("min_moves", 0))]
	grid.add_child(UiKit.stat_row(tr("DIFFICULTY"), diff_text, p.ui_dim, p.ui_text))
	grid.add_child(UiKit.stat_row(tr("MOVES"), moves_text, p.ui_dim, p.ui_text))
	grid.add_child(UiKit.stat_row(tr("TIME"), I18n.format_time(session.elapsed), p.ui_dim, p.ui_text))
	grid.add_child(UiKit.stat_row(tr("HINTS"), str(session.hints_used), p.ui_dim, p.ui_text))
	if session.puzzle.unique:
		grid.add_child(UiKit.stat_row(tr("MISTAKES"), str(session.mistakes), p.ui_dim, p.ui_text))
	box.add_child(grid)
	var ach: PackedStringArray = _completion.get("achievements", PackedStringArray())
	for id in ach:
		box.add_child(UiKit.label("🏆 " + tr("ACH_" + id.to_upper()), 24, p.ui_accent))
	if not ach.is_empty():
		Audio.play("achievement")
	var code_lbl := UiKit.label(session.code(), 20, p.ui_dim)
	box.add_child(code_lbl)
	var next := UiKit.primary_button(_next_label(), _on_next, p.ui_accent)
	box.add_child(next)
	var row := UiKit.hbox(12)
	for spec in [[tr("REPLAY"), _on_replay], [tr("SHARE"), _on_share], [tr("MENU"), _to_menu]]:
		var b := UiKit.button(spec[0], spec[1], 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	var fav := UiKit.icon_button(_fav_symbol(), Callable(), 84)
	fav.pressed.connect(_on_favorite.bind(fav))
	row.add_child(fav)
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
## few seconds, then shows the victory sequence again.
func _on_replay() -> void:
	_close_overlay()
	_replaying = true
	var state := BoardState.new(session.puzzle)
	board.show_puzzle(session.puzzle, state, null)
	board.interactive = false
	var count := session.replay_cells.size()
	var total := session.elapsed if session.elapsed > 0.0 else 1.0
	var scale := minf(1.0, REPLAY_MAX_SECONDS / total)
	var last_t := 0.0
	for i in count:
		var t := session.replay_times[i] * scale
		var wait := clampf(t - last_t, 0.03, 0.6)
		last_t = t
		await get_tree().create_timer(wait).timeout
		if not is_inside_tree():
			return
		var cell := session.replay_cells[i]
		if cell < 0:
			state.reset()
			board.refresh()
			continue
		var changed := state.rotate(cell, session.replay_steps[i])
		board.animate_rotation(changed, session.replay_steps[i])
		Audio.play("rotate", 1.1)
	await get_tree().create_timer(0.4).timeout
	if is_inside_tree():
		var p := session.puzzle
		board.play_victory(p.cores if not p.cores.is_empty() else PackedInt32Array([_last_tap_cell]))
		Audio.play("solve")


func _on_share() -> void:
	var text := "INFINITE LOOP: ASCENSION\n%s\n%s %d (%s)\n%s %d\n%s %s\n%s" % [
		_title.text, tr("DIFFICULTY"), int(round(session.difficulty())), tr(DifficultyCurve.tier_key(session.difficulty())),
		tr("MOVES"), session.moves, tr("TIME"), I18n.format_time(session.elapsed), session.code()]
	DisplayServer.clipboard_set(text)
	var path := _save_share_image()
	main.toast(tr("SHARE_COPIED") + ("\n" + path if path != "" else ""), 2.5)


func _fav_symbol() -> String:
	return "★" if Game.is_favorite(session.code()) else "☆"


func _on_favorite(button: Button = null) -> void:
	var now := Game.toggle_favorite(session.code())
	main.toast(tr("FAVORITE_ADDED") if now else tr("FAVORITE_REMOVED"), 1.4)
	if button:
		button.text = _fav_symbol()


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
	box.add_child(UiKit.title(tr("HINT"), 38, p.ui_accent))
	for lvl in range(1, HINT_LEVELS + 1):
		var b := UiKit.button("%d · %s" % [lvl, tr("HINT_%d" % lvl)], _use_hint.bind(lvl), 80)
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
	box.add_child(UiKit.title(tr("PAUSED"), 40, p.ui_accent))
	box.add_child(UiKit.label(session.code(), 20, p.ui_dim))
	box.add_child(UiKit.primary_button(tr("RESUME"), _close_overlay, p.ui_accent))
	box.add_child(UiKit.button(tr("RESET"), func():
		_close_overlay()
		_on_reset()
	))
	box.add_child(UiKit.button(tr("COPY_CODE"), func():
		DisplayServer.clipboard_set(session.code())
		main.toast(tr("CODE_COPIED"))
	))
	box.add_child(UiKit.button(tr("FAVORITE") + "  " + _fav_symbol(), func():
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
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.62)
	UiKit.full_rect(shade)
	add_child(shade)
	_overlay = shade
	shade.set_meta("dismissable", dismissable)
	var center := CenterContainer.new()
	UiKit.full_rect(center)
	shade.add_child(center)
	var panel := UiKit.panel(content)
	panel.custom_minimum_size = Vector2(minf(640, get_viewport_rect().size.x - 50), 0)
	center.add_child(panel)
	shade.modulate.a = 0.0
	create_tween().tween_property(shade, "modulate:a", 1.0, 0.15)


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
	var box := UiKit.vbox(14)
	box.add_child(UiKit.title(title_text, 40, p.lit))
	var lbl := UiKit.label(body, 25, p.ui_text)
	box.add_child(lbl)
	box.add_child(UiKit.primary_button(tr("GOT_IT"), _close_overlay, p.ui_accent))
	_show_overlay(box, true)


# --- Misc ----------------------------------------------------------------------

## HUD labels carry explicit colours; refresh them when the theme changes
## between puzzles (Controls themselves follow the root Theme automatically).
func _on_theme_changed(p: Palette) -> void:
	_title.add_theme_color_override("font_color", p.ui_text)
	_subtitle.add_theme_color_override("font_color", p.ui_dim)
	_timer_label.add_theme_color_override("font_color", p.ui_text)
	_moves_label.add_theme_color_override("font_color", p.ui_text)
	_loading.add_theme_color_override("font_color", p.ui_dim)
	board.set_palette(p)


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
	if session and not session.solved:
		Game.store_session(session)
	Save.flush()
