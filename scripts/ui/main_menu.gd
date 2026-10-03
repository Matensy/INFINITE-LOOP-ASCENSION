extends Control
## Title screen: gradient logo, a live solved network as hero, one primary
## action (continue the endless climb) and a grid of mode / utility tiles.

static var _crash_prompt_shown := false

var main: Node
var _board: BoardView
var _overlay: Control
var _title_tap := 0


func _ready() -> void:
	UiKit.full_rect(self)
	Themes.apply(Themes.resolve_for_puzzle(ThemeCatalog.DEFAULT_ID))
	var p := Themes.palette
	var safe := UiKit.safe_margins(get_viewport())
	var root := UiKit.margin(null, 40 + int(safe.position.x), 36 + int(safe.position.y), 40 + int(safe.size.x), 28 + int(safe.size.y))
	UiKit.full_rect(root)
	add_child(root)
	var col := UiKit.vbox(18)
	root.add_child(col)

	var logo := UiKit.vbox(0)
	var title := UiKit.gradient_title("INFINITE LOOP", 70, p.lit, p.lit2)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_title_input)
	logo.add_child(title)
	var sub := UiKit.label("ASCENSION", 24, Color(p.ui_text, 0.7), UiKit.spaced_font(UiTheme.semi_font(), 12))
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	logo.add_child(sub)
	col.add_child(logo)

	var chips := UiKit.hbox(10)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_child(UiKit.chip(tr(Game.title_key()), p.lit))
	var stars := Game.prestige_stars()
	if stars > 0:
		chips.add_child(UiKit.chip("✦ %d" % stars, p.lit2))
	col.add_child(chips)

	_board = BoardView.new()
	_board.custom_minimum_size = Vector2(0, 300)
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.attract = true
	_board.interactive = false
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_board)

	var play_text := "%s  ·  %s %s" % [tr("PLAY"), tr("LEVEL"), I18n.format_int(Save.current_level())]
	col.add_child(UiKit.primary_button(play_text, _on_continue, p.lit, p.lit2, 112))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var daily_req := Game.daily_request()
	var daily_badge := "✓" if Game.is_daily_done(daily_req.label) else ""
	var tiles := [
		["calendar", tr("DAILY"), _on_daily, p.lit, daily_badge],
		["infinity", tr("ZEN"), _on_zen, p.lit.lerp(p.lit2, 0.5), ""],
		["bolt", tr("CHALLENGE"), _on_challenge, p.lit2, ""],
		["hash", tr("SEED"), _on_seed, p.lit, ""],
		["user", tr("PROFILE"), func(): main.goto("profile"), p.lit.lerp(p.lit2, 0.5), ""],
		["settings", tr("SETTINGS_SHORT"), func(): main.goto("settings"), p.lit2, ""],
	]
	for t in tiles:
		var b := UiKit.tile_button(t[0], t[1], t[2], t[3], t[4])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	col.add_child(grid)

	var footer := UiKit.hbox(10)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	var ver := UiKit.label("v%s" % ProjectSettings.get_setting("application/config/version", "0.1.0"), 18, Color(p.ui_text, 0.35))
	ver.autowrap_mode = TextServer.AUTOWRAP_OFF
	footer.add_child(ver)
	if OS.is_debug_build():
		var dbg := Button.new()
		dbg.text = "DEBUG"
		dbg.flat = true
		dbg.focus_mode = Control.FOCUS_NONE
		dbg.add_theme_font_size_override("font_size", 18)
		dbg.add_theme_color_override("font_color", Color(p.ui_text, 0.35))
		dbg.pressed.connect(func(): main.goto("debug"))
		footer.add_child(dbg)
	col.add_child(footer)
	_setup_decoration()
	if Save.crashed_last_time and not _crash_prompt_shown:
		_crash_prompt_shown = true
		_show_diagnostics.call_deferred(true)
	elif Save.safe_mode_applied:
		main.toast.call_deferred(tr("SAFE_MODE_ON"), 3.0)


func _setup_decoration() -> void:
	var req := PuzzleRequest.make(PuzzleRequest.Kind.DEBUG, 60, 4242)
	req.force_mode = GameMode.CORE
	req.force_target = 16.0
	var p := Game.generator.generate_now(req)
	var solved := BoardState.new(p, p.solution_rotations())
	_board.palette = Themes.palette
	_board.apply_user_settings(Save.settings())
	_board.show_puzzle(p, solved)


func _on_title_input(event: InputEvent) -> void:
	# Hidden debug entry in release builds: tap the title 7 times.
	if event is InputEventMouseButton and event.pressed:
		_title_tap += 1
		if _title_tap >= 7:
			main.goto("debug")


func _start(req: PuzzleRequest) -> void:
	Game.pending_request = req
	main.goto("game")


func _on_continue() -> void:
	_start(Game.continue_request())


func _on_daily() -> void:
	_start(Game.daily_request())


func _on_zen() -> void:
	_start(Game.zen_request())


func _on_challenge() -> void:
	var p := Themes.palette
	var box := UiKit.vbox(14)
	box.add_child(UiKit.title(tr("CHALLENGE"), 40, p.ui_text))
	box.add_child(UiKit.label(tr("CHALLENGE_DESC"), 22, Color(p.ui_text, 0.6)))
	box.add_child(UiKit.spacer(4))
	for i in Game.CHALLENGES.size():
		var ch: Dictionary = Game.CHALLENGES[i]
		var label := "%s  ·  %d" % [tr("TIER_" + str(ch["id"]).to_upper()), int(ch["target"])]
		box.add_child(UiKit.button(label, _start_challenge.bind(i)))
	box.add_child(UiKit.button(tr("CANCEL"), _close_overlay, 76))
	_show_overlay(box)


func _on_seed() -> void:
	var p := Themes.palette
	var box := UiKit.vbox(16)
	box.add_child(UiKit.title(tr("ENTER_SEED"), 40, p.ui_text))
	box.add_child(UiKit.label(tr("SEED_HELP"), 21, Color(p.ui_text, 0.6)))
	var edit := LineEdit.new()
	edit.placeholder_text = "ASCENSION-18492-839204918230"
	edit.custom_minimum_size = Vector2(0, 88)
	box.add_child(edit)
	var err := UiKit.label("", 22, p.warn)
	box.add_child(err)
	var row := UiKit.hbox(12)
	var paste := UiKit.button(tr("PASTE"), func(): edit.text = DisplayServer.clipboard_get().strip_edges().left(SeedManager.MAX_CODE_LENGTH))
	paste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var play := UiKit.primary_button(tr("PLAY"), _play_code.bind(edit, err), p.lit, p.lit2, 88)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(paste)
	row.add_child(play)
	box.add_child(row)
	box.add_child(UiKit.button(tr("CANCEL"), _close_overlay, 76))
	_show_overlay(box)


func _start_challenge(index: int) -> void:
	_close_overlay()
	_start(Game.challenge_request(index))


func _play_code(edit: LineEdit, err: Label) -> void:
	var req := SeedManager.parse_code(edit.text)
	if req == null:
		err.text = tr("SEED_INVALID")
		return
	_close_overlay()
	_start(req)


func _show_diagnostics(crashed: bool) -> void:
	_show_overlay(DiagnosticsPanel.build(true, _close_overlay, crashed))


func _show_overlay(content: Control) -> void:
	_close_overlay()
	_overlay = UiKit.modal(self, content)


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func on_back() -> bool:
	if _overlay:
		_close_overlay()
		return true
	return false
