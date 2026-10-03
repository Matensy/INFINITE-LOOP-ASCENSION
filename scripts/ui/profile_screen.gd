extends Control
## Profile: rank, statistics, achievements and prestige.

var main: Node


func _ready() -> void:
	UiKit.full_rect(self)
	var p := Themes.palette
	var safe := UiKit.safe_margins(get_viewport())
	var root := UiKit.margin(null, 36 + int(safe.position.x), 30 + int(safe.position.y), 36 + int(safe.size.x), 24 + int(safe.size.y))
	UiKit.full_rect(root)
	add_child(root)
	var col := UiKit.vbox(12)
	root.add_child(col)
	var header := UiKit.hbox(12)
	header.add_child(UiKit.icon_button("←", func(): main.back(), 80))
	var t := UiKit.title(tr("PROFILE"), 40, p.ui_accent)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(t)
	header.add_child(UiKit.spacer(0))
	col.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body := UiKit.vbox(14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var stats: Dictionary = Save.stats()
	var stars := Game.prestige_stars()
	body.add_child(UiKit.title(tr(Game.title_key()), 34, p.lit))
	if stars > 0:
		body.add_child(UiKit.label("✦ ".repeat(mini(stars, 12)).strip_edges() + ("  ×%d" % stars if stars > 12 else ""), 26, p.ui_accent))
		body.add_child(UiKit.label(tr("PRESTIGE_HELP"), 20, p.ui_dim))

	var card := UiKit.vbox(6)
	var rows := [
		["LEVEL", I18n.format_int(Save.current_level())],
		["HIGHEST_LEVEL", I18n.format_int(Save.highest_level())],
		["PUZZLES_SOLVED", I18n.format_int(int(stats.get("total_solved", 0)))],
		["TOTAL_MOVES", I18n.format_int(int(stats.get("total_moves", 0)))],
		["AVERAGE_MOVES", "%.1f" % Statistics.average_moves(stats)],
		["BEST_TIME", I18n.format_time(float(stats.get("fastest_solve", 0.0))) if float(stats.get("fastest_solve", -1.0)) >= 0.0 else "—"],
		["FEWEST_MOVES", str(stats.get("fewest_moves", "—")) if int(stats.get("fewest_moves", -1)) >= 0 else "—"],
		["HARDEST_PUZZLE", "%d" % int(round(float(stats.get("hardest_solve", 0.0))))],
		["PERFECT_SOLVES", I18n.format_int(int(stats.get("perfect_solves", 0)))],
		["NO_HINT_SOLVES", I18n.format_int(int(stats.get("no_hint_solves", 0)))],
		["STREAK", "%d  (%s %d)" % [int(stats.get("current_streak", 0)), tr("BEST"), int(stats.get("longest_streak", 0))]],
		["DAILY_SOLVED", I18n.format_int(int(stats.get("daily_solved", 0)))],
		["BOSSES", I18n.format_int(int(stats.get("boss_solved", 0)))],
		["TOTAL_TIME", I18n.format_time(float(stats.get("total_time", 0.0)))],
	]
	for r in rows:
		card.add_child(UiKit.stat_row(tr(r[0]), str(r[1]), p.ui_dim, p.ui_text))
	body.add_child(UiKit.panel(card))
	var hardest := str(stats.get("hardest_code", ""))
	if hardest != "":
		body.add_child(UiKit.button(tr("REPLAY_HARDEST"), _replay_code.bind(hardest), 76))

	var favs: Array = Game.favorites()
	if not favs.is_empty():
		body.add_child(UiKit.title("%s  %d" % [tr("FAVORITES"), favs.size()], 30, p.ui_accent))
		for i in range(favs.size() - 1, maxi(-1, favs.size() - 11), -1):
			var b := UiKit.button("★  " + str(favs[i]), _replay_code.bind(str(favs[i])), 70)
			b.add_theme_font_size_override("font_size", 22)
			body.add_child(b)

	var unlocked: Dictionary = Save.data.get("achievements", {})
	var defs := AchievementSystem.definitions()
	body.add_child(UiKit.title("%s  %d/%d" % [tr("ACHIEVEMENTS"), unlocked.size(), defs.size()], 30, p.ui_accent))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for def in defs:
		var id := str(def.get("id", ""))
		var got := unlocked.has(id)
		var cell := UiKit.vbox(4)
		var name := UiKit.label(("🏆 " if got else "🔒 ") + tr("ACH_" + id.to_upper()), 22, p.ui_text if got else p.ui_dim, UiTheme.bold_font())
		var desc := UiKit.label(tr("ACH_" + id.to_upper() + "_DESC"), 18, p.ui_dim)
		cell.add_child(name)
		cell.add_child(desc)
		var panel := UiKit.panel(cell)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.modulate.a = 1.0 if got else 0.55
		grid.add_child(panel)
	body.add_child(grid)


func _replay_code(code: String) -> void:
	var req := SeedManager.parse_code(code)
	if req:
		Game.pending_request = req
		main.goto("game")


func on_back() -> bool:
	return false
