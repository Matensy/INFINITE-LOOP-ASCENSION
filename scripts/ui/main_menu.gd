extends Control
## Title screen: continue the endless climb, daily puzzle, zen, challenges,
## seed entry, profile and settings. A live solved network decorates it.

var main: Node
var _board: BoardView
var _overlay: Control
var _title_tap := 0


func _ready() -> void:
	UiKit.full_rect(self)
	Themes.apply(Themes.resolve_for_puzzle(ThemeCatalog.DEFAULT_ID))
	var p := Themes.palette
	var safe := UiKit.safe_margins(get_viewport())
	var root := UiKit.margin(null, 44 + int(safe.position.x), 40 + int(safe.position.y), 44 + int(safe.size.x), 30 + int(safe.size.y))
	UiKit.full_rect(root)
	add_child(root)
	var col := UiKit.vbox(16)
	root.add_child(col)

	var title := UiKit.title("INFINITE LOOP", 58, p.lit)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_title_input)
	col.add_child(title)
	var sub := UiKit.title("ASCENSION", 40, p.ui_accent.lerp(Color.WHITE, 0.3))
	col.add_child(sub)
	var stars := Game.prestige_stars()
	var rank := "%s · %s %s" % [tr(Game.title_key()), tr("LEVEL"), I18n.format_int(Save.current_level())]
	if stars > 0:
		rank += "  " + "✦".repeat(mini(stars, 5)) + ("+%d" % (stars - 5) if stars > 5 else "")
	col.add_child(UiKit.label(rank, 24, p.ui_dim))

	_board = BoardView.new()
	_board.custom_minimum_size = Vector2(0, 330)
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.attract = true
	_board.interactive = false
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_board)

	var cont := UiKit.primary_button("%s  ·  %s %s" % [tr("CONTINUE"), tr("LEVEL"), I18n.format_int(Save.current_level())], _on_continue, p.ui_accent)
	col.add_child(cont)
	var daily_req := Game.daily_request()
	var daily_txt := tr("DAILY_PUZZLE")
	if Game.is_daily_done(daily_req.label):
		daily_txt += "  ✓"
	col.add_child(UiKit.button(daily_txt, _on_daily))
	var row := UiKit.hbox(14)
	var zen := UiKit.button(tr("ZEN"), _on_zen)
	zen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var challenge := UiKit.button(tr("CHALLENGE"), _on_challenge)
	challenge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(zen)
	row.add_child(challenge)
	col.add_child(row)
	col.add_child(UiKit.button(tr("ENTER_SEED"), _on_seed))
	var row2 := UiKit.hbox(14)
	var prof := UiKit.button(tr("PROFILE"), func(): main.goto("profile"))
	prof.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sett := UiKit.button(tr("SETTINGS"), func(): main.goto("settings"))
	sett.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(prof)
	row2.add_child(sett)
	col.add_child(row2)
	if OS.is_debug_build():
		var dbg := UiKit.button(tr("DEBUG_GENERATOR"), func(): main.goto("debug"), 64)
		dbg.add_theme_font_size_override("font_size", 22)
		col.add_child(dbg)
	col.add_child(UiKit.label("v%s" % ProjectSettings.get_setting("application/config/version", "0.1.0"), 18, Color(p.ui_dim, 0.6)))
	_setup_decoration()


func _setup_decoration() -> void:
	var req := PuzzleRequest.make(PuzzleRequest.Kind.DEBUG, 60, 4242)
	req.force_mode = GameMode.CORE
	req.force_target = 18.0
	var p := Game.generator.generate_now(req)
	var solved := BoardState.new(p, p.solution_rotations())
	_board.palette = Themes.palette
	_board.set_effects(float(Save.setting("animation_speed", 1.0)), bool(Save.setting("reduce_motion", false)), str(Save.setting("effects", "high")) == "high")
	_board.show_puzzle(p, solved)
	_board.set_process(true)


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
	var box := UiKit.vbox(14)
	box.add_child(UiKit.title(tr("CHALLENGE"), 36, Themes.palette.ui_accent))
	box.add_child(UiKit.label(tr("CHALLENGE_DESC"), 22, Themes.palette.ui_dim))
	for i in Game.CHALLENGES.size():
		var ch: Dictionary = Game.CHALLENGES[i]
		var label := "%s  ·  %d" % [tr("TIER_" + str(ch["id"]).to_upper()), int(ch["target"])]
		box.add_child(UiKit.button(label, _start_challenge.bind(i)))
	box.add_child(UiKit.button(tr("CANCEL"), _close_overlay, 72))
	_show_overlay(box)


func _on_seed() -> void:
	var box := UiKit.vbox(16)
	box.add_child(UiKit.title(tr("ENTER_SEED"), 36, Themes.palette.ui_accent))
	box.add_child(UiKit.label(tr("SEED_HELP"), 22, Themes.palette.ui_dim))
	var edit := LineEdit.new()
	edit.placeholder_text = "ASCENSION-18492-839204918230"
	edit.custom_minimum_size = Vector2(0, 84)
	box.add_child(edit)
	var err := UiKit.label("", 22, Themes.palette.warn)
	box.add_child(err)
	var row := UiKit.hbox(12)
	var paste := UiKit.button(tr("PASTE"), func(): edit.text = DisplayServer.clipboard_get().strip_edges().left(SeedManager.MAX_CODE_LENGTH))
	paste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var play := UiKit.button(tr("PLAY"), _play_code.bind(edit, err))
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(paste)
	row.add_child(play)
	box.add_child(row)
	box.add_child(UiKit.button(tr("CANCEL"), _close_overlay, 72))
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


func _show_overlay(content: Control) -> void:
	_close_overlay()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.6)
	UiKit.full_rect(_overlay)
	add_child(_overlay)
	var center := CenterContainer.new()
	UiKit.full_rect(center)
	_overlay.add_child(center)
	var panel := UiKit.panel(content)
	panel.custom_minimum_size = Vector2(minf(620, get_viewport_rect().size.x - 60), 0)
	center.add_child(panel)


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func on_back() -> bool:
	if _overlay:
		_close_overlay()
		return true
	return false
